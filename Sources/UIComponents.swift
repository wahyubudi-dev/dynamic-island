import SwiftUI

func formatPlaybackTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    let hours = total / 3600
    let minutes = (total / 60) % 60
    let secs = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}

func formatStopwatch(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "00:00.00" }
    let hundredths = Int((seconds * 100).rounded(.down))
    let hours = hundredths / 360_000
    let minutes = (hundredths / 6_000) % 60
    let secs = (hundredths / 100) % 60
    let centis = hundredths % 100
    if hours > 0 {
        return String(format: "%d:%02d:%02d.%02d", hours, minutes, secs, centis)
    }
    return String(format: "%02d:%02d.%02d", minutes, secs, centis)
}

/// Small circular icon button used for chrome actions (gear, reveal, clear…).
struct GlassIconButton: View {
    let systemName: String
    var size: CGFloat = 11
    var help: String = ""
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 0.95 : 0.55))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(hovering ? 0.12 : 0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Plain transport / stopwatch glyph button.
struct GlyphButton: View {
    let systemName: String
    var size: CGFloat = 15
    var frame: CGFloat = 30
    var help: String = ""
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.88))
                .frame(width: frame, height: frame)
                .background(Circle().fill(.white.opacity(hovering ? 0.10 : 0.001)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
