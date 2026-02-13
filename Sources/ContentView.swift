import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var tapManager: EventTapManager
    @State private var selection: AppSection = .general

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            NavigationStack {
                selectedSectionView
                .navigationTitle(selection.title)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Restore All Defaults") {
                            settings.applyDefaultSettings()
                        }

                        if hasSectionActions {
                            Divider()
                            sectionActions
                        }
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: syncTapManagerIfNeeded)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            syncTapManagerIfNeeded()
        }
        .onChange(of: settings.snapshot) { _ in
            syncTapManagerIfNeeded()
        }
    }

    @ViewBuilder
    private var selectedSectionView: some View {
        switch selection {
        case .general:
            GeneralView()
        case .buttons:
            ButtonsView()
        case .scrolling:
            ScrollingView()
        case .about:
            AboutView()
        }
    }

    private var hasSectionActions: Bool {
        selection != .about
    }

    @ViewBuilder
    private var sectionActions: some View {
        switch selection {
        case .general:
            Button("Request Accessibility") {
                tapManager.requestAccessibilityPermission(forceOpenSettings: true)
            }
        case .buttons:
            Button("Restore Button Defaults") {
                settings.restoreButtonsDefaults()
            }
            Button("Options…") {}
                .disabled(true)
        case .scrolling:
            Button("Restore Scrolling Defaults") {
                settings.restoreScrollingDefaults()
            }
        case .about:
            EmptyView()
        }
    }

    private func syncTapManagerIfNeeded() {
        guard !PreviewEnvironment.isPreview else { return }
        tapManager.apply(settings: settings)
    }
}

#Preview("ContentView") {
    MainActor.assumeIsolated {
        PreviewHost.defaults {
            ContentView()
                .frame(width: 760, height: 520)
        }
    }
}
