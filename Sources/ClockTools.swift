import AppKit
import Foundation

enum ClockMode: Int, CaseIterable, Identifiable {
    case stopwatch
    case timer
    case pomodoro

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .stopwatch: return "Stopwatch"
        case .timer: return "Timer"
        case .pomodoro: return "Pomodoro"
        }
    }
}

/// Countdown timer with presets. Runs off an end date so it survives polls,
/// window collapse and short sleeps.
final class CountdownTimer: ObservableObject {
    static let presets: [TimeInterval] = [60, 300, 600, 900, 1500, 1800]

    @Published private(set) var duration: TimeInterval = 300
    @Published private(set) var remaining: TimeInterval = 300
    @Published private(set) var isRunning = false
    @Published private(set) var isFinished = false

    private var endDate: Date?
    private var ticker: Timer?

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max((duration - remaining) / duration, 0), 1)
    }

    func select(_ seconds: TimeInterval) {
        guard !isRunning else { return }
        duration = seconds
        remaining = seconds
        isFinished = false
        endDate = nil
    }

    func startPause() {
        if isRunning { pause() } else { start() }
    }

    func reset() {
        stopTicker()
        endDate = nil
        isRunning = false
        isFinished = false
        remaining = duration
    }

    private func start() {
        if remaining <= 0.05 {
            remaining = duration
        }
        isFinished = false
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        startTicker()
    }

    private func pause() {
        if let endDate {
            remaining = max(0, endDate.timeIntervalSinceNow)
        }
        endDate = nil
        isRunning = false
        stopTicker()
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let endDate else { return }
        let left = endDate.timeIntervalSinceNow
        if left <= 0 {
            remaining = 0
            isRunning = false
            isFinished = true
            self.endDate = nil
            stopTicker()
            NSSound(named: "Glass")?.play()
        } else {
            remaining = left
        }
    }

    deinit {
        ticker?.invalidate()
    }
}

/// Classic 25/5 pomodoro. Finishing a phase advances and auto-starts the next one.
final class Pomodoro: ObservableObject {
    enum Phase {
        case focus
        case breakTime
    }

    static let focusDuration: TimeInterval = 25 * 60
    static let breakDuration: TimeInterval = 5 * 60

    @Published private(set) var phase: Phase = .focus
    @Published private(set) var completedFocus = 0
    @Published private(set) var remaining: TimeInterval = Pomodoro.focusDuration
    @Published private(set) var isRunning = false

    private var endDate: Date?
    private var ticker: Timer?

    var phaseDuration: TimeInterval {
        phase == .focus ? Self.focusDuration : Self.breakDuration
    }

    var phaseTitle: String {
        phase == .focus ? "Focus" : "Break"
    }

    var progress: Double {
        guard phaseDuration > 0 else { return 0 }
        return min(max((phaseDuration - remaining) / phaseDuration, 0), 1)
    }

    func startPause() {
        if isRunning { pause() } else { start() }
    }

    func reset() {
        stopTicker()
        endDate = nil
        isRunning = false
        remaining = phaseDuration
    }

    func skip() {
        advance(counting: false, autoStart: isRunning)
    }

    private func start() {
        if remaining <= 0.05 {
            remaining = phaseDuration
        }
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        startTicker()
    }

    private func pause() {
        if let endDate {
            remaining = max(0, endDate.timeIntervalSinceNow)
        }
        endDate = nil
        isRunning = false
        stopTicker()
    }

    private func advance(counting: Bool, autoStart: Bool) {
        if phase == .focus && counting {
            completedFocus += 1
        }
        phase = phase == .focus ? .breakTime : .focus
        stopTicker()
        endDate = nil
        isRunning = false
        remaining = phaseDuration
        if autoStart { start() }
    }

    private func tick() {
        guard let endDate else { return }
        let left = endDate.timeIntervalSinceNow
        if left <= 0 {
            NSSound(named: "Glass")?.play()
            advance(counting: true, autoStart: true)
        } else {
            remaining = left
        }
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    deinit {
        ticker?.invalidate()
    }
}

func formatCountdown(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded(.up)))
    let hours = total / 3600
    let minutes = (total / 60) % 60
    let secs = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%02d:%02d", minutes, secs)
}
