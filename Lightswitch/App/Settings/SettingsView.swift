import AppKit
import SwiftUI
import LightswitchKit

struct SettingsView: View {
    @AppStorage(Preferences.showOnAllDisplaysKey) private var showOnAllDisplays = true
    @AppStorage(Preferences.openOnHoverKey) private var openOnHover = true
    @AppStorage(Preferences.alertSoundKey) private var alertSound = true
    @AppStorage(Preferences.sensorEnabledKey) private var sensorEnabled = true
    @AppStorage(Preferences.gestureActionKey) private var gestureAction = GestureAction.smart.rawValue
    @ObservedObject private var hooks = HooksModel.shared
    @ObservedObject private var sensorController = SensorController.shared
    @ObservedObject private var sensor = SensorController.shared.sensor

    var body: some View {
        Form {
            Section("Notch") {
                Toggle("Show on every display", isOn: $showOnAllDisplays)
                Toggle("Open when the pointer rests on it", isOn: $openOnHover)
                Toggle("Play a sound when a session needs you", isOn: $alertSound)
            }

            Section {
                Toggle("Use the light sensor as a button", isOn: $sensorEnabled)
                Picker("Covering the notch", selection: $gestureAction) {
                    ForEach(GestureAction.allCases) { action in
                        Text(action.label).tag(action.rawValue)
                    }
                }
                LabeledContent("Sensor") {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(sensorReadout)
                            .monospacedDigit()
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                        if sensorEnabled, sensor.baseline > 0 {
                            RatioBar(ratio: sensor.ratio,
                                     cover: sensor.config.coverRatio,
                                     uncover: sensor.config.uncoverRatio)
                                .frame(width: 180, height: 6)
                        }
                    }
                }
                if let error = sensorController.lastActionError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(Color(nsColor: .systemRed))
                }
                HStack {
                    Button("Recalibrate") { sensorController.recalibrate() }
                        .disabled(!sensorEnabled)
                    Spacer()
                    if GestureAction(rawValue: gestureAction)?.needsAccessibility == true {
                        Text("Needs Accessibility permission")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Light sensor")
            } footer: {
                Text("Cup your hand over the top of the screen; the gesture fires about 300 ms after the sensor is covered. Turn off System Settings → Displays → Automatically adjust brightness, or macOS dims the screen as you shade the sensor and fights the detection. Needs a lit room: below 25 lux the shadow can't be told from the room.")
                    .foregroundStyle(.secondary)
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

    private var sensorReadout: String {
        guard sensorEnabled else { return "Off" }
        let lux = sensor.lux.formatted(.number.precision(.fractionLength(0)))
        switch sensor.status {
        case .off: return "Starting…"
        case .calibrating: return "Calibrating, keep the screen unshaded"
        case .armed: return "\(lux) lux · armed"
        case .covered: return "\(lux) lux · covered"
        case .fault(let message): return message
        case .unavailable(let message): return "Unavailable: \(message)"
        }
    }
}

/// The live signal against its two thresholds: the fill is the current
/// reading as a fraction of the baseline, the two ticks are where a cover is
/// detected and where it releases.
struct RatioBar: View {
    let ratio: Double
    let cover: Double
    let uncover: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(ratio < cover ? Color(nsColor: .systemOrange) : Color.accentColor)
                    .frame(width: max(0, min(1, ratio)) * w)
                    .animation(.linear(duration: 0.1), value: ratio)
                ForEach([cover, uncover], id: \.self) { tick in
                    Rectangle()
                        .fill(.secondary)
                        .frame(width: 1, height: geo.size.height + 4)
                        .offset(x: tick * w)
                }
            }
        }
        .accessibilityLabel("Light level \(Int(ratio * 100)) percent of baseline")
    }
}
