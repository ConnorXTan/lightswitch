import AppKit
import Darwin

/// A window-server space at the top of the stack, so the notch stays visible
/// over fullscreen apps and above the menu bar. The entry points live in the
/// private SkyLight framework; they are resolved at runtime and, if any is
/// missing, nothing is done — the panel then simply keeps its (already very
/// high) AppKit window level.
@MainActor
final class PrivateSpace {
    static let shared = PrivateSpace()

    private typealias DefaultConnection = @convention(c) () -> UInt32
    private typealias SpaceCreate = @convention(c) (UInt32, Int, CFDictionary?) -> UInt64
    private typealias SpaceSetLevel = @convention(c) (UInt32, UInt64, Int) -> Void
    private typealias SpacesShow = @convention(c) (UInt32, CFArray) -> Void
    private typealias WindowsSpaces = @convention(c) (UInt32, CFArray, CFArray) -> Void

    private let connection: UInt32
    private let space: UInt64
    private let addWindows: WindowsSpaces?
    private let removeWindows: WindowsSpaces?

    /// True when the private API resolved and the space exists.
    let available: Bool

    private init() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let cidSym = dlsym(handle, "_CGSDefaultConnection"),
              let createSym = dlsym(handle, "CGSSpaceCreate"),
              let levelSym = dlsym(handle, "CGSSpaceSetAbsoluteLevel"),
              let showSym = dlsym(handle, "CGSShowSpaces"),
              let addSym = dlsym(handle, "CGSAddWindowsToSpaces"),
              let removeSym = dlsym(handle, "CGSRemoveWindowsFromSpaces")
        else {
            connection = 0
            space = 0
            addWindows = nil
            removeWindows = nil
            available = false
            return
        }

        let cid = unsafeBitCast(cidSym, to: DefaultConnection.self)()
        let create = unsafeBitCast(createSym, to: SpaceCreate.self)
        let setLevel = unsafeBitCast(levelSym, to: SpaceSetLevel.self)
        let show = unsafeBitCast(showSym, to: SpacesShow.self)

        // The flag must be 1; anything else makes Finder draw desktop icons
        // into the new space.
        let id = create(cid, 1, nil)
        setLevel(cid, id, Int(Int32.max))
        show(cid, [id] as CFArray)

        connection = cid
        space = id
        addWindows = unsafeBitCast(addSym, to: WindowsSpaces.self)
        removeWindows = unsafeBitCast(removeSym, to: WindowsSpaces.self)
        available = true
    }

    func add(_ window: NSWindow) {
        guard available, let addWindows else { return }
        addWindows(connection, [window.windowNumber] as CFArray, [space] as CFArray)
    }

    func remove(_ window: NSWindow) {
        guard available, let removeWindows else { return }
        removeWindows(connection, [window.windowNumber] as CFArray, [space] as CFArray)
    }
}
