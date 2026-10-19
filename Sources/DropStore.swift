import AppKit
import Foundation
import UniformTypeIdentifiers

struct DroppedItem: Identifiable {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    let size: Int64
    let icon: NSImage

    var name: String { url.lastPathComponent }
    var detail: String {
        guard !isDirectory else { return "Folder" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

final class DropStore: ObservableObject {
    @Published private(set) var items: [DroppedItem] = []
    @Published private(set) var selection: Set<UUID> = []

    private let maxItems = 40

    var totalSize: Int64 {
        items.filter { !$0.isDirectory }.reduce(0) { $0 + $1.size }
    }

    var totalSizeString: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        var known = Set(items.map { $0.url.standardizedFileURL })
        var newItems: [DroppedItem] = []

        for url in urls {
            let standardized = url.standardizedFileURL
            guard known.insert(standardized).inserted else { continue }
            let values = try? standardized.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            newItems.append(
                DroppedItem(
                    url: standardized,
                    isDirectory: values?.isDirectory ?? false,
                    size: Int64(values?.fileSize ?? 0),
                    icon: NSWorkspace.shared.icon(forFile: standardized.path)
                )
            )
        }

        guard !newItems.isEmpty else { return }
        items.append(contentsOf: newItems)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
    }

    /// Reads file URLs out of drop providers. Completion always runs on the main queue.
    func add(providers: [NSItemProvider]) {
        let identifier = UTType.fileURL.identifier
        let candidates = providers.filter { $0.hasItemConformingToTypeIdentifier(identifier) }
        guard !candidates.isEmpty else { return }

        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in candidates {
            group.enter()
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
                defer { group.leave() }
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let value = item as? URL {
                    url = value
                } else if let value = item as? NSURL {
                    url = value as URL
                } else if let string = item as? String {
                    url = URL(string: string)
                }
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.add(urls)
        }
    }

    func select(_ id: UUID, extending: Bool) {
        if extending {
            if selection.contains(id) {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
        } else if !selection.contains(id) {
            selection = [id]
        }
    }

    func deselectAll() {
        selection.removeAll()
    }

    func setSelection(_ ids: Set<UUID>) {
        selection = ids
    }

    func urlsForDrag(of item: DroppedItem) -> [URL] {
        if selection.contains(item.id) {
            let selected = items.filter { selection.contains($0.id) }
            if selected.count > 1 {
                return selected.map(\.url)
            }
        }
        return [item.url]
    }

    func remove(_ item: DroppedItem) {
        items.removeAll { $0.id == item.id }
        selection.remove(item.id)
    }

    func clear() {
        items.removeAll()
        selection.removeAll()
    }

    func reveal() {
        guard !items.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
    }

}
