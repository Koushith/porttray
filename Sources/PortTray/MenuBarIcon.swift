import AppKit

/// Menu bar glyph from the redesign: a socket panel with a port opening.
/// Rendered as a template image so it tints correctly in light/dark menu bars.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.black.setStroke()

            let body = NSBezierPath(roundedRect: NSRect(x: 2, y: 3, width: 12, height: 10),
                                    xRadius: 2, yRadius: 2)
            body.lineWidth = 1.5
            body.lineJoinStyle = .round
            body.stroke()

            let port = NSBezierPath()
            port.move(to: NSPoint(x: 5.5, y: 13))
            port.line(to: NSPoint(x: 5.5, y: 9.5))
            port.line(to: NSPoint(x: 10.5, y: 9.5))
            port.line(to: NSPoint(x: 10.5, y: 13))
            port.move(to: NSPoint(x: 7, y: 9.5))
            port.line(to: NSPoint(x: 7, y: 8))
            port.line(to: NSPoint(x: 9, y: 8))
            port.line(to: NSPoint(x: 9, y: 9.5))
            port.lineWidth = 1.5
            port.lineJoinStyle = .round
            port.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
