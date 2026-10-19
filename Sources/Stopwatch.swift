import Foundation

final class Stopwatch: ObservableObject {
    @Published private(set) var isRunning = false

    private var accumulated: TimeInterval = 0
    private var startedAt: Date?

    func elapsed(at date: Date = Date()) -> TimeInterval {
        let running = startedAt.map { date.timeIntervalSince($0) } ?? 0
        return max(accumulated + running, 0)
    }

    var hasElapsed: Bool {
        accumulated > 0 || startedAt != nil
    }

    func toggle() {
        if isRunning {
            accumulated = elapsed()
            startedAt = nil
            isRunning = false
        } else {
            startedAt = Date()
            isRunning = true
        }
    }

    func reset() {
        accumulated = 0
        startedAt = isRunning ? Date() : nil
    }
}
