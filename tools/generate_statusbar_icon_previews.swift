#!/usr/bin/env swift

import AppKit

struct PreviewSpec {
    let size: Int
}

let specs: [PreviewSpec] = [
    .init(size: 16),
    .init(size: 18),
    .init(size: 20),
    .init(size: 24),
    .init(size: 32)
]

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let outputDir = cwd.appendingPathComponent("artifacts/statusbar-icon-previews", isDirectory: true)

private let referenceViewBox = NSSize(width: 1000.0, height: 1000.0)
private let leafAffine = CGAffineTransform(
    a: -1.66155,
    b: -0.959297,
    c: -0.628757,
    d: 1.089039,
    tx: 1664.712115,
    ty: 471.805902
)
private let stemAffine = CGAffineTransform(
    a: -0.518933,
    b: -0.420401,
    c: -0.108986,
    d: 0.156395,
    tx: 492.769665,
    ty: 925.252616
)

func fittedReferenceRect(in rect: NSRect, scale: CGFloat = 1.12, yOffset: CGFloat = 0.01) -> NSRect {
    let fitted = NSSize(width: rect.height * (referenceViewBox.width / referenceViewBox.height), height: rect.height)
    let scaled = NSSize(width: fitted.width * scale, height: fitted.height * scale)
    return NSRect(
        x: rect.midX - scaled.width / 2.0,
        y: rect.midY - scaled.height / 2.0 + rect.height * yOffset,
        width: scaled.width,
        height: scaled.height
    )
}

func sourcePoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x, y: y)
}

func drawingTransform(for rect: NSRect) -> CGAffineTransform {
    var transform = CGAffineTransform(translationX: rect.minX, y: rect.maxY)
    transform = transform.scaledBy(
        x: rect.width / referenceViewBox.width,
        y: -rect.height / referenceViewBox.height
    )
    return transform
}

func referenceLeafPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: sourcePoint(496.366, 64.337))
    path.addCurve(
        to: sourcePoint(405.654, 240.339),
        control1: sourcePoint(496.366, 64.337),
        control2: sourcePoint(460.654, 51.382)
    )
    path.addCurve(
        to: sourcePoint(542.995, 683.745),
        control1: sourcePoint(347.612, 439.746),
        control2: sourcePoint(366.104, 754.969)
    )
    path.addCurve(
        to: sourcePoint(573.28, 343.052),
        control1: sourcePoint(641.586, 644.048),
        control2: sourcePoint(601.525, 462.418)
    )
    path.addCurve(
        to: sourcePoint(496.366, 64.337),
        control1: sourcePoint(509.198, 72.236),
        control2: sourcePoint(496.366, 64.337)
    )
    path.closeSubpath()

    var transform = leafAffine
    return path.copy(using: &transform) ?? path
}

func referenceStemFillPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: sourcePoint(413.769, -615.48))
    path.addCurve(
        to: sourcePoint(568.796, 949.941),
        control1: sourcePoint(413.769, -615.48),
        control2: sourcePoint(528.885, 590.915)
    )
    path.addCurve(
        to: sourcePoint(434.067, 1056.694),
        control1: sourcePoint(598.702, 1218.965),
        control2: sourcePoint(467.411, 1387.05)
    )
    path.addCurve(
        to: sourcePoint(279.21, -590.967),
        control1: sourcePoint(398.865, 707.946),
        control2: sourcePoint(279.21, -590.967)
    )
    path.addLine(to: sourcePoint(413.769, -615.48))
    path.closeSubpath()

    var transform = stemAffine
    return path.copy(using: &transform) ?? path
}

func drawStatusBarGlyph(pointSize: CGFloat, color: NSColor) -> NSImage {
    let size = NSSize(width: pointSize, height: pointSize)
    let image = NSImage(size: size)

    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high
    color.setFill()

    let inset: CGFloat = max(0.65, pointSize * 0.055)
    let glyphRect = NSRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
    let fittedRect = fittedReferenceRect(in: glyphRect)
    let transform = drawingTransform(for: fittedRect)
    let context = NSGraphicsContext.current!.cgContext

    var leafTransform = transform
    if let leaf = referenceLeafPath().copy(using: &leafTransform) {
        context.addPath(leaf)
        context.fillPath()
    }

    var stemTransform = transform
    if let stem = referenceStemFillPath().copy(using: &stemTransform) {
        context.addPath(stem)
        context.fillPath()
    }

    return image
}

func composite(glyph: NSImage, canvasSize: Int, background: NSColor) -> NSImage {
    let s = CGFloat(canvasSize)
    let image = NSImage(size: NSSize(width: s, height: s))

    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    background.setFill()
    rect.fill()
    glyph.draw(in: rect)

    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(
            domain: "DockmintStatusBarPreview",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"]
        )
    }
    try data.write(to: url, options: .atomic)
}

try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

for spec in specs {
    let blackGlyph = drawStatusBarGlyph(pointSize: CGFloat(spec.size), color: .black)
    let whiteGlyph = drawStatusBarGlyph(pointSize: CGFloat(spec.size), color: .white)

    let templateURL = outputDir.appendingPathComponent("statusbar_template_\(spec.size).png")
    let lightURL = outputDir.appendingPathComponent("statusbar_on_light_\(spec.size).png")
    let darkURL = outputDir.appendingPathComponent("statusbar_on_dark_\(spec.size).png")

    try writePNG(blackGlyph, to: templateURL)
    try writePNG(composite(glyph: blackGlyph, canvasSize: spec.size, background: .white), to: lightURL)
    try writePNG(composite(glyph: whiteGlyph, canvasSize: spec.size, background: NSColor(calibratedWhite: 0.08, alpha: 1.0)), to: darkURL)

    print("Wrote \(templateURL.path)")
    print("Wrote \(lightURL.path)")
    print("Wrote \(darkURL.path)")
}
