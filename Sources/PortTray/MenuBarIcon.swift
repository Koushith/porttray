import AppKit

/// A custom monochrome menu bar glyph: a panel with three port holes.
/// Rendered as a template image so it tints correctly in light/dark menu bars.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let outer = NSRect(x: 1.5, y: 4, width: 15, height: 10)
            let panel = NSBezierPath(roundedRect: outer, xRadius: 2.5, yRadius: 2.5)
            panel.lineWidth = 1.4
            NSColor.black.setStroke()
            panel.stroke()

            NSColor.black.setFill()
            let r: CGFloat = 1.35
            for i in 0..<3 {
                let cx = outer.minX + 4 + CGFloat(i) * 3.6
                let dot = NSBezierPath(ovalIn: NSRect(x: cx - r, y: outer.midY - r,
                                                      width: r * 2, height: r * 2))
                dot.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}
