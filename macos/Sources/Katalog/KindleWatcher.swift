import AppKit
import Foundation
import KatalogCore

/// A mounted removable reader (Kindle) exposed as a copy target.
struct Device: Identifiable, Hashable {
    let volume: URL
    var id: URL { volume }
    var name: String { volume.lastPathComponent }
    var documents: URL { volume.appendingPathComponent("documents", isDirectory: true) }
}

/// A running Kindle send/remove, shown in the status bar while in flight.
struct KindleJob: Identifiable, Equatable {
    let id = UUID()
    let bookId: Int64
    let title: String
    let deviceName: String
    enum Kind { case send, remove }
    let kind: Kind
    var verb: String { kind == .send ? "Sending" : "Removing" }
}

extension Book {
    /// Stable, unique filename this book gets on a device. Deterministic so we
    /// can both write it and detect it — the basis of duplicate detection.
    var deviceFilename: String {
        let author = authors.first ?? "Unknown"
        let base = deviceSanitize("\(title) - \(author)")
        return "\(base).mobi"  // we convert epub → MOBI before transfer
    }
}

private func deviceSanitize(_ s: String) -> String {
    let bad = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
    let cleaned = String(s.unicodeScalars.map { bad.contains($0) ? "_" : Character($0) })
    let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? "_" : String(trimmed.prefix(120))
}

/// Watches mounted volumes for Kindles (a volume with a `documents/` folder).
/// Detection + copy live here — inherently platform-specific, so Foundation
/// owns them; the core just hands us the validated source path.
final class KindleWatcher: NSObject, ObservableObject {
    @Published private(set) var devices: [Device] = []
    /// Match keys for every book on the connected devices (union). Built from
    /// real epub metadata where possible, else the filename — see core file_keys.
    @Published private(set) var deviceKeys: Set<String> = []
    /// True while the background key-scan of a connected device is in flight.
    @Published private(set) var scanning = false
    /// Completed and total files in the current scan. Keys are published as
    /// each file completes, so matches appear before this reaches the total.
    @Published private(set) var scanProgress: (done: Int, total: Int) = (0, 0)
    /// A new scan invalidates callbacks from an older mount notification.
    private var scanGeneration = UUID()
    /// In-flight send/remove operations. Owned here (not by the book detail
    /// view) so they keep running — and stay visible in the status bar — after
    /// the detail page closes. This small array is the whole "job system": a
    /// desktop app with one Kindle doesn't need a queue, persistence, or retry.
    @Published private(set) var jobs: [KindleJob] = []
    /// Last failed operation, surfaced in the reader toolbar menu until dismissed.
    @Published var lastFailure: String?

    // A user-selected security-scoped URL is stronger than the removable-volume
    // entitlement on recent macOS builds, where reading a mounted Kindle works
    // but creating files in documents/ can still be denied. Reuse the grant
    // captured by the access picker rather than the unscoped mount-list URL.
    private var authorizedVolume: URL?
    private static let volumeBookmarkKey = "kindleVolumeBookmark"

