#!/usr/bin/env swift
// Generates multiple icon candidates using different SF Symbols and color schemes.
// Usage: swift scripts/generate-icon-candidates.swift

import AppKit

struct IconCandidate {
    let symbolName: String
    let label: String
    let gradientStart: NSColor
    let gradientEnd: NSColor
}

let candidates: [IconCandidate] = [
    IconCandidate(
        symbolName: "text.below.photo",
        label: "1-text-below-photo",
        gradientStart: NSColor(red: 0.20, green: 0.10, blue: 0.35, alpha: 1),
        gradientEnd: NSColor(red: 0.10, green: 0.05, blue: 0.20, alpha: 1)
    ),
    IconCandidate(
        symbolName: "photo.on.rectangle.angled",
        label: "2-photo-stacked",
        gradientStart: NSColor(red: 0.05, green: 0.20, blue: 0.30, alpha: 1),
        gradientEnd: NSColor(red: 0.02, green: 0.10, blue: 0.18, alpha: 1)
    ),
    IconCandidate(
        symbolName: "doc.text.image",
        label: "3-doc-text-image",
        gradientStart: NSColor(red: 0.12, green: 0.22, blue: 0.15, alpha: 1),
        gradientEnd: NSColor(red: 0.05, green: 0.12, blue: 0.08, alpha: 1)
    ),
    IconCandidate(
        symbolName: "sparkle.magnifyingglass",
        label: "4-sparkle-search",
        gradientStart: NSColor(red: 0.30, green: 0.15, blue: 0.05, alpha: 1),
        gradientEnd: NSColor(red: 0.18, green: 0.08, blue: 0.02, alpha: 1)
    ),
    IconCandidate(
        symbolName: "rectangle.and.text.magnifyingglass",
        label: "5-rect-text-search",
        gradientStart: NSColor(red: 0.15, green: 0.15, blue: 0.20, alpha: 1),
        gradientEnd: NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1)
    ),
    IconCandidate(
        symbolName: "eye.circle",
        label: "6-eye-circle",
        gradientStart: NSColor(red: 0.25, green: 0.08, blue: 0.15, alpha: 1),
        gradientEnd: NSColor(red: 0.15, green: 0.04, blue: 0.08, alpha: 1)
    ),
]

let size = NSSize(width: 512, height: 512)
let padding: CGFloat = 80
let cornerRadius: CGFloat = 110

let outputDir = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Distribution/icon-candidates")

try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

for candidate in candidates {
    guard let symbol = NSImage(systemSymbolName: candidate.symbolName, accessibilityDescription: nil) else {
        print("SKIP: \(candidate.symbolName) not found")
        continue
    }

    let image = NSImage(size: size)
    image.lockFocus()

    // Background
    let bgRect = NSRect(origin: .zero, size: size)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
    let gradient = NSGradient(starting: candidate.gradientStart, ending: candidate.gradientEnd)!
    gradient.draw(in: bgPath, angle: -90)

    // Symbol
    let symbolRect = NSRect(
        x: padding, y: padding,
        width: size.width - padding * 2,
        height: size.height - padding * 2
    )
    let config = NSImage.SymbolConfiguration(pointSize: 250, weight: .regular)
        .applying(.init(paletteColors: [.white]))
    let configured = symbol.withSymbolConfiguration(config)!
    configured.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)

    image.unlockFocus()

    // Save
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { continue }

    let outPath = outputDir.appendingPathComponent("\(candidate.label).png")
    try png.write(to: outPath)
    print("Generated: \(candidate.label).png")
}

print("\nAll icons saved to: \(outputDir.path)")
