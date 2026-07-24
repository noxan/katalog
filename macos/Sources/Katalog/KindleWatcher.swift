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
            let keys = Set(devices.flatMap { dev in
                self.bookFiles(in: dev.documents).flatMap { (try? fileKeys(path: $0.path)) ?? [] }
            })
            DispatchQueue.main.async {
                self.deviceKeys = keys
                self.scanning = false
            }
        }
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
        // briefly flips the button back to its pre-send state).
        deviceKeys.formUnion(bookKeys(title: book.title, isbn: book.isbn))
    }

    /// Delete every copy of this book from the device — matched by the same keys
    /// the "on device" badge uses, so what shows as present is exactly what we
    /// remove. Also clears the `.sdr` sidecar folder Kindle keeps per book.
    func remove(_ book: Book, from device: Device) throws {
        let fm = FileManager.default
        let keys = Set(bookKeys(title: book.title, isbn: book.isbn))
        for file in bookFiles(in: device.documents) {
            guard !Set((try? fileKeys(path: file.path)) ?? []).isDisjoint(with: keys) else { continue }
            try fm.removeItem(at: file)
            let sidecar = file.deletingPathExtension().appendingPathExtension("sdr")
            if fm.fileExists(atPath: sidecar.path) { try? fm.removeItem(at: sidecar) }
        }
        // ponytail: subtract the removed book's keys directly — correct for the
        // usual single connected Kindle. A book shared across two mounted devices
        // would need per-device key sets; mount/unmount rescan rebuilds the union.
        // Callers run this off the main thread (the scan is slow I/O), so hop back
        // to update the @Published set.
        DispatchQueue.main.async { self.deviceKeys.subtract(keys) }
    }
}
