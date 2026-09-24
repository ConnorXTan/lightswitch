import AppKit
import ServiceManagement
import SwiftUI
import LightswitchKit

/// The menu bar extra's menu.
struct StatusMenu: View {
    @ObservedObject private var store = SessionStore.shared
    @ObservedObject private var hooks = HooksModel.shared

    var body: some View {
        Text(summary)
        if !hooks.isInstalled {
            Button("Install Claude Code Hooks…") { hooks.install() }
        }
        Button("Open Notch") {
            NotchCoordinator.shared.toggleAll()
        }
        Divider()
        if Bundle.main.bundleIdentifier != nil {
            Toggle("Launch at Login", isOn: launchAtLogin)
        }
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

    /// Registers the app as a login item; only meaningful from a bundle.
    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    Log.note(Log.app, "launch at login: \(error.localizedDescription)")
                }
            })
    }

    private var summary: String {
        if !hooks.isInstalled { return "Hooks not installed" }
        let red = store.sessions.filter { $0.state == .needsYou }.count
        let n = store.sessions.count
        var text = n == 1 ? "1 session" : "\(n) sessions"
        if red > 0 { text += " · \(red) need\(red == 1 ? "s" : "") you" }
        return text
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
