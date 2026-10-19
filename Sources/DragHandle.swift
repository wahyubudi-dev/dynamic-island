import AppKit
import SwiftUI

/// Transparent row overlay that selects on press and starts a native drag session
/// carrying the row's file, or every selected file when the row is part of a group.
struct RowDragHandle: NSViewRepresentable {
    let urls: () -> [URL]
    let onPress: (Bool) -> Void
    let selected: Bool
    let onMarquee: (CGPoint, CGPoint) -> Void
    let onMarqueeEnd: () -> Void
    let onDragStateChanged: (Bool) -> Void

    func makeNSView(context: Context) -> RowDragSourceView {
        let view = RowDragSourceView()
        view.urls = urls
        view.onPress = onPress
        view.selected = selected
        view.onMarquee = onMarquee
        view.onMarqueeEnd = onMarqueeEnd
        view.onDragStateChanged = onDragStateChanged
        view.toolTip = "Drag to select · ⇧/⌘-click to toggle selection"
        return view
    }

    func updateNSView(_ nsView: RowDragSourceView, context: Context) {
        nsView.urls = urls
        nsView.onPress = onPress
        nsView.selected = selected
        nsView.onMarquee = onMarquee
        nsView.onMarqueeEnd = onMarqueeEnd
        nsView.onDragStateChanged = onDragStateChanged
    }
}

final class RowDragSourceView: NSView {
    var urls: () -> [URL] = { [] }
    var onPress: ((Bool) -> Void)?
    var selected = false
    var onMarquee: ((CGPoint, CGPoint) -> Void)?
    var onMarqueeEnd: (() -> Void)?
    var onDragStateChanged: ((Bool) -> Void)?

    private var pendingMouseDown: NSEvent?
    private var dragStart: NSPoint?
    private var marqueeActive = false
    private var dragStartedSelected = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartedSelected = selected
        dragStart = convert(event.locationInWindow, from: nil)
        let extends = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift)
        onPress?(extends)
        pendingMouseDown = event
    }

    override func mouseUp(with event: NSEvent) {
        pendingMouseDown = nil
        dragStart = nil
        if marqueeActive {
            marqueeActive = false
            onMarqueeEnd?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = pendingMouseDown, let start = dragStart else { return }
        let current = convert(event.locationInWindow, from: nil)
        let dx = current.x - start.x
        let dy = current.y - start.y

        // Ignore sub-pixel jitter so shift/cmd-clicking does not turn into a marquee.
        guard dx * dx + dy * dy >= 25 else { return }

        // Already-selected rows move their files straight away; marquee is for
        // selecting rows that are not part of the current selection.
        if dragStartedSelected {
            pendingMouseDown = nil
            dragStart = nil
            beginFileDrag(with: down)
            return
        }

        if let window, let content = window.contentView,
           !content.bounds.contains(event.locationInWindow) {
            // Leaving the island turns the gesture into a real file drag.
            pendingMouseDown = nil
            dragStart = nil
            if marqueeActive {
                marqueeActive = false
                onMarqueeEnd?()
            }
            beginFileDrag(with: down)
            return
        }

        marqueeActive = true
        onMarquee?(start, current)
    }

    private func beginFileDrag(with event: NSEvent) {
        let fileURLs = urls()
        guard !fileURLs.isEmpty else { return }

        var items: [NSDraggingItem] = []
        for (index, url) in fileURLs.prefix(40).enumerated() {
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 40, height: 40)
            let offset = CGFloat(index % 4) * 5
            item.setDraggingFrame(
                NSRect(x: offset, y: -offset, width: 40, height: 40),
                contents: icon
            )
            items.append(item)
        }

        guard !items.isEmpty else { return }
        onDragStateChanged?(true)
        beginDraggingSession(with: items, event: event, source: self)
    }
}

extension RowDragSourceView: NSDraggingSource {
    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .outsideApplication ? .copy : .generic
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        onDragStateChanged?(false)
    }
}
