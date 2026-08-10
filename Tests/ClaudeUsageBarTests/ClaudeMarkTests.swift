import AppKit
import Testing
@testable import ClaudeUsageBar

/// Regression coverage for a real bug: `ClaudeMark.image` originally drew
/// into the offscreen bitmap using pixel-sized coordinates while the
/// context's actual coordinate space was in points, so the whole mark ended
/// up squeezed into one corner of the canvas instead of filling it. These
/// checks would have caught that: they fail if the colored pixels are
/// confined to one quadrant instead of spanning the canvas.
@Test func markImageFillsCanvasNotJustOneCorner() throws {
    let pointSize: CGFloat = 15
    let image = ClaudeMark.image(pointSize: pointSize, scale: 3, color: .red)

    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
        Issue.record("could not read back rendered bitmap")
        return
    }

    let width = bitmap.pixelsWide
    let height = bitmap.pixelsHigh
    var minX = width, maxX = 0, minY = height, maxY = 0
    for px in 0..<width {
        for py in 0..<height {
            guard let color = bitmap.colorAt(x: px, y: py), color.alphaComponent > 0.5 else { continue }
            minX = min(minX, px)
            maxX = max(maxX, px)
            minY = min(minY, py)
            maxY = max(maxY, py)
        }
    }

    // Bug this guards against: the mark was drawn using pixel-sized
    // coordinates into a context whose logical space was actually in
    // points, so it ended up squeezed into a small corner of the canvas
    // instead of spanning it. Assert the opaque pixels' bounding box covers
    // most of the canvas in both axes, not just a fraction confined to one
    // corner.
    #expect(maxX > minX, "no opaque pixels found at all")
    let coveredWidthFraction = Double(maxX - minX) / Double(width)
    let coveredHeightFraction = Double(maxY - minY) / Double(height)
    #expect(coveredWidthFraction > 0.6, "opaque pixels only span \(coveredWidthFraction) of canvas width")
    #expect(coveredHeightFraction > 0.6, "opaque pixels only span \(coveredHeightFraction) of canvas height")
}

@Test func markImageHasCorrectPointSize() {
    let image = ClaudeMark.image(pointSize: 15, scale: 3, color: .red)
    #expect(image.size == NSSize(width: 15, height: 15))
}
