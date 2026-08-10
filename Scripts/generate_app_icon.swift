#!/usr/bin/env swift
import AppKit
import CoreGraphics

// Standalone icon-generation tool (run via `swift Scripts/generate_app_icon.swift`).
// Deliberately duplicates the small sunburst-path math from
// Sources/ClaudeUsageBar/Graphics/ClaudeMark.swift rather than importing the
// app module, since this is a one-off build-time asset generator, not app logic.

func sunburstPath(in rect: CGRect, rayCount: Int = 8) -> CGPath {
    let path = CGMutablePath()
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let outerRadius = min(rect.width, rect.height) / 2
    let innerRadius = outerRadius * 0.16
    let rayLength = outerRadius * 0.86
    let rayWidth = outerRadius * 0.30

    for index in 0..<rayCount {
        let angle = (CGFloat(index) / CGFloat(rayCount)) * 2 * .pi
        let rayRect = CGRect(x: -rayWidth / 2, y: innerRadius, width: rayWidth, height: rayLength)
        var transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
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

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let inset = size * 0.03
    let canvasRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let cornerRadius = canvasRect.width * 0.22

    let background = CGPath(roundedRect: canvasRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(background)
    ctx.setFillColor(CGColor(red: 0.98, green: 0.96, blue: 0.93, alpha: 1.0))
    ctx.fillPath()

    ctx.addPath(background)
    ctx.setStrokeColor(CGColor(red: 0.87, green: 0.83, blue: 0.77, alpha: 1.0))
    ctx.setLineWidth(size * 0.004)
    ctx.strokePath()

    let markInset = canvasRect.width * 0.22
    let markRect = canvasRect.insetBy(dx: markInset, dy: markInset)
    ctx.addPath(sunburstPath(in: markRect))
    ctx.setFillColor(CGColor(red: 0.80, green: 0.47, blue: 0.34, alpha: 1.0))
    ctx.fillPath()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL, size: CGFloat) {
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        fputs("Failed to encode PNG for \(url.lastPathComponent)\n", stderr)
        exit(1)
    }
    try? data.write(to: url)
}

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let projectRoot = scriptDir.deletingLastPathComponent()
let iconsetDir = projectRoot.appendingPathComponent("dist/AppIcon.iconset")

try? FileManager.default.removeItem(at: iconsetDir)
try! FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let sizes: [(name: String, points: CGFloat, scale: CGFloat)] = [
    ("icon_16x16", 16, 1), ("icon_16x16@2x", 16, 2),
    ("icon_32x32", 32, 1), ("icon_32x32@2x", 32, 2),
    ("icon_128x128", 128, 1), ("icon_128x128@2x", 128, 2),
    ("icon_256x256", 256, 1), ("icon_256x256@2x", 256, 2),
    ("icon_512x512", 512, 1), ("icon_512x512@2x", 512, 2),
]

for entry in sizes {
    let pixelSize = entry.points * entry.scale
    let image = drawIcon(size: pixelSize)
    let url = iconsetDir.appendingPathComponent("\(entry.name).png")
    writePNG(image, to: url, size: pixelSize)
}

print("Wrote iconset to \(iconsetDir.path)")
