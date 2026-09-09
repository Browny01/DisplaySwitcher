#!/usr/bin/env swift
// Renders the DisplaySwitcher app icon (the `display.2` glyph on a blue
// background) at exactly the pixel sizes the macOS asset catalog / .icns
// need.
//
// Usage:
//   swift tools/make_icon.swift
//   iconutil -c icns build/AppIcon.iconset -o DisplaySwitcher/Resources/AppIcon.icns
import AppKit

let outputDir = "DisplaySwitcher/Resources/Assets.xcassets/AppIcon.appiconset"
let iconsetDir = "build/AppIcon.iconset"

let gradientTop = NSColor(srgbRed: 0x38 / 255.0, green: 0xA8 / 255.0, blue: 0xFF / 255.0, alpha: 1.0)
let gradientBottom = NSColor(srgbRed: 0x00 / 255.0, green: 0x56 / 255.0, blue: 0xD8 / 255.0, alpha: 1.0)

/// Renders the icon into an exact-width RGBA bitmap (not point-based, so a
/// retina device cannot silently double the pixel dimensions).
func renderIcon(pixelSize: Int) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize, pixelsHigh: pixelSize,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        fputs("error: could not allocate \(pixelSize)x\(pixelSize) bitmap\n", stderr)
        exit(1)
    }

    let s = CGFloat(pixelSize)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    let bg = NSBezierPath(rect: NSRect(x: 0, y: 0, width: s, height: s))
    if let gradient = NSGradient(starting: gradientTop, ending: gradientBottom) {
        gradient.draw(in: bg, angle: -90)
    }

    // The same `display.2` glyph used by the menu-bar status item, tinted white.
    let glyphWidth = 0.46 * s
    if let symbol = NSImage(systemSymbolName: "display.2", accessibilityDescription: nil) {
        let white = NSImage.SymbolConfiguration(hierarchicalColor: .white)
        let config = NSImage.SymbolConfiguration(pointSize: glyphWidth, weight: .medium).applying(white)
        if let configured = symbol.withSymbolConfiguration(config) {
            let size = configured.size
            let x = (s - size.width) / 2
            let y = (s - size.height) / 2
            configured.draw(in: NSRect(x: x, y: y, width: size.width, height: size.height))
        }
    }

    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func savePNG(_ rep: NSBitmapImageRep, path: String) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fputs("error: could not encode PNG for \(path)\n", stderr)
        exit(1)
    }
    do {
        try data.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }
}

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)
for entry in sizes {
    let rep = renderIcon(pixelSize: entry.pixels)
    savePNG(rep, path: "\(outputDir)/\(entry.name)")
    savePNG(rep, path: "\(iconsetDir)/\(entry.name)")
}
print("iconset written to \(iconsetDir)")
print("run: iconutil -c icns \(iconsetDir) -o DisplaySwitcher/Resources/AppIcon.icns")