import SwiftUI
import UniformTypeIdentifiers

struct IslandRootView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var music: MusicPlayer
    @ObservedObject var stopwatch: Stopwatch
    @ObservedObject var timer: CountdownTimer
    @ObservedObject var pomodoro: Pomodoro
    @ObservedObject var store: DropStore
    @ObservedObject var prayer: PrayerModel
    let actions: IslandActions

    var body: some View {
        let expanded = state.expandedSize
        let collapsed = state.collapsedSize
        let size = state.expanded ? expanded : collapsed
        let radius: CGFloat = state.expanded ? 40 : min(collapsed.height / 2, 20)
        let shape = IslandShape(topRadius: 0, bottomRadius: radius)

        ZStack(alignment: .top) {
            shape
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.055), Color(white: 0.018)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if let palette = music.palette, state.expanded, state.page == .music {
                shape
                    .fill(
                        LinearGradient(
                            colors: [Color(nsColor: palette.top), Color(nsColor: palette.bottom)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size.width, height: size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .id(palette.id)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            ZStack(alignment: .top) {
                ExpandedIslandView(
                    state: state,
                    music: music,
                    stopwatch: stopwatch,
                    timer: timer,
                    pomodoro: pomodoro,
                    store: store,
                    prayer: prayer
                )
                .frame(width: expanded.width, height: expanded.height)

                if state.showSettings {
                    SettingsOverlay(state: state, actions: actions)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .frame(width: expanded.width, height: expanded.height, alignment: .top)
            .opacity(state.expanded ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: state.expanded)
            .mask(alignment: .top) {
                IslandShape(topRadius: 0, bottomRadius: radius)
                    .frame(width: size.width, height: size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.92), value: state.expanded)
        .animation(.easeInOut(duration: 0.2), value: state.showSettings)
        .animation(.easeInOut(duration: 0.5), value: music.palette?.id)
        .animation(.easeInOut(duration: 0.35), value: state.page)
        .onDrop(of: [UTType.fileURL], isTargeted: dropTarget) { providers in
            state.fileDragActive = false
            store.add(providers: providers)
            return true
        }
    }

    /// Any file dragged over the island opens the drop zone, whichever page is visible.
    private var dropTarget: Binding<Bool> {
        Binding(
            get: { state.dropActive },
            set: { targeted in
                state.dropActive = targeted && !state.internalDragActive
                guard targeted, !state.internalDragActive else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.page = .files
                    state.showSettings = false
                }
            }
        )
    }
}
