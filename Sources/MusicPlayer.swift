import AppKit
import Foundation

/// A playhead sample: a known position at a known instant.
/// Players often freeze `ElapsedTime`/`Timestamp` between updates, so the position is
/// extrapolated from the sample instead of reset on every poll.
struct Playhead {
    var elapsed: TimeInterval
    var date: Date
    var isPlaying: Bool

    func position(at now: Date, duration: TimeInterval) -> TimeInterval {
        var value = elapsed
        if isPlaying {
            value += max(0, now.timeIntervalSince(date))
        }
        if duration > 0 {
            value = min(value, duration)
        }
        return max(0, value)
    }
}

/// Reads the system-wide Now Playing session through MediaRemote (private framework)
/// and forwards transport commands. Polls instead of observing notifications so a
/// missing/renamed notification symbol can never break playback state.
final class MusicPlayer: ObservableObject {
    @Published private(set) var isAvailable = true
    @Published private(set) var hasSession = false
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var artwork: NSImage?
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var canSkipNext = true
    @Published private(set) var canSkipPrevious = true

    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias GetPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias GetSupportedFn = @convention(c) (DispatchQueue, @escaping (AnyObject?) -> Void) -> Void
    private typealias SendCommandFn = @convention(c) (Int32, CFDictionary?) -> Bool

    private enum Command {
        static let togglePlayPause: Int32 = 2
        static let nextTrack: Int32 = 4
        static let previousTrack: Int32 = 5
    }

    private enum Key {
        static let title = "kMRMediaRemoteNowPlayingInfoTitle"
        static let artist = "kMRMediaRemoteNowPlayingInfoArtist"
        static let album = "kMRMediaRemoteNowPlayingInfoAlbum"
        static let duration = "kMRMediaRemoteNowPlayingInfoDuration"
        static let elapsed = "kMRMediaRemoteNowPlayingInfoElapsedTime"
        static let artworkData = "kMRMediaRemoteNowPlayingInfoArtworkData"
        static let assetURL = "kMRMediaRemoteNowPlayingInfoAssetURL"
        static let playbackRate = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
        static let timestamp = "kMRMediaRemoteNowPlayingInfoTimestamp"
    }

    private let handle: UnsafeMutableRawPointer?
    private let getNowPlayingInfo: GetInfoFn?
    private let getIsPlaying: GetPlayingFn?
    private let getSupportedCommands: GetSupportedFn?
    private let sendCommand: SendCommandFn?

    private var pollTimer: Timer?
    private var fetching = false
    private var lastArtworkData: Data?
    private var isStarted = false

    private var anchor = Playhead(elapsed: 0, date: Date(), isPlaying: false)
    private var lastReportedElapsed: TimeInterval = -1
    private var lastReportedTimestamp: Date?
    private var lastInfoDate = Date()
    private var optimisticPlaying: Bool?
    private var optimisticUntil: Date?

    init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        let opened = dlopen(path, RTLD_LAZY)
        handle = opened

