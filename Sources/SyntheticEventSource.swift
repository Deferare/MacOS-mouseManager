import Cocoa

enum SyntheticEventSource {
    static let hidSystemState: CGEventSource? = CGEventSource(stateID: .hidSystemState)
}
