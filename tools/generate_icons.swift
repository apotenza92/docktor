#!/usr/bin/env swift

import AppKit

struct IconSpec {
    let size: Int
    let filename: String
}

struct IconTheme {
    let baseTop: NSColor
    let baseBottom: NSColor
    let diagonalTop: NSColor
    let diagonalMid: NSColor
    let diagonalBottom: NSColor
    let vignetteBottom: NSColor
    let glyphTopAlpha: CGFloat
    let glyphBottomAlpha: CGFloat
}

struct IconSet {
    let folderName: String
    let label: String
    let theme: IconTheme
}

let specs: [IconSpec] = [
    .init(size: 16, filename: "icon_16x16.png"),
    .init(size: 32, filename: "icon_16x16@2x.png"),
    .init(size: 32, filename: "icon_32x32.png"),
    .init(size: 64, filename: "icon_32x32@2x.png"),
    .init(size: 128, filename: "icon_128x128.png"),
    .init(size: 256, filename: "icon_128x128@2x.png"),
    .init(size: 256, filename: "icon_256x256.png"),
    .init(size: 512, filename: "icon_256x256@2x.png"),
    .init(size: 512, filename: "icon_512x512.png"),
    .init(size: 1024, filename: "icon_512x512@2x.png")
]

let stableTheme = IconTheme(
    baseTop: NSColor(calibratedRed: 0.77, green: 0.98, blue: 0.89, alpha: 1.0),
    baseBottom: NSColor(calibratedRed: 0.08, green: 0.73, blue: 0.55, alpha: 1.0),
    diagonalTop: NSColor(calibratedRed: 0.96, green: 1.00, blue: 0.98, alpha: 0.36),
    diagonalMid: NSColor(calibratedRed: 0.41, green: 0.93, blue: 0.77, alpha: 0.11),
    diagonalBottom: NSColor(calibratedRed: 0.03, green: 0.53, blue: 0.40, alpha: 0.24),
    vignetteBottom: NSColor(calibratedRed: 0.02, green: 0.34, blue: 0.25, alpha: 0.20),
    glyphTopAlpha: 0.99,
    glyphBottomAlpha: 0.74
)

let betaTheme = IconTheme(
    baseTop: NSColor(calibratedRed: 0.58, green: 0.79, blue: 1.00, alpha: 1.0),
    baseBottom: NSColor(calibratedRed: 0.29, green: 0.27, blue: 0.82, alpha: 1.0),
    diagonalTop: NSColor(calibratedRed: 0.92, green: 0.96, blue: 1.00, alpha: 0.36),
    diagonalMid: NSColor(calibratedRed: 0.60, green: 0.72, blue: 1.00, alpha: 0.11),
    diagonalBottom: NSColor(calibratedRed: 0.20, green: 0.18, blue: 0.58, alpha: 0.24),
    vignetteBottom: NSColor(calibratedRed: 0.12, green: 0.11, blue: 0.33, alpha: 0.22),
    glyphTopAlpha: 0.99,
    glyphBottomAlpha: 0.74
)

let iconSets: [IconSet] = [
    .init(folderName: "AppIcon.appiconset", label: "stable", theme: stableTheme),
    .init(folderName: "AppIconBeta.appiconset", label: "beta", theme: betaTheme)
]

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let assetsCatalog = cwd.appendingPathComponent("Dockmint/Assets.xcassets", isDirectory: true)

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func newStrokePath(lineWidth: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.lineWidth = lineWidth
    path.lineJoinStyle = .round
    path.lineCapStyle = .round
    return path
}

func lucidePoint(_ x: CGFloat, _ y: CGFloat, in rect: NSRect) -> NSPoint {
    NSPoint(
        x: rect.minX + rect.width * (x / 24.0),
        y: rect.minY + rect.height * ((24.0 - y) / 24.0)
    )
}

