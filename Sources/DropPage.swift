import SwiftUI

private let shelfAccent = Color(red: 0.39, green: 0.60, blue: 1.0)

struct DropPage: View {
    @ObservedObject var store: DropStore
    @ObservedObject var state: IslandState

    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    @State private var marqueeIgnored = false
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var hoveredID: UUID?

    var body: some View {
        Group {
            if store.items.isEmpty {
                emptyState
            } else {
                filledState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.white.opacity(0.55))
            Text("Drop files or folders")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("Hold them here while you switch apps, drag them back out later.")
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.15), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
        )
        .overlay(alignment: .top) {
            if state.dropActive && !state.internalDragActive {
                Text("Release to add")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(red: 0.30, green: 0.50, blue: 1.0)))
                    .padding(.top, 7)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Filled

    private var filledState: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            list
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if state.dropActive && !state.internalDragActive {
                Text("Release to add")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(red: 0.30, green: 0.50, blue: 1.0)))
            } else {
                Text("\(store.items.count) item\(store.items.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Text("· \(store.totalSizeString)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.35))

                if store.selection.count > 1 {
                    Text("· \(store.selection.count) selected")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(shelfAccent.opacity(0.9))
                }
            }

            Spacer(minLength: 8)

            GlassIconButton(systemName: "folder", size: 10, help: "Reveal in Finder") {
                store.reveal()
            }
            GlassIconButton(systemName: "trash", size: 10, help: "Clear") {
                store.clear()
                hoveredID = nil
            }
        }
        .padding(.horizontal, 2)
    }

    private var list: some View {
        ZStack(alignment: .topLeading) {
            ScrollView(.vertical) {
                LazyVStack(spacing: 2) {
                    ForEach(store.items) { item in
                        DropRow(
                            item: item,
                            isSelected: store.selection.contains(item.id),
                            dragURLs: { store.urlsForDrag(of: item) },
                            onSelect: { extending in
                                store.select(item.id, extending: extending)
                            },
                            onMarquee: { startLocal, currentLocal in
                                guard let frame = rowFrames[item.id] else { return }
                                // Use the delta only: SwiftUI's scroll transform means the
                                // row's window position differs from its layout position.
                                let start = CGPoint(x: frame.midX, y: frame.midY)
                                let current = CGPoint(
                                    x: start.x + (currentLocal.x - startLocal.x),
                                    y: start.y + (startLocal.y - currentLocal.y)
                                )
                                beginMarquee(start, current)
                            },
                            onMarqueeEnd: { endMarquee() },
                            onDragStateChanged: { active in
                                state.internalDragActive = active
                                if active { state.dropActive = false }
                            },
                            isHovered: hoveredID == item.id,
                            onHover: { hovering in
                                if hovering {
                                    hoveredID = item.id
                                } else if hoveredID == item.id {
                                    hoveredID = nil
                                }
                            }
                        ) {
                            removeItem(item)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .gesture(marqueeGesture)

            if let rect = marqueeRect {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(shelfAccent.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(shelfAccent.opacity(0.65), lineWidth: 1)
                    )
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: "shelf")
        .onPreferenceChange(RowFramesKey.self) { rowFrames = $0 }
    }

    // MARK: - Marquee selection

    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("shelf"))
            .onChanged { value in
                if marqueeStart == nil && !marqueeIgnored {
                    // A drag that starts on a row belongs to the row's file drag.
                    if rowFrames.values.contains(where: { $0.contains(value.startLocation) }) {
                        marqueeIgnored = true
                        return
                    }
                    marqueeStart = value.startLocation
                    store.deselectAll()
                }
                guard !marqueeIgnored, marqueeStart != nil else { return }
                marqueeCurrent = value.location
                applyMarquee()
            }
            .onEnded { _ in
                marqueeStart = nil
                marqueeCurrent = nil
                marqueeIgnored = false
            }
    }

    private var marqueeRect: CGRect? {
        guard let start = marqueeStart, let current = marqueeCurrent else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    private func removeItem(_ item: DroppedItem) {
        guard let index = store.items.firstIndex(where: { $0.id == item.id }) else { return }
        let hoveredBefore = hoveredID
        store.remove(item)
        hoveredID = hoveredIDAfterRemoving(
            items: store.items,
            removedIndex: index,
            hoveredBefore: hoveredBefore,
            removedID: item.id
        )
    }

    private func beginMarquee(_ start: CGPoint, _ current: CGPoint) {
        if marqueeStart == nil {
            marqueeStart = start
        }
        marqueeCurrent = current
        applyMarquee()
    }

    private func endMarquee() {
        marqueeStart = nil
        marqueeCurrent = nil
    }

    private func applyMarquee() {
        guard let rect = marqueeRect else { return }
        let hits = rowFrames.filter { $0.value.intersects(rect) }.map(\.key)
        store.setSelection(Set(hits))
    }


}

private struct DropRow: View {
    let item: DroppedItem
    let isSelected: Bool
    let dragURLs: () -> [URL]
    let onSelect: (Bool) -> Void
    let onMarquee: (CGPoint, CGPoint) -> Void
    let onMarqueeEnd: () -> Void
    let onDragStateChanged: (Bool) -> Void
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(nsImage: item.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 19, height: 19)

                Text(item.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 6)

                Text(item.detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.32))
                    .lineLimit(1)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay(
                RowDragHandle(
                    urls: dragURLs,
                    onPress: onSelect,
                    selected: isSelected,
                    onMarquee: onMarquee,
                    onMarqueeEnd: onMarqueeEnd,
                    onDragStateChanged: onDragStateChanged
                )
            )

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(.white.opacity(0.08)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .help("Remove")
        }
        .padding(.horizontal, 7)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                        ? shelfAccent.opacity(0.18)
                        : Color.white.opacity(isHovered ? 0.07 : 0.025)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? shelfAccent.opacity(0.55) : Color.clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover(perform: onHover)
        .help(
            isSelected
                ? "Drag to move the selected files · ⇧/⌘-click to add or remove"
                : "Drag to move this file · ⇧/⌘-click to select several"
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: RowFramesKey.self,
                    value: [item.id: proxy.frame(in: .named("shelf"))]
                )
            }
        )
    }
}

private struct RowFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// After a row is removed the next row slides under the stationary pointer.
/// Keep the hover on that row so its x button stays visible.
func hoveredIDAfterRemoving(
    items: [DroppedItem],
    removedIndex: Int,
    hoveredBefore: UUID?,
    removedID: UUID
) -> UUID? {
    guard hoveredBefore == removedID else { return hoveredBefore }
    return items.indices.contains(removedIndex) ? items[removedIndex].id : nil
}
