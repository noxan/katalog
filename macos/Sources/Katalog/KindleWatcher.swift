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

    override init() {
        super.init()
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
        devices = vols.filter(isKindle).map(Device.init)
        guard !devices.isEmpty else { deviceKeys = []; scanning = false; return }

        scanning = true
        let devices = self.devices
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let keys = devices.reduce(into: Set<String>()) { $0.formUnion(self.scanKeys($1)) }
            DispatchQueue.main.async {
                self.deviceKeys = keys
                self.scanning = false
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
    private func scanKeys(_ dev: Device) -> Set<String> {
        let old = loadIndex(dev)
        var fresh: [String: CacheEntry] = [:]
        var changed = false
        for file in bookFiles(in: dev.documents) {
            let vals = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(vals?.fileSize ?? 0)
            let mtime = Int64(vals?.contentModificationDate?.timeIntervalSince1970 ?? 0)
            let key = lpath(file, on: dev)
            if let hit = old[key], hit.size == size, hit.mtime == mtime {
                fresh[key] = hit
            } else {
                fresh[key] = CacheEntry(size: size, mtime: mtime,
                                        keys: (try? fileKeys(path: file.path)) ?? [])
                changed = true
            }
        }
        if changed || fresh.count != old.count,  // count drop => a file was removed
           let data = try? JSONEncoder().encode(fresh) {
            try? data.write(to: indexURL(dev))
        }
        return Set(fresh.values.flatMap(\.keys))
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

    /// Whether this book is on a connected device — same match-key primitive the
    /// core uses for duplicate detection, so import dedup and this agree.
    func onDevice(_ book: Book) -> Bool {
        !Set(bookKeys(title: book.title, isbn: book.isbn)).isDisjoint(with: deviceKeys)
    }

    private func isKindle(_ vol: URL) -> Bool {
        var isDir: ObjCBool = false
        let docs = vol.appendingPathComponent("documents").path
        let hasDocs = FileManager.default.fileExists(atPath: docs, isDirectory: &isDir) && isDir.boolValue
        return hasDocs && vol.lastPathComponent.lowercased().contains("kindle")
    }

    /// Copy the epub at `srcPath` into the device's documents folder under the
    /// book's stable `deviceFilename`. Overwrites an existing copy of the same
    /// book; refresh the scan so the "on device" state updates.
    func transfer(_ book: Book, from srcPath: String, to device: Device) throws {
        let fm = FileManager.default
        let src = URL(fileURLWithPath: srcPath)
        let dest = device.documents.appendingPathComponent(book.deviceFilename)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: src, to: dest)
        // We know exactly what we added — update the "on device" state directly
        // rather than kicking off a full background rescan (which lands late and
        // briefly flips the button back to its pre-send state). Callers run this
        // off-main, so hop back to touch the @Published set.
        let added = bookKeys(title: book.title, isbn: book.isbn)
        DispatchQueue.main.async { self.deviceKeys.formUnion(added) }
    }

    /// Delete every copy of this book from the device — matched by the same keys
    /// the "on device" badge uses, so what shows as present is exactly what we
    /// remove. Also clears the `.sdr` sidecar folder Kindle keeps per book.
    func remove(_ book: Book, from device: Device) throws {
        let fm = FileManager.default
        let keys = Set(bookKeys(title: book.title, isbn: book.isbn))
        var index = loadIndex(device)
        var prunedIndex = false
        for file in bookFiles(in: device.documents) {
            guard !Set((try? fileKeys(path: file.path)) ?? []).isDisjoint(with: keys) else { continue }
            try fm.removeItem(at: file)
            if index.removeValue(forKey: lpath(file, on: device)) != nil { prunedIndex = true }
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
