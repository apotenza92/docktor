import AppKit

enum StatusBarIcon {
    static func image(pointSize: CGFloat = 18) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size)
        image.isTemplate = true

        image.lockFocus()
        defer { image.unlockFocus() }

        // Square-forward, unique glyph tuned for menu bar legibility.
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let inset: CGFloat = 1.75
        let side = min(size.width, size.height) - inset * 2
        let originX = floor((size.width - side) * 0.5)
        let originY = floor((size.height - side) * 0.5)

        let outer = NSRect(x: originX, y: originY, width: side, height: side)
        let lineWidth: CGFloat = max(1.45, round(side * 0.10))
        let outerPath = NSBezierPath(roundedRect: outer, xRadius: side * 0.16, yRadius: side * 0.16)
        outerPath.lineWidth = lineWidth
        outerPath.stroke()

        let module = round(side * 0.25)
        let margin = round(side * 0.17)
        let topLeft = NSRect(x: outer.minX + margin,
                             y: outer.maxY - margin - module,
                             width: module,
                             height: module)
        let bottomRight = NSRect(x: outer.maxX - margin - module,
                                 y: outer.minY + margin,
                                 width: module,
                                 height: module)

        let cornerRadius = max(0.9, module * 0.18)
        NSBezierPath(roundedRect: topLeft, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        NSBezierPath(roundedRect: bottomRight, xRadius: cornerRadius, yRadius: cornerRadius).fill()

        let bridge = NSBezierPath()
        bridge.lineWidth = max(1.3, round(side * 0.09))
        bridge.lineCapStyle = .round
        bridge.move(to: NSPoint(x: topLeft.maxX - module * 0.12, y: topLeft.minY + module * 0.12))
        bridge.line(to: NSPoint(x: bottomRight.minX + module * 0.12, y: bottomRight.maxY - module * 0.12))
        bridge.stroke()

        return image
    }
}