    /// Whether a send or remove for this book is currently running.
    func busy(_ book: Book) -> Bool { jobs.contains { $0.bookId == book.id } }

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.volumeBookmarkKey) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                  relativeTo: nil, bookmarkDataIsStale: &stale),
               url.startAccessingSecurityScopedResource() {
                authorizedVolume = url
                if stale, let refreshed = try? url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    UserDefaults.standard.set(refreshed, forKey: Self.volumeBookmarkKey)
                }
            }
        }
        rescan()
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(volumesChanged),
                       name: NSWorkspace.didMountNotification, object: nil)
        nc.addObserver(self, selector: #selector(volumesChanged),
                       name: NSWorkspace.didUnmountNotification, object: nil)
    }

    @objc private func volumesChanged() { rescan() }

    /// Detecting a device is cheap (volume list + a stat), so do it synchronously
    /// — the reader shows as mounted immediately. Reading every MOBI/AZW file for
    /// its match keys is the slow part, so scan contents in the background (else
    /// init() and the mount notifications would stall the window / freeze the UI)
    /// and flag `scanning` so the UI can show a spinner until keys are ready.
    func rescan() {
        let fm = FileManager.default
        let vols = fm.mountedVolumeURLs(
            includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]
        ) ?? []
        devices = vols.filter(isKindle).map { mounted in
            if let authorizedVolume, authorizedVolume.path == mounted.path {
                return Device(volume: authorizedVolume)
            }
            return Device(volume: mounted)
        }
        scanGeneration = UUID()
        let generation = scanGeneration
        guard !devices.isEmpty else {
            deviceKeys = []; scanProgress = (0, 0); scanning = false; return
        }

        // Enumerate up front so the UI immediately gets a real total. Clear old
        // keys because they may belong to a Kindle that was just unplugged.
        let scans = devices.map { ($0, bookFiles(in: $0.documents)) }
        let total = scans.reduce(0) { $0 + $1.1.count }
        deviceKeys = []
        scanProgress = (0, total)
        scanning = total > 0
        guard total > 0 else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var done = 0
            for (device, files) in scans {
                self.scanKeys(device, files: files) { keys in
                    done += 1
                    let currentDone = done
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.scanGeneration == generation else { return }
                        self.deviceKeys.formUnion(keys)
                        self.scanProgress = (currentDone, total)
                        if currentDone == total { self.scanning = false }
                    }
                }
            }
        }
    }

    // MARK: - On-device key cache
    //
    // Reading every book's metadata on each connect is the slow part (see
    // rescan). We cache each file's match keys in a hidden index at the device
    // root — same idea as Calibre's metadata.calibre, but keyed on size *and*
    // mtime (Calibre uses size alone, so a same-size edit slips through) and
    // covering every book including native Amazon content Calibre's own cache
    // ignores. A reconnect then re-parses only files that are new or changed.

    private struct CacheEntry: Codable { let size: Int64; let mtime: Int64; let keys: [String] }

    private func indexURL(_ dev: Device) -> URL {
        dev.volume.appendingPathComponent(".katalog-index.json")
    }

    /// A file's device-relative path — the index key. Relative so the cache
    /// survives the mount moving (e.g. /Volumes/Kindle → /Volumes/Kindle 1).
    private func lpath(_ file: URL, on dev: Device) -> String {
        let prefix = dev.volume.path.hasSuffix("/") ? dev.volume.path : dev.volume.path + "/"
        return file.path.hasPrefix(prefix) ? String(file.path.dropFirst(prefix.count)) : file.path
    }

    private func loadIndex(_ dev: Device) -> [String: CacheEntry] {
        (try? JSONDecoder().decode(
            [String: CacheEntry].self, from: Data(contentsOf: indexURL(dev)))) ?? [:]
    }

    /// Match keys for every book on a device, re-parsing only files whose size
    /// or mtime changed since the last connect. Rewrites the on-device index
    /// when anything was added, changed, or removed. Index keys are paths
    /// relative to the volume, so the cache survives the mount moving (e.g.
    /// /Volumes/Kindle → /Volumes/Kindle 1).
    private func scanKeys(_ dev: Device, files: [URL], publish: (Set<String>) -> Void) {
        let old = loadIndex(dev)
        var fresh: [String: CacheEntry] = [:]
        var dirty = false
        var changesSinceSave = 0

        func save() {
            guard let data = try? JSONEncoder().encode(fresh) else { return }
            // Atomic replacement avoids leaving a truncated index if the Kindle
            // is unplugged during a long first scan.
            try? data.write(to: indexURL(dev), options: .atomic)
        }

        for file in files {
            let vals = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(vals?.fileSize ?? 0)
            let mtime = Int64(vals?.contentModificationDate?.timeIntervalSince1970 ?? 0)
            let key = lpath(file, on: dev)
            let entry: CacheEntry
            if let hit = old[key], hit.size == size, hit.mtime == mtime {
                entry = hit
            } else {
                entry = CacheEntry(size: size, mtime: mtime,
                                   keys: (try? fileKeys(path: file.path)) ?? [])
                dirty = true
                changesSinceSave += 1
            }
            fresh[key] = entry
            publish(Set(entry.keys))

            // Preserve useful work during a first scan rather than waiting for
            // every MOBI parser invocation to finish.
            if changesSinceSave >= 10 {
                save()
                changesSinceSave = 0
            }
        }
        if dirty || fresh.count != old.count { save() }
    }

    private static let ebookExts: Set<String> = ["epub", "mobi", "azw", "azw3", "prc", "kfx"]

    /// Recursively find ebook files under a device — Kindles organize books in
    /// Author/ subfolders. Skips hidden/AppleDouble files and .sdr sidecars.
    private func bookFiles(in root: URL) -> [URL] {
        guard let en = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in en {
            if url.pathComponents.contains(where: { $0.hasSuffix(".sdr") }) { continue }
            if Self.ebookExts.contains(url.pathExtension.lowercased()) { files.append(url) }
        }
        return files
    }

    /// Match keys per book, memoized on title+isbn. `onDevice` is called for
    /// every visible tile on every render; without this each one crossed the FFI
    /// boundary into Rust just to rebuild the same key set.
    private var keyCache: [String: Set<String>] = [:]

    /// Whether this book is on a connected device — same match-key primitive the
    /// core uses for duplicate detection, so import dedup and this agree.
    func onDevice(_ book: Book) -> Bool {
        guard !deviceKeys.isEmpty else { return false }  // no reader: nothing to match
        let cacheKey = "\(book.title)\u{1}\(book.isbn ?? "")"
        let keys = keyCache[cacheKey] ?? {
            let keys = Set(bookKeys(title: book.title, isbn: book.isbn))
            keyCache[cacheKey] = keys
            return keys
        }()
        return !keys.isDisjoint(with: deviceKeys)
    }

    private func isKindle(_ vol: URL) -> Bool {
        vol.lastPathComponent.lowercased().contains("kindle")
    }

    @MainActor private func requestAccess(to device: Device) -> Device? {
        let panel = NSOpenPanel()
        panel.message = "Choose your Kindle to let Katalog send and remove books."
        panel.prompt = "Allow Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = device.volume
        guard panel.runModal() == .OK, let url = panel.url,
              let bookmark = try? url.bookmarkData(options: .withSecurityScope,
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        UserDefaults.standard.set(bookmark, forKey: Self.volumeBookmarkKey)
        authorizedVolume = url
        rescan()
        return Device(volume: url)
    }

    private func withAccess(to device: Device, _ operation: (Device) throws -> Void) async throws {
        do { try operation(device) }
        catch {
            let e = error as NSError
            let denied = (e.domain == NSCocoaErrorDomain &&
                          [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(e.code)) ||
                         (e.domain == NSPOSIXErrorDomain && [EACCES, EPERM].contains(Int32(e.code)))
            guard denied, let authorized = await requestAccess(to: device) else { throw error }
            try operation(authorized)
        }
    }

    // MARK: - Owned operations
    //
    // These run the work in a watcher-owned task and track it in `jobs`, so it
    // survives the book detail page closing and shows in the status bar. The
    // view kicks one off and forgets it.

    /// Convert `epubPath` to MOBI and copy it to the reader, in the background.
    func send(_ book: Book, epubPath: String, to device: Device) {
        let job = KindleJob(bookId: book.id, title: book.title, deviceName: device.name, kind: .send)
        lastFailure = nil
        jobs.append(job)
        Task.detached { [weak self] in
            do {
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).appendingPathExtension("mobi")
                try convertEpubToMobi(epubPath: epubPath, outPath: tmp.path)
                try await self?.withAccess(to: device) {
                    try self?.performTransfer(book, from: tmp.path, to: $0)
                }
                try? FileManager.default.removeItem(at: tmp)
                await self?.finish(job, error: nil)
            } catch { await self?.finish(job, error: error.localizedDescription) }
        }
    }

    /// Delete this book's copies from the reader, in the background.
    func remove(_ book: Book, from device: Device) {
        let job = KindleJob(bookId: book.id, title: book.title, deviceName: device.name, kind: .remove)
        lastFailure = nil
        jobs.append(job)
        Task.detached { [weak self] in
            do {
                try await self?.withAccess(to: device) { try self?.performRemove(book, from: $0) }
                await self?.finish(job, error: nil)
            }
            catch { await self?.finish(job, error: error.localizedDescription) }
        }
    }

    /// Drop a finished job and surface any failure. Hops to main for @Published.
    @MainActor private func finish(_ job: KindleJob, error: String?) {
        jobs.removeAll { $0.id == job.id }
        if let error { lastFailure = "\(job.verb) \(job.title): \(error)" }
    }

    /// Copy the epub at `srcPath` into the device's documents folder under the
    /// book's stable `deviceFilename`. Overwrites an existing copy of the same
    /// book; refresh the scan so the "on device" state updates.
    private func performTransfer(_ book: Book, from srcPath: String, to device: Device) throws {
        let fm = FileManager.default
        let src = URL(fileURLWithPath: srcPath)
        let dest = device.documents.appendingPathComponent(book.deviceFilename)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: src, to: dest)
        // Record the file we just wrote in the on-device index so the next
        // reconnect reuses its keys instead of re-parsing it. Keys come from
        // fileKeys (the same primitive scanKeys uses), so this entry is
        // indistinguishable from one a full scan would produce.
        let vals = try? dest.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        var index = loadIndex(device)
        index[lpath(dest, on: device)] = CacheEntry(
            size: Int64(vals?.fileSize ?? 0),
            mtime: Int64(vals?.contentModificationDate?.timeIntervalSince1970 ?? 0),
            keys: (try? fileKeys(path: dest.path)) ?? [])
        if let data = try? JSONEncoder().encode(index) { try? data.write(to: indexURL(device)) }
        // Update the "on device" state directly rather than kicking off a full
        // background rescan (which lands late and briefly flips the button back
        // to its pre-send state). Callers run this off-main, so hop back to
        // touch the @Published set.
        let added = bookKeys(title: book.title, isbn: book.isbn)
        DispatchQueue.main.async { self.deviceKeys.formUnion(added) }
    }

    /// Delete every copy of this book from the device — matched by the same keys
    /// the "on device" badge uses, so what shows as present is exactly what we
    /// remove. Also clears the `.sdr` sidecar folder Kindle keeps per book.
    private func performRemove(_ book: Book, from device: Device) throws {
        let fm = FileManager.default
        let keys = Set(bookKeys(title: book.title, isbn: book.isbn))
        var index = loadIndex(device)
        var prunedIndex = false
        for file in bookFiles(in: device.documents) {
            let key = lpath(file, on: device)
            // Match against cached keys — parsing every file here is what made
            // remove slow (it re-read all books to find the one to delete). Fall
            // back to a parse only for a file the index doesn't know yet.
            let fileK = index[key]?.keys ?? (try? fileKeys(path: file.path)) ?? []
            guard !Set(fileK).isDisjoint(with: keys) else { continue }
            try fm.removeItem(at: file)
            if index.removeValue(forKey: key) != nil { prunedIndex = true }
            let sidecar = file.deletingPathExtension().appendingPathExtension("sdr")
            if fm.fileExists(atPath: sidecar.path) { try? fm.removeItem(at: sidecar) }
        }
        // Drop the deleted files from the on-device index now, so it doesn't
        // carry dead entries until the next reconnect rebuilds it.
        if prunedIndex, let data = try? JSONEncoder().encode(index) {
            try? data.write(to: indexURL(device))
        }
        // ponytail: subtract the removed book's keys directly — correct for the
        // usual single connected Kindle. A book shared across two mounted devices
        // would need per-device key sets; mount/unmount rescan rebuilds the union.
        // Callers run this off the main thread (the scan is slow I/O), so hop back
        // to update the @Published set.
        DispatchQueue.main.async { self.deviceKeys.subtract(keys) }
    }
}
