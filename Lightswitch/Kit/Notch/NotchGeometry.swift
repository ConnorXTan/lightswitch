import AppKit

/// Where the notch is and how big the closed black shape has to be.
///
/// The rule is pure so it can be tested without a display: the width is the
/// physical notch plus 4 pt so the shape covers the notch's anti-aliased edge,
/// and the height is the notch on notched Macs or the menu bar elsewhere.
public enum NotchGeometry {
    /// Width used when a screen reports no auxiliary areas (no notch).
    public static let fallbackWidth: CGFloat = 185
    /// Height used when neither a notch nor a menu bar can be measured.
    public static let fallbackHeight: CGFloat = 32
    /// How far the black shape bleeds past the physical notch on each side.
    public static let bleed: CGFloat = 2

    public static func closedSize(screenWidth: CGFloat,
                                  leftAuxWidth: CGFloat?,
                                  rightAuxWidth: CGFloat?,
                                  safeAreaTop: CGFloat,
                                  menuBarHeight: CGFloat) -> CGSize {
        var width = fallbackWidth
        if let l = leftAuxWidth, let r = rightAuxWidth, l > 0, r > 0, screenWidth > l + r {
            width = screenWidth - l - r + bleed * 2
        }
        var height = safeAreaTop > 0 ? safeAreaTop : menuBarHeight
        if height <= 0 { height = fallbackHeight }
        return CGSize(width: width, height: height)
    }

    @MainActor
    public static func closedSize(for screen: NSScreen) -> CGSize {
        closedSize(screenWidth: screen.frame.width,
                   leftAuxWidth: screen.auxiliaryTopLeftArea?.width,
                   rightAuxWidth: screen.auxiliaryTopRightArea?.width,
                   safeAreaTop: screen.safeAreaInsets.top,
                   menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY)
    }

    @MainActor
    public static func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    /// The screen the notch UI prefers when it is only shown on one display:
    /// the built-in notched panel if present, else whatever holds the menu bar.
    @MainActor
    public static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: hasNotch) ?? NSScreen.main ?? NSScreen.screens.first
    }
}

public extension NSScreen {
    /// A stable identifier for the display that survives sleep and reconnects,
    /// unlike `NSScreenNumber`.
    var displayUUID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))
        else { return nil }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }

    @MainActor
    static func screen(withUUID uuid: String) -> NSScreen? {
        screens.first { $0.displayUUID == uuid }
    }
}