func drawLeafGlyph(
    in rect: NSRect,
    strokeColor: NSColor,
    lineWidth: CGFloat
) {
    strokeColor.setStroke()
    let strokeWidth = lineWidth * min(rect.width, rect.height) / 24.0

    let leaf = newStrokePath(lineWidth: strokeWidth)
    leaf.move(to: lucidePoint(11.0, 20.0, in: rect))
    leaf.curve(to: lucidePoint(9.8, 6.1, in: rect),
               controlPoint1: lucidePoint(7.2, 18.0, in: rect),
               controlPoint2: lucidePoint(6.9, 9.7, in: rect))
    leaf.curve(to: lucidePoint(19.0, 2.0, in: rect),
               controlPoint1: lucidePoint(15.5, 5.0, in: rect),
               controlPoint2: lucidePoint(17.0, 4.48, in: rect))
    leaf.curve(to: lucidePoint(21.0, 10.0, in: rect),
               controlPoint1: lucidePoint(20.0, 4.0, in: rect),
               controlPoint2: lucidePoint(21.0, 6.18, in: rect))
    leaf.curve(to: lucidePoint(11.0, 20.0, in: rect),
               controlPoint1: lucidePoint(21.0, 15.5, in: rect),
               controlPoint2: lucidePoint(16.22, 20.0, in: rect))
    leaf.close()
    leaf.stroke()

    let vein = newStrokePath(lineWidth: strokeWidth)
    vein.move(to: lucidePoint(2.0, 21.0, in: rect))
    vein.curve(to: lucidePoint(7.08, 15.0, in: rect),
               controlPoint1: lucidePoint(2.0, 18.0, in: rect),
               controlPoint2: lucidePoint(3.85, 15.64, in: rect))
    vein.curve(to: lucidePoint(13.0, 12.0, in: rect),
               controlPoint1: lucidePoint(9.5, 14.52, in: rect),
               controlPoint2: lucidePoint(12.0, 13.0, in: rect))
    vein.stroke()
}

func drawIcon(size: Int, theme: IconTheme) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))

    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high
    let canvas = NSRect(x: 0, y: 0, width: s, height: s)
    NSColor.clear.setFill()
    canvas.fill()

    let outerInset = s * 0.06
    let outerRect = canvas.insetBy(dx: outerInset, dy: outerInset)
    let outer = roundedRect(outerRect, radius: s * 0.22)

    let baseGradient = NSGradient(colors: [theme.baseTop, theme.baseBottom])!
    baseGradient.draw(in: outer, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    outer.addClip()

    let diagonal = NSGradient(colors: [
        theme.diagonalTop,
        theme.diagonalMid,
        theme.diagonalBottom
    ])!
    diagonal.draw(in: outerRect, angle: -35)

    let subtleVignette = NSGradient(colors: [
        NSColor(calibratedWhite: 0.0, alpha: 0.0),
        theme.vignetteBottom
    ])!
    subtleVignette.draw(in: outerRect, relativeCenterPosition: NSPoint(x: 0.0, y: -0.15))

    NSGraphicsContext.restoreGraphicsState()

    let glyphRect = outerRect.insetBy(dx: s * 0.10, dy: s * 0.10)

    drawLeafGlyph(
        in: glyphRect,
        strokeColor: NSColor(calibratedWhite: 1.0, alpha: theme.glyphTopAlpha),
        lineWidth: 2.0
    )

    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "DockmintIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    try data.write(to: url, options: .atomic)
}

func appIconContentsJSON() -> String {
    """
    {
      "images" : [
        { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
        { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
        { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
        { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
        { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
        { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
        { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
        { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
        { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
        { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }
    """
}

guard fm.fileExists(atPath: assetsCatalog.path) else {
    fputs("Missing assets catalog: \(assetsCatalog.path)\n", stderr)
    exit(1)
}

for iconSet in iconSets {
    let iconsetURL = assetsCatalog.appendingPathComponent(iconSet.folderName, isDirectory: true)
    try fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

    for spec in specs {
        let image = drawIcon(size: spec.size, theme: iconSet.theme)
        let out = iconsetURL.appendingPathComponent(spec.filename)
        try writePNG(image, to: out)
        print("Wrote \(out.path)")
    }

    let contentsURL = iconsetURL.appendingPathComponent("Contents.json")
    try appIconContentsJSON().data(using: .utf8)?.write(to: contentsURL, options: .atomic)
    print("Updated \(contentsURL.path) [\(iconSet.label)]")
}
