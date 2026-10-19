import SwiftUI

struct ClockPage: View {
    @ObservedObject var state: IslandState
    @ObservedObject var stopwatch: Stopwatch
    @ObservedObject var timer: CountdownTimer
    @ObservedObject var pomodoro: Pomodoro

    var body: some View {
        TimelineView(.periodic(from: .now, by: refreshInterval)) { context in
            content(at: context.date)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var refreshInterval: TimeInterval {
        if state.clockMode == .stopwatch && stopwatch.isRunning { return 0.03 }
        return 0.25
    }

    private func content(at date: Date) -> some View {
        HStack(spacing: 14) {
            dial(at: date)
            VStack(alignment: .leading, spacing: 2) {
                modeTabs
                timeText(at: date)
                accessory
                Spacer(minLength: 2)
                controls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 2)
    }

    // MARK: - Tabs

    private var modeTabs: some View {
        HStack(spacing: 2) {
            ForEach(ClockMode.allCases) { mode in
                Button {
                    state.clockMode = mode
                } label: {
                    Text(mode.title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(state.clockMode == mode ? .white : .white.opacity(0.42))
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        .background(
                            Capsule().fill(state.clockMode == mode ? Color.white.opacity(0.13) : Color.clear)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.05)))
    }

    private func timeText(at date: Date) -> some View {
        Text(timeString(at: date))
            .font(.system(size: 36, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .fixedSize()
            .frame(height: 40, alignment: .leading)
    }

    private func timeString(at date: Date) -> String {
        switch state.clockMode {
        case .stopwatch:
            return formatStopwatch(stopwatch.elapsed(at: date))
        case .timer:
            return formatCountdown(timer.remaining)
        case .pomodoro:
            return formatCountdown(pomodoro.remaining)
        }
    }

    // MARK: - Accessory row

    @ViewBuilder
    private var accessory: some View {
        switch state.clockMode {
        case .stopwatch:
            Text(stopwatch.isRunning ? "Running" : stopwatch.hasElapsed ? "Paused" : "Ready")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .frame(height: 20, alignment: .leading)

        case .timer:
            timerPresets

        case .pomodoro:
            pomodoroInfo
        }
    }

    private var timerPresets: some View {
        HStack(spacing: 4) {
            ForEach(CountdownTimer.presets, id: \.self) { preset in
                let selected = abs(timer.duration - preset) < 1
                Button {
                    timer.select(preset)
                } label: {
                    Text("\(Int(preset / 60))m")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(selected ? .white : .white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        .background(
                            Capsule().fill(selected ? Color.white.opacity(0.14) : Color.white.opacity(0.05))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(timer.isRunning)
                .opacity(timer.isRunning ? 0.5 : 1)
            }
        }
        .frame(height: 20)
    }

    private var pomodoroInfo: some View {
        let tint: Color = pomodoro.phase == .focus ? .orange : .green
        return HStack(spacing: 8) {
            Text(pomodoro.phaseTitle)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(tint)
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background(Capsule().fill(tint.opacity(0.15)))

            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(index < pomodoro.completedFocus % 4 ? Color.white.opacity(0.8) : Color.white.opacity(0.15))
                        .frame(width: 4, height: 4)
                }
            }

            Text("\(pomodoro.completedFocus) done")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.32))
        }
        .frame(height: 20)
    }

    // MARK: - Dial

    private struct DialSpec {
        var fraction: CGFloat
        var icon: String
        var caption: String
        var colors: [Color]
    }

    private func dial(at date: Date) -> some View {
        let spec = dialSpec(at: date)
        return ZStack {
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 5)

            Circle()
                .trim(from: 0, to: spec.fraction)
                .stroke(
                    AngularGradient(colors: spec.colors, center: .center),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 3) {
                Image(systemName: spec.icon)
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(.white.opacity(0.8))
                Text(spec.caption)
                    .font(.system(size: 7.5, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .frame(width: 104, height: 104)
    }

    private func dialSpec(at date: Date) -> DialSpec {
        switch state.clockMode {
        case .stopwatch:
            let elapsed = stopwatch.elapsed(at: date)
            return DialSpec(
                fraction: (elapsed.truncatingRemainder(dividingBy: 60)) / 60,
                icon: "stopwatch",
                caption: stopwatch.isRunning ? "RUNNING" : stopwatch.hasElapsed ? "PAUSED" : "READY",
                colors: [Color(red: 1.0, green: 0.58, blue: 0.28), Color(red: 0.98, green: 0.32, blue: 0.42)]
            )

        case .timer:
            return DialSpec(
                fraction: timer.progress,
                icon: "timer",
                caption: timer.isFinished ? "DONE" : "TIMER",
                colors: [Color(red: 0.35, green: 0.68, blue: 1.0), Color(red: 0.25, green: 0.90, blue: 0.86)]
            )

        case .pomodoro:
            let isFocus = pomodoro.phase == .focus
            return DialSpec(
                fraction: pomodoro.progress,
                icon: isFocus ? "brain.head.profile" : "cup.and.saucer.fill",
                caption: isFocus ? "FOCUS" : "BREAK",
                colors: isFocus
                    ? [Color(red: 1.0, green: 0.58, blue: 0.28), Color(red: 0.98, green: 0.32, blue: 0.42)]
                    : [Color(red: 0.30, green: 0.85, blue: 0.55), Color(red: 0.20, green: 0.70, blue: 0.70)]
            )
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 8) {
            Button(action: primaryAction) {
                HStack(spacing: 6) {
                    Image(systemName: primaryIcon)
                        .font(.system(size: 10, weight: .bold))
                    Text(primaryTitle)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.black)
                .frame(width: 92, height: 26)
                .background(Capsule().fill(.white))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Button(action: resetAction) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(canReset ? 0.9 : 0.25))
                    .frame(width: 28, height: 26)
                    .background(Capsule().fill(.white.opacity(canReset ? 0.09 : 0.03)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canReset)
            .help("Reset")

            if state.clockMode == .pomodoro {
                Button {
                    pomodoro.skip()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 28, height: 26)
                        .background(Capsule().fill(.white.opacity(0.07)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Skip to next phase")
            }

            Spacer(minLength: 0)
        }
        .frame(height: 26)
    }

    private var primaryTitle: String {
        switch state.clockMode {
        case .stopwatch:
            return stopwatch.isRunning ? "Pause" : stopwatch.hasElapsed ? "Resume" : "Start"
        case .timer:
            if timer.isFinished { return "Restart" }
            return timer.isRunning ? "Pause" : timer.remaining < timer.duration - 0.01 ? "Resume" : "Start"
        case .pomodoro:
            return pomodoro.isRunning ? "Pause" : pomodoro.remaining < pomodoro.phaseDuration - 0.01 ? "Resume" : "Start"
        }
    }

    private var primaryIcon: String {
        switch state.clockMode {
        case .stopwatch:
            return stopwatch.isRunning ? "pause.fill" : "play.fill"
        case .timer:
            if timer.isFinished { return "arrow.clockwise" }
            return timer.isRunning ? "pause.fill" : "play.fill"
        case .pomodoro:
            return pomodoro.isRunning ? "pause.fill" : "play.fill"
        }
    }

    private var primaryAction: () -> Void {
        switch state.clockMode {
        case .stopwatch: return { stopwatch.toggle() }
        case .timer: return { timer.startPause() }
        case .pomodoro: return { pomodoro.startPause() }
        }
    }

    private var canReset: Bool {
        switch state.clockMode {
        case .stopwatch:
            return stopwatch.hasElapsed
        case .timer:
            return timer.isRunning || timer.isFinished || timer.remaining < timer.duration - 0.01
        case .pomodoro:
            return pomodoro.isRunning || pomodoro.remaining < pomodoro.phaseDuration - 0.01
        }
    }

    private func resetAction() {
        switch state.clockMode {
        case .stopwatch: stopwatch.reset()
        case .timer: timer.reset()
        case .pomodoro: pomodoro.reset()
        }
    }
}
