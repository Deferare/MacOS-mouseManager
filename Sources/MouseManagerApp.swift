import AppKit
import SwiftUI

@main
struct MouseManagerApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var tapManager: EventTapManager

    init() {
        let settingsStore = SettingsStore()
        let eventTapManager = EventTapManager()
        _settings = StateObject(wrappedValue: settingsStore)
        _tapManager = StateObject(wrappedValue: eventTapManager)

        guard !PreviewEnvironment.isPreview else { return }
        if !settingsStore.didInitializeDefaults {
            settingsStore.applyDefaultSettings()
            settingsStore.didInitializeDefaults = true
        }
        eventTapManager.apply(settings: settingsStore)
    }

    private func applyAppVisibilityPolicy() {
        guard !PreviewEnvironment.isPreview else { return }
        let app = NSApplication.shared
        let policy: NSApplication.ActivationPolicy = settings.showInAppSwitcher ? .regular : .accessory
        guard app.activationPolicy() != policy else { return }
        _ = app.setActivationPolicy(policy)
        if settings.showInAppSwitcher {
            app.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(tapManager)
                .frame(minWidth: 760, minHeight: 520)
                .onAppear {
                    applyAppVisibilityPolicy()
                }
                .onChange(of: settings.showInAppSwitcher) { _ in
                    applyAppVisibilityPolicy()
                }
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
    }
}
