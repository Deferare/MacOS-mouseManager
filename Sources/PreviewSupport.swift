import SwiftUI

enum PreviewEnvironment {
    static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

struct PreviewHost<Content: View>: View {
    @StateObject private var settings: SettingsStore
    @StateObject private var tapManager: EventTapManager
    private let content: Content

    init(
        settings: SettingsStore,
        tapManager: EventTapManager,
        @ViewBuilder content: () -> Content
    ) {
        _settings = StateObject(wrappedValue: settings)
        _tapManager = StateObject(wrappedValue: tapManager)
        self.content = content()
    }

    var body: some View {
        content
            .environmentObject(settings)
            .environmentObject(tapManager)
    }

    @MainActor
    static func makeSettings() -> SettingsStore {
        let store = SettingsStore()
        store.enabled = true
        store.smoothScrollingEnabled = true
        store.smoothnessLevel = 0.68
        store.middleDragScrollingEnabled = true
        store.middleDragInertiaStrength = 0.62
        store.reverseDirection = false
        store.speedMultiplier = 3.0
        store.middleClickButtonAction = .lookUpQuickLook
        store.button4ButtonAction = .back
        store.button5ButtonAction = .forward
        return store
    }

    @MainActor
    static func defaults(@ViewBuilder content: () -> Content) -> PreviewHost {
        PreviewHost(
            settings: makeSettings(),
            tapManager: EventTapManager(),
            content: content
        )
    }
}
