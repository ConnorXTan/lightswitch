import AppKit
import SwiftUI

/// A transparent, non-activating panel pinned above the menu bar. The window
/// server passes clicks through its fully transparent pixels, so only the
/// black shape is interactive.
final class NotchWindow: NSPanel {
    init<Content: View>(rootView: Content) {
        let rect = NSRect(origin: .zero, size: NotchMetrics.windowSize)
        super.init(contentRect: rect,
                   styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        level = .mainMenu + 3
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]

        let host = NSHostingView(rootView: rootView)
        host.sizingOptions = []
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
