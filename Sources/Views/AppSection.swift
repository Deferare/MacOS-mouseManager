import SwiftUI

enum AppSection: String, CaseIterable, Hashable, Identifiable {
    case general
    case buttons
    case scrolling
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .buttons: return "Buttons"
        case .scrolling: return "Scrolling"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .buttons: return "square"
        case .scrolling: return "arrow.up.and.down"
        case .about: return "info.circle"
        }
    }
}

