import AppKit
import Foundation

/// A mounted removable reader (Kindle) exposed as a copy target.
struct Device: Identifiable, Hashable {
    let volume: URL
    var id: URL { volume }
    var name: String { volume.lastPathComponent }
    var documents: URL { volume.appendingPathComponent("documents", isDirectory: true) }
}

/// Watches mounted volumes for Kindles (a volume with a `documents/` folder).
/// Detection + copy live here — inherently platform-specific, so Foundation
/// owns them; the core just hands us the validated source path.
final class KindleWatcher: NSObject, ObservableObject {
    @Published private(set) var devices: [Device] = []

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
    }

    private func isKindle(_ vol: URL) -> Bool {
        var isDir: ObjCBool = false
        let docs = vol.appendingPathComponent("documents").path
        let hasDocs = FileManager.default.fileExists(atPath: docs, isDirectory: &isDir) && isDir.boolValue
        return hasDocs && vol.lastPathComponent.lowercased().contains("kindle")
    }

    /// Copy the epub at `srcPath` into the device's documents folder.
    func transfer(from srcPath: String, to device: Device) throws {
        let fm = FileManager.default
        let src = URL(fileURLWithPath: srcPath)
        let dest = device.documents.appendingPathComponent(src.lastPathComponent)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: src, to: dest)
    }
}
