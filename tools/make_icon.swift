#!/usr/bin/env swift
// Renders the DisplaySwitcher app icon (the `display.2` glyph on a blue
// background) at every size the macOS asset catalog needs.
//
// Usage: swift tools/make_icon.swift
import AppKit

let outputDir = "DisplaySwitcher/Resources/Assets.xcassets/AppIcon.appiconset"
let iconsetDir = "build/AppIcon.iconset"

let gradientTop = NSColor(srgbRed: 0x38 / 255.0, green: 0xA8 / 255.0, blue: 0xFF / 255.0, alpha: 1.0)
let gradientBottom = NSColor(srgbRed: 0x00 / 255.0, green: 0x56 / 255.0, blue: 0xD8 / 255.0, alpha: 1.0)

func tinted(_ image: NSImage, with color: NSColor) -> NSImage {
    let tinted = NSImage(size: image.size)
    tinted.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: image.size))
    color.set()
    NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    return tinted
}

func renderIcon(pixelSize: CGFloat) -> NSImage {
    let canvas = 1024.0
    let scale = pixelSize / canvas
    let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
    image.lockFocus()

    // Blue background (full-bleed; macOS applies the rounded app-icon shape).
    let bg = NSBezierPath(rect: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    if let gradient = NSGradient(starting: gradientTop, ending: gradientBottom) {
        gradient.draw(in: bg, angle: -90)
    }

    // The same `display.2` glyph used by the menu-bar status item, in white.
    let glyphWidth = 0.46 * canvas * scale
    if let symbol = NSImage(systemSymbolName: "display.2", accessibilityDescription: nil),
       let configured = symbol.withSymbolConfiguration(
           NSImage.SymbolConfiguration(pointSize: glyphWidth, weight: .medium)) {
        let glyph = tinted(configured, with: .white)
        let size = glyph.size
        let x = (pixelSize - size.width) / 2
        let y = (pixelSize - size.height) / 2
        glyph.draw(in: NSRect(x: x, y: y, width: size.width, height: size.height))
    }

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        fputs("error: could not encode PNG for \(path)\n", stderr)
        exit(1)
    }
    do {
        try data.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }
}

let sizes: [(name: String, pixels: CGFloat)] = [
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

for entry in sizes {
    let image = renderIcon(pixelSize: entry.pixels)
    savePNG(image, path: "\(outputDir)/\(entry.name)")
    try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)
    savePNG(image, path: "\(iconsetDir)/\(entry.name)")
}
print("iconset written to \(iconsetDir)")
print("run: iconutil -c icns \(iconsetDir) -o DisplaySwitcher/Resources/AppIcon.icns")