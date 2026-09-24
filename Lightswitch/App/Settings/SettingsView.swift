import SwiftUI
import LightswitchKit

struct SettingsView: View {
    @AppStorage(Preferences.showOnAllDisplaysKey) private var showOnAllDisplays = true
    @AppStorage(Preferences.openOnHoverKey) private var openOnHover = true

    var body: some View {
        Form {
            Section("Notch") {
                Toggle("Show on every display", isOn: $showOnAllDisplays)
                Toggle("Open when the pointer rests on it", isOn: $openOnHover)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}
