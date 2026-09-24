import AppKit
import SwiftUI
import LightswitchKit

struct SettingsView: View {
    @AppStorage(Preferences.showOnAllDisplaysKey) private var showOnAllDisplays = true
    @AppStorage(Preferences.openOnHoverKey) private var openOnHover = true
    @AppStorage(Preferences.alertSoundKey) private var alertSound = true
    @ObservedObject private var hooks = HooksModel.shared

    var body: some View {
        Form {
            Section("Notch") {
                Toggle("Show on every display", isOn: $showOnAllDisplays)
                Toggle("Open when the pointer rests on it", isOn: $openOnHover)
                Toggle("Play a sound when a session needs you", isOn: $alertSound)
            }

            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(hooks.isInstalled ? Color(nsColor: .systemGreen) : Color.secondary.opacity(0.5))
                            .frame(width: 8, height: 8)
                        Text(hooks.summary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if let error = hooks.lastError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(Color(nsColor: .systemRed))
                }
                HStack {
                    Button("Install hooks") { hooks.install() }
                        .disabled(!hooks.canInstall)
                    Button("Remove hooks") { hooks.uninstall() }
                        .disabled(hooks.status == .notInstalled)
                    Spacer()
                    Button("Show script in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([hooks.installer.scriptURL])
                    }
                    .disabled(!FileManager.default.fileExists(atPath: hooks.installer.scriptURL.path))
                }
            } header: {
                Text("Claude Code hooks")
            } footer: {
                Text("Installing adds seven entries to ~/.claude/settings.json, each running ~/.claude/hooks/notch.sh, and backs the file up to settings.json.bak first. Nothing else in the file is touched. Sessions already running pick the hooks up on their next start.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear {
            hooks.refresh()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
