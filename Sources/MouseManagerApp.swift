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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(tapManager)
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
    }
}
