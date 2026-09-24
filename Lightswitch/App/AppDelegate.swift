import AppKit
import SwiftUI
import LightswitchKit

/// Owns one notch window per display and keeps them positioned as screens
/// come and go. Everything else in the app is reached through the
/// coordinator; this class is only windows.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [String: NotchWindow] = [:]
    private let coordinator = NotchCoordinator.shared
    private let store = SessionStore.shared
    private var observers: [NSObjectProtocol] = []
    private var snapshotter: Snapshotter?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.register()
        NSApp.setActivationPolicy(.accessory)
        store.start()

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.layoutWindows() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.layoutWindows() }
        })

        layoutWindows()
        snapshotter = Snapshotter { [weak self] in Array((self?.windows ?? [:]).values) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Creates, removes and repositions windows so there is exactly one per
    /// target screen. Safe to call repeatedly.
    func layoutWindows() {
        let targets: [NSScreen]
        if Preferences.showOnAllDisplays {
            targets = NSScreen.screens
        } else {
            targets = NotchGeometry.preferredScreen().map { [$0] } ?? []
        }
        let wanted = Dictionary(uniqueKeysWithValues: targets.compactMap { screen in
            screen.displayUUID.map { ($0, screen) }
        })

        for (uuid, window) in windows where wanted[uuid] == nil {
            PrivateSpace.shared.remove(window)
            window.close()
            windows[uuid] = nil
            coordinator.unregister(screenUUID: uuid)
        }

        for (uuid, screen) in wanted {
            if windows[uuid] == nil {
                let vm = NotchViewModel(screen: screen)
                let window = NotchWindow(rootView: ContentView()
                    .environmentObject(vm)
                    .environmentObject(coordinator)
                    .environmentObject(store))
                windows[uuid] = window
                coordinator.register(vm, screenUUID: uuid)
                PrivateSpace.shared.add(window)
                window.orderFrontRegardless()
            }
            coordinator.viewModel(for: uuid)?.refreshSize()
            position(windows[uuid]!, on: screen)
        }
    }

    private func position(_ window: NSWindow, on screen: NSScreen) {
        let size = NotchMetrics.windowSize
        let frame = NSRect(x: NotchGeometry.notchCenterX(for: screen) - size.width / 2,
                           y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        window.setFrame(frame, display: true)
    }
}
