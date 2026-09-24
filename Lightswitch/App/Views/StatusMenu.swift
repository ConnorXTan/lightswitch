import AppKit
import SwiftUI
import LightswitchKit

/// The menu bar extra's menu.
struct StatusMenu: View {
    @EnvironmentObject private var coordinator: NotchCoordinator

    var body: some View {
        Button("Open Notch") {
            NotchCoordinator.shared.toggleAll()
        }
        Divider()
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Lightswitch") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

/// The menu bar icon: four dots, drawn as a template image so it follows the
/// menu bar's light or dark appearance.
enum StatusIcon {
    static func image() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            let dot: CGFloat = 3
            let gap: CGFloat = 1.5
            let total = dot * 2 + gap
            let x0 = rect.midX - total / 2
            let y0 = rect.midY - total / 2
            for row in 0..<2 {
                for col in 0..<2 {
                    let r = NSRect(x: x0 + CGFloat(col) * (dot + gap),
                                   y: y0 + CGFloat(row) * (dot + gap),
                                   width: dot, height: dot)
                    NSBezierPath(ovalIn: r).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
