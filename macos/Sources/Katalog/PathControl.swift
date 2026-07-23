import AppKit
import SwiftUI

/// The native Finder-style breadcrumb (folder icons + names). Clicking a
/// component opens it in Finder — same as Apple Music's Media Location.
struct PathControl: NSViewRepresentable {
    let path: String

    func makeNSView(context: Context) -> NSPathControl {
        let pc = NSPathControl()
        pc.pathStyle = .standard
        pc.isEditable = false
        pc.focusRingType = .none
        pc.target = context.coordinator
        pc.action = #selector(Coordinator.clicked(_:))
        pc.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return pc
    }

    func updateNSView(_ pc: NSPathControl, context: Context) {
        pc.url = URL(fileURLWithPath: path)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        @objc func clicked(_ sender: NSPathControl) {
            guard let url = sender.clickedPathItem?.url ?? sender.url else { return }
            NSWorkspace.shared.open(url) // open the folder in Finder
        }
    }
}
