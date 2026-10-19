import SwiftUI

struct MusicPage: View {
    @ObservedObject var music: MusicPlayer

    var body: some View {
        HStack(spacing: 14) {
            artwork
            details
            Spacer(minLength: 0)
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var artwork: some View {
        Group {
            if let image = music.artwork {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color(white: 0.20), Color(white: 0.09)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .frame(width: 104, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 1)
        )
        .overlay(alignment: .bottomLeading) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.99, green: 0.32, blue: 0.40), Color(red: 0.90, green: 0.16, blue: 0.32)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Image(systemName: "music.note")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 24, height: 24)
            .padding(6)
        }
        .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 6)
    }

    @ViewBuilder
    private var details: some View {
        if music.hasSession {
            VStack(alignment: .leading, spacing: 1) {
                Text(music.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !music.artist.isEmpty {
                    Text(music.artist)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }

                if !music.album.isEmpty {
                    Text(music.album)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.34))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                progress

                HStack(spacing: 2) {
                    GlyphButton(
                        systemName: "backward.fill",
                        size: 13,
                        help: music.canSkipPrevious ? "Previous" : "This player does not expose previous"
                    ) {
                        music.previousTrack()
                    }
                    .disabled(!music.canSkipPrevious)
                    .opacity(music.canSkipPrevious ? 1 : 0.3)
                    GlyphButton(
                        systemName: music.isPlaying ? "pause.fill" : "play.fill",
                        size: 18,
                        frame: 34,
                        help: music.isPlaying ? "Pause" : "Play"
                    ) {
                        music.togglePlayPause()
                    }
                    GlyphButton(
                        systemName: "forward.fill",
                        size: 13,
                        help: music.canSkipNext ? "Next" : "This player does not expose next"
                    ) {
                        music.nextTrack()
                    }
                    .disabled(!music.canSkipNext)
                    .opacity(music.canSkipNext ? 1 : 0.3)
                }
                .padding(.leading, -6)
            }
            .frame(maxWidth: .infinity, maxHeight: 104, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(music.isAvailable ? "Nothing playing" : "MediaRemote unavailable")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)

                Text(
                    music.isAvailable
                        ? "Start playback in Music, Spotify or any media app."
                        : "The private MediaRemote framework could not be loaded."
                )
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300, alignment: .leading)
            }
        }
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            progressBar(at: context.date)
        }
    }

    private func progressBar(at date: Date) -> some View {
        let position = music.position(at: date)
        let fraction: CGFloat = {
            guard music.duration > 0 else { return 0 }
            return CGFloat(min(max(position / music.duration, 0), 1))
        }()

        return HStack(spacing: 8) {
            Text(formatPlaybackTime(position))
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.42))

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.13))
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: max(0, geometry.size.width * fraction))
                }
            }
            .frame(height: 3)

            Text(formatPlaybackTime(music.duration))
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.42))
        }
        .frame(height: 12)
    }
}
