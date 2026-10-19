import SwiftUI

struct ExpandedIslandView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var music: MusicPlayer
    @ObservedObject var stopwatch: Stopwatch
    @ObservedObject var timer: CountdownTimer
    @ObservedObject var pomodoro: Pomodoro
    @ObservedObject var store: DropStore
    @ObservedObject var prayer: PrayerModel

    var body: some View {
        FeaturePager(
            state: state,
            music: music,
            stopwatch: stopwatch,
            timer: timer,
            pomodoro: pomodoro,
            store: store,
            prayer: prayer,
            intendedInitialPage: state.page
        )
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .padding(.top, 12 + state.notchInset)
        .padding(.bottom, 12)
        .overlay(alignment: .topTrailing) {
            GlassIconButton(
                systemName: "gearshape.fill",
                size: 11,
                help: "Settings"
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    state.showSettings.toggle()
                }
            }
            .padding(.top, 6)
            .padding(.trailing, 8)
        }
    }
}

/// Horizontally paged feature area. Trackpad swipes drive it.
private struct FeaturePager: View {
    @ObservedObject var state: IslandState
    @ObservedObject var music: MusicPlayer
    @ObservedObject var stopwatch: Stopwatch
    @ObservedObject var timer: CountdownTimer
    @ObservedObject var pomodoro: Pomodoro
    @ObservedObject var store: DropStore
    @ObservedObject var prayer: PrayerModel
    let intendedInitialPage: IslandFeature

    @State private var didRestoreInitialPage = false

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(IslandFeature.allCases) { feature in
                        page(for: feature)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .id(feature)
                    }
                }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .scrollPosition(id: pageBinding)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .onAppear {
                    guard !didRestoreInitialPage else { return }
                    didRestoreInitialPage = true
                    // `scrollPosition` reports the first page on its initial layout and does
                    // not always scroll when the binding is restored, so nudge the proxy too.
                    let target = intendedInitialPage
                    DispatchQueue.main.async {
                        proxy.scrollTo(target, anchor: .center)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        proxy.scrollTo(target, anchor: .center)
                        if state.page != target {
                            state.page = target
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func page(for feature: IslandFeature) -> some View {
        switch feature {
        case .music:
            MusicPage(music: music)
        case .monitor:
            MonitorPage()
        case .stopwatch:
            ClockPage(state: state, stopwatch: stopwatch, timer: timer, pomodoro: pomodoro)
        case .files:
            DropPage(store: store, state: state)
        case .prayer:
            PrayerPage(model: prayer)
        }
    }

    private var pageBinding: Binding<IslandFeature?> {
        Binding(
            get: { state.page },
            set: { newValue in
                if let feature = newValue, feature != state.page {
                    state.page = feature
                }
            }
        )
    }
}
