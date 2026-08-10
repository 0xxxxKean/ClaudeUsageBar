import AppKit
import CoreGraphics
import SwiftUI

/// A rounded sunburst mark inspired by Claude's brand mark: a set of soft,
/// rounded rays radiating from a center point. This is an original,
/// independently-drawn glyph in that visual language, not a reproduction of
/// Anthropic's trademarked logo asset.
enum ClaudeMark {
    static func path(
        in rect: CGRect,
        rayCount: Int = 8,
        innerRadiusRatio: CGFloat = 0.16,
        rayLengthRatio: CGFloat = 0.86,
        rayWidthRatio: CGFloat = 0.30
    ) -> CGPath {
        let path = CGMutablePath()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRadiusRatio
        let rayLength = outerRadius * rayLengthRatio
        let rayWidth = outerRadius * rayWidthRatio

        for index in 0..<rayCount {
            let angle = (CGFloat(index) / CGFloat(rayCount)) * 2 * .pi
            let rayRect = CGRect(
                x: -rayWidth / 2,
                y: innerRadius,
                width: rayWidth,
                height: rayLength
            )
            var transform = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: angle)
            let rayPath = CGPath(
                roundedRect: rayRect,
                cornerWidth: rayWidth / 2,
                cornerHeight: rayWidth / 2,
                transform: &transform
            )
            path.addPath(rayPath)
        }
        return path
    }

    /// Rasterizes the mark to an `NSImage` at `pointSize`, rendered into a
    /// higher-resolution offscreen bitmap so it stays crisp on Retina.
    ///
    /// The menu bar label is drawn by `MenuBarExtra` into an `NSStatusItem`
    /// button, a rendering path that — unlike a normal SwiftUI window —
    /// didn't reliably display a custom `Shape` (`ClaudeMarkShape`) here in
    /// practice, even after switching between `.fill()`/`.foregroundStyle()`
    /// and simplifying the geometry. A pre-rendered bitmap sidesteps that
    /// entirely; this is the same approach `Scripts/generate_app_icon.swift`
    /// already uses (successfully) for the Dock icon.
    static func image(
        pointSize: CGFloat,
        scale: CGFloat = 3,
        rayCount: Int = 6,
        innerRadiusRatio: CGFloat = 0.10,
        rayLengthRatio: CGFloat = 0.80,
        rayWidthRatio: CGFloat = 0.42,
        color: NSColor
    ) -> NSImage {
        let pixelSize = Int((pointSize * scale).rounded())
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: NSSize(width: pointSize, height: pointSize))
        }
        bitmap.size = NSSize(width: pointSize, height: pointSize)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let ctx = NSGraphicsContext.current!.cgContext
        // This context's logical coordinate space matches `bitmap.size`
        // (points, set above), not `pixelsWide`/`pixelsHigh` — draw in
        // points and let the higher-resolution backing store (from `scale`)
        // provide the Retina sharpness automatically.
        let rect = CGRect(x: 0, y: 0, width: pointSize, height: pointSize)
        let markPath = path(
            in: rect,
            rayCount: rayCount,
            innerRadiusRatio: innerRadiusRatio,
            rayLengthRatio: rayLengthRatio,
            rayWidthRatio: rayWidthRatio
        )
        ctx.addPath(markPath)
        ctx.setFillColor(color.cgColor)
        ctx.fillPath()

        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }
}

/// SwiftUI-native wrapper so the mark can be used directly as a View/Shape
/// (menu bar label, popover header) without any bitmap asset.
struct ClaudeMarkShape: Shape {
    var rayCount: Int = 8
    var innerRadiusRatio: CGFloat = 0.16
    var rayLengthRatio: CGFloat = 0.86
    var rayWidthRatio: CGFloat = 0.30

    func path(in rect: CGRect) -> Path {
        Path(ClaudeMark.path(
            in: rect,
            rayCount: rayCount,
            innerRadiusRatio: innerRadiusRatio,
            rayLengthRatio: rayLengthRatio,
            rayWidthRatio: rayWidthRatio
        ))
    }

    /// Fewer, thicker rays than the default mark. The 8-ray version reads
    /// fine at the popover's 18pt header size, but at menu-bar sizes
    /// (~13-16pt) its thin rays anti-alias into a fuzzy blob instead of a
    /// recognizable mark — this variant stays legible that small.
    static var compact: ClaudeMarkShape {
        ClaudeMarkShape(rayCount: 6, innerRadiusRatio: 0.10, rayLengthRatio: 0.80, rayWidthRatio: 0.42)
    }
}
