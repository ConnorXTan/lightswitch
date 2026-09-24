import SwiftUI
import LightswitchKit

extension SessionState {
    /// The dot colour on black. System colours so they match every other
    /// status light on the Mac; idle is a dim white rather than grey so it
    /// still reads on the black notch.
    var color: Color {
        switch self {
        case .idle: return Color.white.opacity(0.32)
        case .working: return Color(nsColor: .systemYellow)
        case .needsYou: return Color(nsColor: .systemRed)
        case .done: return Color(nsColor: .systemGreen)
        }
    }
}