        if let opened,
           let infoSymbol = dlsym(opened, "MRMediaRemoteGetNowPlayingInfo"),
           let playingSymbol = dlsym(opened, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            getNowPlayingInfo = unsafeBitCast(infoSymbol, to: GetInfoFn.self)
            getIsPlaying = unsafeBitCast(playingSymbol, to: GetPlayingFn.self)
            if let supportedSymbol = dlsym(opened, "MRMediaRemoteGetSupportedCommands") {
                getSupportedCommands = unsafeBitCast(supportedSymbol, to: GetSupportedFn.self)
            } else {
                getSupportedCommands = nil
            }
            if let commandSymbol = dlsym(opened, "MRMediaRemoteSendCommand") {
                sendCommand = unsafeBitCast(commandSymbol, to: SendCommandFn.self)
            } else {
                sendCommand = nil
            }
        } else {
            getNowPlayingInfo = nil
            getIsPlaying = nil
            getSupportedCommands = nil
            sendCommand = nil
            isAvailable = false
        }
    }

    deinit {
        pollTimer?.invalidate()
        if let handle { dlclose(handle) }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        poll()
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        isStarted = false
    }

    // MARK: - Transport

    func togglePlayPause() {
        // Flip the button immediately; polls can lag behind for a moment.
        let next = !isPlaying
        let current = position()
        isPlaying = next
        optimisticPlaying = next
        optimisticUntil = Date().addingTimeInterval(1.0)
        anchor = Playhead(elapsed: current, date: Date(), isPlaying: next)
        send(Command.togglePlayPause)
    }
    func nextTrack() { send(Command.nextTrack) }
    func previousTrack() { send(Command.previousTrack) }

    private func send(_ command: Int32) {
        guard let sendCommand else { return }
        _ = sendCommand(command, nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.poll()
        }
    }

    // MARK: - Read

    /// Current playhead, extrapolated from the last MediaRemote sample.
    func position(at date: Date = Date()) -> TimeInterval {
        anchor.position(at: date, duration: duration)
    }

    private func poll() {
        guard !fetching, let getNowPlayingInfo, let getIsPlaying else { return }
        fetching = true

        let group = DispatchGroup()
        var info: [String: Any] = [:]
        var playing = false
        var supported: AnyObject?

        group.enter()
        getNowPlayingInfo(.main) { dictionary in
            info = dictionary
            group.leave()
        }

        group.enter()
        getIsPlaying(.main) { value in
            playing = value
            group.leave()
        }

        if let getSupportedCommands {
            group.enter()
            getSupportedCommands(.main) { value in
                supported = value
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.apply(info: info, playing: playing)
            self.applySupported(supported)
            self.fetching = false
        }
    }

    private func applySupported(_ value: AnyObject?) {
        guard let array = value as? [Any], !array.isEmpty else { return }
        var codes = Set<Int>()
        for item in array {
            let object = item as AnyObject
            guard object.responds(to: NSSelectorFromString("command")),
                  let number = object.value(forKey: "command") as? NSNumber else { continue }
            codes.insert(number.intValue)
        }
        guard !codes.isEmpty else { return }
        canSkipNext = codes.contains(4)
        canSkipPrevious = codes.contains(5)
    }

    private func apply(info: [String: Any], playing: Bool) {
        let newArtist = info[Key.artist] as? String ?? ""
        let newAlbum = info[Key.album] as? String ?? ""
        let newDuration = (info[Key.duration] as? NSNumber)?.doubleValue ?? 0
        let newElapsed = (info[Key.elapsed] as? NSNumber)?.doubleValue ?? 0
        let rate = (info[Key.playbackRate] as? NSNumber)?.doubleValue ?? 0

        var newTitle = info[Key.title] as? String ?? ""
        if newTitle.isEmpty {
            let asset: URL?
            if let value = info[Key.assetURL] as? URL {
                asset = value
            } else if let value = info[Key.assetURL] as? String {
                asset = URL(string: value)
            } else {
                asset = nil
            }
            if let asset {
                newTitle = asset.deletingPathExtension().lastPathComponent
            }
        }

        let now = Date()
        let resolved = resolvedPlaybackState(
            reported: playing || rate > 0,
            optimistic: optimisticPlaying,
            optimisticUntil: optimisticUntil,
            now: now
        )
        optimisticPlaying = resolved.pendingOptimistic
        let effectivePlaying = resolved.playing

        let isEmptyInfo = newTitle.isEmpty && newDuration == 0
        if isEmptyInfo {
            // Players briefly drop the info dict while pause/play is settling.
            if hasSession && now.timeIntervalSince(lastInfoDate) < 1.5 {
                isPlaying = effectivePlaying
                anchor.isPlaying = effectivePlaying
                return
            }
            title = ""
            artist = ""
            album = ""
            duration = 0
            artwork = nil
            lastArtworkData = nil
            hasSession = false
            isPlaying = false
            optimisticPlaying = nil
            anchor = Playhead(elapsed: 0, date: now, isPlaying: false)
            return
        }

        lastInfoDate = now

        let trackChanged = newTitle != title || abs(newDuration - duration) > 0.5
        let reportedTimestamp = info[Key.timestamp] as? Date

        if newTitle != title { title = newTitle }
        if newArtist != artist { artist = newArtist }
        if newAlbum != album { album = newAlbum }
        if newDuration != duration { duration = newDuration }

        isPlaying = effectivePlaying
        hasSession = true
        updateAnchor(
            elapsed: newElapsed,
            timestamp: reportedTimestamp,
            playing: effectivePlaying,
            trackChanged: trackChanged
        )

        switch artworkDecision(
            current: lastArtworkData,
            incoming: info[Key.artworkData] as? Data,
            trackChanged: trackChanged
        ) {
        case .keep:
            break
        case .clear:
            // A new track without artwork: drop the previous cover.
            lastArtworkData = nil
            artwork = nil
        case .update(let data):
            lastArtworkData = data
            artwork = NSImage(data: data)
        }
    }

    /// Re-bases the playhead only when MediaRemote produces a new sample. A frozen
    /// sample keeps its original timestamp, so the position keeps advancing instead
    /// of snapping back on every poll (Spotify does this).
    private func updateAnchor(elapsed: TimeInterval, timestamp: Date?, playing: Bool, trackChanged: Bool) {
        let now = Date()
        let elapsedChanged = abs(elapsed - lastReportedElapsed) > 0.05
        let timestampChanged = timestamp != lastReportedTimestamp
        let stateChanged = playing != anchor.isPlaying
        let firstSample = lastReportedElapsed < 0

        if firstSample || elapsedChanged || timestampChanged || stateChanged || trackChanged {
            anchor = Playhead(elapsed: elapsed, date: min(timestamp ?? now, now), isPlaying: playing)
            lastReportedElapsed = elapsed
            lastReportedTimestamp = timestamp
        } else {
            anchor.isPlaying = playing
        }
    }
}

/// Reconciles the optimistic button state with MediaRemote's reported state.
func resolvedPlaybackState(
    reported: Bool,
    optimistic: Bool?,
    optimisticUntil: Date?,
    now: Date
) -> (playing: Bool, pendingOptimistic: Bool?) {
    guard let optimistic, let until = optimisticUntil, now < until else {
        return (reported, nil)
    }
    if reported == optimistic {
        return (reported, nil)
    }
    return (optimistic, optimistic)
}

enum ArtworkDecision: Equatable {
    case keep
    case clear
    case update(Data)
}

/// Keeps the current cover when the artwork key briefly disappears during a
/// pause/play transition; only a track change may drop it.
func artworkDecision(current: Data?, incoming: Data?, trackChanged: Bool) -> ArtworkDecision {
    if let incoming {
        return incoming == current ? .keep : .update(incoming)
    }
    return trackChanged ? .clear : .keep
}
