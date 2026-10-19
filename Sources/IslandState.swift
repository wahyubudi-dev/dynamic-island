import SwiftUI

enum IslandFeature: Int, CaseIterable, Identifiable, Hashable {
    case music
    case stopwatch
    case prayer
    case files

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .music: return "Now Playing"
        case .stopwatch: return "Stopwatch"
        case .prayer: return "Prayer Times"
        case .files: return "Drop Zone"
        }
    }

    var icon: String {
        switch self {
        case .music: return "music.note"
        case .stopwatch: return "stopwatch"
        case .prayer: return "moon.stars.fill"
        case .files: return "tray.and.arrow.down"
        }
    }
}

final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var page: IslandFeature = .music
    @Published var dropActive = false
    @Published var pinned = false
    @Published var showSettings = false
    @Published var clockMode: ClockMode = .stopwatch
    @Published var notchInset: CGFloat = 0
    @Published var expandedSize = CGSize(width: 600, height: 182)
    @Published var collapsedSize = CGSize(width: 203, height: 34)
    @Published var fileDragActive = false
    @Published var internalDragActive = false
}

struct IslandActions {
    var quit: () -> Void
}
