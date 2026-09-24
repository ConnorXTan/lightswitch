import AppKit

/// Development aid: with `LIGHTSWITCH_SNAPSHOT_DIR` set, `kill -USR1 <pid>`
/// writes a PNG of every notch window into that directory, composited over a
/// neutral grey so the black shape and white text both read, and `kill -USR2`
/// toggles the notch open. Two images are written per window: the window
/// server's composite (needs Screen Recording permission, otherwise blank)
/// and the view hierarchy drawn offscreen (always works). Together they let
/// the layout be checked from a terminal, or on a locked screen.
@MainActor
final class Snapshotter {
    private var source: DispatchSourceSignal?
    private var toggleSource: DispatchSourceSignal?
    private let directory: URL
    private let windows: () -> [NSWindow]
    private var counter = 0

    init?(windows: @escaping () -> [NSWindow]) {
        guard let dir = ProcessInfo.processInfo.environment["LIGHTSWITCH_SNAPSHOT_DIR"], !dir.isEmpty else {
            return nil
        }
        directory = URL(fileURLWithPath: dir, isDirectory: true)
        self.windows = windows
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in self?.snapshotAll() }
        source.resume()
        self.source = source

        // SIGUSR2 toggles every notch open/closed, for inspecting the open layout.
        signal(SIGUSR2, SIG_IGN)
        let toggle = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
        toggle.setEventHandler { NotchCoordinator.shared.toggleAll() }
        toggle.resume()
        self.toggleSource = toggle
        FileHandle.standardError.write(Data("snapshots: \(directory.path) (kill -USR1 \(ProcessInfo.processInfo.processIdentifier))\n".utf8))
    }

    func snapshotAll() {
        counter += 1
        for (index, window) in windows().enumerated() {
            let cv = window.contentView
            FileHandle.standardError.write(Data("window \(index) frame=\(window.frame) content=\(cv?.frame ?? .zero) subviews=\(cv?.subviews.map { "\(type(of: $0)) \($0.frame)" } ?? []) visible=\(window.isVisible) occluded=\(!window.occlusionState.contains(.visible)) activeSpace=\(window.isOnActiveSpace) level=\(window.level.rawValue) space=\(PrivateSpace.shared.available)\n".utf8))
            for (method, image) in [("server", Self.serverImage(of: window)), ("view", Self.viewImage(of: window))] {
                guard let image else { FileHandle.standardError.write(Data("snapshot \(method): nil\n".utf8)); continue }
                let url = directory.appendingPathComponent(String(format: "%02d-window%d-%@.png", counter, index, method))
                if let png = Self.png(image, over: NSColor(white: 0.45, alpha: 1)) {
                    try? png.write(to: url)
                    FileHandle.standardError.write(Data("snapshot \(url.lastPathComponent) \(image.width)x\(image.height)\n".utf8))
                }
            }
        }
    }

    /// The window server's composited image of the window (shadow included).
    private static func serverImage(of window: NSWindow) -> CGImage? {
        let id = CGWindowID(window.windowNumber)
        return CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution])
    }

    /// The view hierarchy drawn into a bitmap, independent of the window server.
    private static func viewImage(of window: NSWindow) -> CGImage? {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage
    }

    private static func png(_ image: CGImage, over background: NSColor) -> Data? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(background.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: out)
        return rep.representation(using: .png, properties: [:])
    }
}
