import AppKit
import SwiftUI

/// Keeps a hidden AppKit view in the hierarchy so SwiftUI code can reach the
/// hosting window whenever it needs it. The window is looked up at the time
/// of asking, not captured when the view is made: at that moment the view
/// is not in a window yet.
final class WindowHandle {
    fileprivate weak var view: NSView?
    var window: NSWindow? { view?.window }
}

struct WindowReader: NSViewRepresentable {
    let handle: WindowHandle

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.isHidden = true
        handle.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        handle.view = view
    }
}
