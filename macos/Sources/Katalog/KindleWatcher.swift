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
        return "\(base).epub"  // becomes .azw3 once conversion lands
    }
}

/// Lowercase, keep only alphanumerics — a loose key for matching titles to
/// device filenames regardless of punctuation, spacing, or format.
private func normalizeKey(_ s: String) -> String {
    String(String.UnicodeScalarView(
        s.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains)
    ))
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
    /// Filenames present in the connected devices' documents/ folders (union).
    @Published private(set) var deviceFiles: Set<String> = []
    /// Normalized filename stems on the device, for fuzzy title matching.
    @Published private(set) var deviceStems: Set<String> = []

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

    func rescan() {
        let fm = FileManager.default
        let vols = fm.mountedVolumeURLs(
            includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]
        ) ?? []
        devices = vols.filter(isKindle).map(Device.init)
        // ponytail: top-level only; Kindles keep books in documents/ directly.
        let names = devices.flatMap { dev in
            (try? fm.contentsOfDirectory(atPath: dev.documents.path)) ?? []
        }
        deviceFiles = Set(names)
        deviceStems = Set(names
            .map { normalizeKey(($0 as NSString).deletingPathExtension) }
            .filter { !$0.isEmpty })
    }

    /// Whether this book appears to be on a connected device. Matches our exact
    /// transfer name, else the book's title against the device's filenames
    /// (works for books sideloaded any way, in any format).
    func onDevice(_ book: Book) -> Bool {
        if deviceFiles.contains(book.deviceFilename) { return true }
        let title = normalizeKey(book.title)
        guard !title.isEmpty else { return false }
        // Short titles must match a whole stem; longer ones can be a substring.
        return title.count >= 4
            ? deviceStems.contains { $0.contains(title) }
            : deviceStems.contains(title)
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
        rescan()
    }
}
