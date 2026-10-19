import AppKit

/// Computes the island frames for a screen, hugging the notch when one exists.
struct IslandGeometry {
    static let expandedBaseSize = CGSize(width: 600, height: 144)
    static let collapsedInsetWidth: CGFloat = 6
    static let collapsedInsetHeight: CGFloat = 4

    let screen: NSScreen

    var notchHeight: CGFloat {
        max(screen.safeAreaInsets.top, 0)
    }

    var notchWidth: CGFloat? {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return nil }
        let width = screen.frame.width - left.width - right.width
        return width > 40 ? width : nil
    }

    var collapsedSize: CGSize {
        if let notchWidth {
            // Stay inside the physical notch so the idle island does not protrude.
            return CGSize(
                width: max(notchWidth - Self.collapsedInsetWidth, 40),
                height: max(notchHeight - Self.collapsedInsetHeight, 12)
            )
        }
        return CGSize(width: 200, height: 30)
    }

    func frame(expanded: Bool) -> NSRect {
        let size: CGSize
        if expanded {
            // The physical notch overlaps the top of the window, so reserve its height
            // above the content instead of letting it clip the title and artwork.
            size = CGSize(
                width: Self.expandedBaseSize.width,
                height: Self.expandedBaseSize.height + notchHeight
            )
        } else {
            size = collapsedSize
        }
        let rawX = screen.frame.midX - size.width / 2
        let x = min(max(rawX.rounded(), screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
        return NSRect(x: x, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
    }

    static func preferredScreen() -> NSScreen {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
