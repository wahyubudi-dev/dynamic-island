import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let state = IslandState()
    private let music = MusicPlayer()
    private let stopwatch = Stopwatch()
    private let timer = CountdownTimer()
    private let pomodoro = Pomodoro()
    private let dropStore = DropStore()
    private let prayer = PrayerModel()

    private var panel: IslandPanel?
    private var geometry = IslandGeometry(screen: IslandGeometry.preferredScreen())
    private var hoverTimer: Timer?
    private var collapseDeadline: Date?
    private var statusItem: NSStatusItem?
    private var dragMonitor: Any?
    private var dragPasteboardBaseline = -1
    private var trackingFileDrag = false

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildPanel()
        buildStatusItem()
        music.start()
        startHoverTracking()
        startDragTracking()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NSLog("[island] ready screen=%@ notch=%@", NSStringFromRect(geometry.screen.frame),
              geometry.notchWidth.map { String(format: "%.0f", $0) } ?? "none")
    }

    func applicationWillTerminate(_ notification: Notification) {
        music.stop()
        hoverTimer?.invalidate()
        if let dragMonitor {
            NSEvent.removeMonitor(dragMonitor)
        }
    }

    // MARK: - Panel

    private func buildPanel() {
        geometry = IslandGeometry(screen: IslandGeometry.preferredScreen())
        state.notchInset = geometry.notchHeight
        state.expandedSize = geometry.frame(expanded: true).size
        state.collapsedSize = geometry.collapsedSize
        let frame = geometry.frame(expanded: true)

        let panel = IslandPanel(frame: frame)
        let root = IslandRootView(
            state: state,
            music: music,
            stopwatch: stopwatch,
            timer: timer,
            pomodoro: pomodoro,
            store: dropStore,
            prayer: prayer,
            actions: IslandActions(quit: { NSApp.terminate(nil) })
        )
        let host = ClickHostingView(rootView: root)
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        // Do not let Core Animation interpolate the hosting layer from its center
        // while the window frame animates; that made the island appear to grow
        // from the middle and exposed the menu bar above it.
        host.layer?.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "contents": NSNull(),
            "sublayers": NSNull(),
        ]
        panel.contentView = host
        panel.setFrame(frame, display: true)
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func expand() {
        guard let panel, !state.expanded else { return }
        state.expanded = true
        collapseDeadline = nil
        panel.ignoresMouseEvents = false
    }

    private func collapse() {
        guard let panel, state.expanded else { return }
        guard !state.pinned, !state.showSettings, !state.dropActive,
              !state.fileDragActive, !state.internalDragActive else { return }
        state.expanded = false
        state.showSettings = false
        panel.ignoresMouseEvents = true
        // The shelf is a transient tool: reopen on the music page after closing.
        if state.page == .files {
            state.page = .music
        }
    }

    @objc private func screenParametersChanged() {
        geometry = IslandGeometry(screen: IslandGeometry.preferredScreen())
        state.notchInset = geometry.notchHeight
        state.expandedSize = geometry.frame(expanded: true).size
        state.collapsedSize = geometry.collapsedSize
        panel?.setFrame(geometry.frame(expanded: true), display: true)
    }

    // MARK: - Hover

    private func startHoverTracking() {
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.hoverTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func hoverTick() {
        guard panel != nil else { return }

        if state.fileDragActive, NSEvent.pressedMouseButtons & 0x1 == 0 {
            state.fileDragActive = false
        }

        let mouse = NSEvent.mouseLocation

        var zone = geometry.frame(expanded: state.expanded).insetBy(dx: -8, dy: -8)
        if !state.expanded {
            // Make the thin tongue under the notch easier to hit.
            zone.size.height += 6
        }

        if zone.contains(mouse) {
            collapseDeadline = nil
            if !state.expanded { expand() }
            return
        }

        guard state.expanded, !state.pinned, !state.showSettings, !state.dropActive,
              !state.fileDragActive, !state.internalDragActive else {
            collapseDeadline = nil
            return
        }

        if let deadline = collapseDeadline {
            if Date() >= deadline { collapse() }
        } else {
            collapseDeadline = Date().addingTimeInterval(0.45)
        }
    }

    // MARK: - File drags

    /// Opens the shelf as soon as a file drag comes near the island, before the pointer
    /// enters the panel. The SwiftUI drop target alone only reacts once the drag is
    /// already inside the window.
    private func startDragTracking() {
        dragMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            DispatchQueue.main.async { self?.handleDragEvent(event) }
        }
    }

    private func handleDragEvent(_ event: NSEvent) {
        let pasteboard = NSPasteboard(name: .drag)

        switch event.type {
        case .leftMouseDown:
            // The drag pasteboard keeps stale contents after a drag, so only trust it
            // when it was rewritten by the drag that is starting now.
            dragPasteboardBaseline = pasteboard.changeCount
            trackingFileDrag = false
            state.fileDragActive = false

        case .leftMouseUp:
            trackingFileDrag = false
            state.fileDragActive = false

        case .leftMouseDragged:
            if !trackingFileDrag {
                guard pasteboard.changeCount != dragPasteboardBaseline,
                      pasteboard.types?.contains(.fileURL) == true else {
                    state.fileDragActive = false
                    return
                }
                trackingFileDrag = true
            }

            guard let panel, pasteboard.types?.contains(.fileURL) == true else {
                state.fileDragActive = false
                return
            }

            let mouse = NSEvent.mouseLocation
            let near = panel.frame.insetBy(dx: -90, dy: -90).contains(mouse)
            state.fileDragActive = near
            guard near else { return }

            if !state.expanded { expand() }
            if state.page != .files {
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.page = .files
                }
            }

        default:
            break
        }
    }

    // MARK: - Status item

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "capsule.portrait", accessibilityDescription: "Dynamic Island")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.delegate = self

        let show = NSMenuItem(title: "Expand Island", action: #selector(expandFromMenu), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        let pin = NSMenuItem(title: "Keep Expanded", action: #selector(togglePinFromMenu), keyEquivalent: "")
        pin.target = self
        menu.addItem(pin)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Dynamic Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func expandFromMenu() {
        expand()
    }

    @objc private func togglePinFromMenu() {
        state.pinned.toggle()
        if state.pinned { expand() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTitle: "Keep Expanded")?.state = state.pinned ? .on : .off
    }
}
