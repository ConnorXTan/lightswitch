import SwiftUI
import LightswitchKit

@main
struct LightswitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            StatusMenu()
        } label: {
            Image(nsImage: StatusIcon.image())
        }

        Settings {
            SettingsView()
        }
    }
}
