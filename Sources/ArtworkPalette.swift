import AppKit

/// A dark two-stop gradient derived from the dominant vivid color of the artwork.
struct ArtworkPalette: Equatable, Identifiable {
    let top: NSColor
    let bottom: NSColor
    let id = UUID()

    static func == (lhs: ArtworkPalette, rhs: ArtworkPalette) -> Bool {
        lhs.id == rhs.id
    }
}

/// Downsamples the cover and averages its vivid pixels, then clamps the result to
/// a dark tint that keeps the island's white content readable.
func extractArtworkPalette(from image: NSImage) -> ArtworkPalette? {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
    }

    let side = 24
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: &pixels,
              width: side,
              height: side,
              bitsPerComponent: 8,
              bytesPerRow: side * 4,
              space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        return nil
    }
    context.interpolationQuality = .medium
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

    var red = 0.0
    var green = 0.0
    var blue = 0.0
    var weight = 0.0
    var vivid = 0.0

    for index in stride(from: 0, to: pixels.count, by: 4) {
        let r = Double(pixels[index]) / 255
        let g = Double(pixels[index + 1]) / 255
        let b = Double(pixels[index + 2]) / 255
        let high = max(r, max(g, b))
        let low = min(r, min(g, b))
        let saturation = high > 0 ? (high - low) / high : 0
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        vivid = max(vivid, saturation)

        // Skip black, blown-out white and near-gray pixels so a logo or cover
        // photos drive the hue instead of the background.
        guard luminance > 0.05, luminance < 0.97, saturation > 0.08 else { continue }
        let pixelWeight = 0.15 + saturation * saturation * 2.5
        red += r * pixelWeight
        green += g * pixelWeight
        blue += b * pixelWeight
        weight += pixelWeight
    }

    guard weight > 0, vivid > 0.1 else { return nil }

    let average = NSColor(
        srgbRed: red / weight,
        green: green / weight,
        blue: blue / weight,
        alpha: 1
    )
    guard let srgb = average.usingColorSpace(.sRGB) else { return nil }

    var hue: CGFloat = 0
    var saturation: CGFloat = 0
    var brightness: CGFloat = 0
    var alpha: CGFloat = 0
    srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

    let tintSaturation = min(0.82, max(0.42, saturation * 0.95))
    let top = NSColor(
        hue: hue,
        saturation: tintSaturation,
        brightness: 0.20,
        alpha: 1
    )
    let bottom = NSColor(
        hue: hue,
        saturation: tintSaturation * 0.9,
        brightness: 0.045,
        alpha: 1
    )
    return ArtworkPalette(top: top, bottom: bottom)
}
