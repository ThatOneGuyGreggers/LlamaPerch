import AppKit

/// A vector template preserves a sharp silhouette at either menu bar display scale.
/// macOS supplies its color for light, dark, and selected menu bar appearances.
@MainActor
enum LlamaMenuIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 20), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            defer { context.restoreGState() }
            context.scaleBy(x: 22 / 24, y: 20 / 24)
            NSColor.black.setFill()
            silhouette().fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Llama"
        return image
    }()

    static func silhouette() -> NSBezierPath {
        // Long ears, a raised neck, and a compact woolly body carry the shape at 20 points.
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 3.5, y: 11.5))
        path.curve(
            to: NSPoint(x: 2, y: 8.5), controlPoint1: NSPoint(x: 1, y: 11), controlPoint2: NSPoint(x: 1, y: 9)
        )
        path.curve(
            to: NSPoint(x: 5, y: 11), controlPoint1: NSPoint(x: 3, y: 9),
            controlPoint2: NSPoint(x: 3, y: 10.5))
        path.line(to: NSPoint(x: 12.5, y: 11))
        path.curve(
            to: NSPoint(x: 14, y: 8), controlPoint1: NSPoint(x: 14, y: 11),
            controlPoint2: NSPoint(x: 14, y: 9.5))
        path.line(to: NSPoint(x: 14, y: 5))
        path.line(to: NSPoint(x: 13.3, y: 1.5))
        path.curve(
            to: NSPoint(x: 14.7, y: 1.1), controlPoint1: NSPoint(x: 13.1, y: 0.5),
            controlPoint2: NSPoint(x: 14.2, y: 0.2))
        path.line(to: NSPoint(x: 16, y: 4))
        path.line(to: NSPoint(x: 17, y: 1))
        path.curve(
            to: NSPoint(x: 18.4, y: 1.4), controlPoint1: NSPoint(x: 17.4, y: 0.2),
            controlPoint2: NSPoint(x: 18.5, y: 0.5))
        path.line(to: NSPoint(x: 18, y: 4.6))
        path.curve(
            to: NSPoint(x: 20, y: 6), controlPoint1: NSPoint(x: 19.2, y: 4.6),
            controlPoint2: NSPoint(x: 19.8, y: 5.1))
        path.line(to: NSPoint(x: 22, y: 6.6))
        path.curve(
            to: NSPoint(x: 22, y: 9), controlPoint1: NSPoint(x: 23.5, y: 7),
            controlPoint2: NSPoint(x: 23.2, y: 8.8))
        path.line(to: NSPoint(x: 19, y: 9.2))
        path.line(to: NSPoint(x: 18.5, y: 15))
        path.curve(
            to: NSPoint(x: 17, y: 18), controlPoint1: NSPoint(x: 18.5, y: 16.5),
            controlPoint2: NSPoint(x: 18, y: 17.6))
        path.line(to: NSPoint(x: 17, y: 22.5))
        path.line(to: NSPoint(x: 14.7, y: 22.5))
        path.line(to: NSPoint(x: 14.4, y: 18.5))
        path.line(to: NSPoint(x: 7, y: 18.5))
        path.line(to: NSPoint(x: 6.5, y: 22.5))
        path.line(to: NSPoint(x: 4.2, y: 22.5))
        path.line(to: NSPoint(x: 4, y: 17))
        path.curve(
            to: NSPoint(x: 3.5, y: 11.5), controlPoint1: NSPoint(x: 2.5, y: 16),
            controlPoint2: NSPoint(x: 2.3, y: 13))
        path.close()
        // A single cutout adds expression without fragile strokes or fur detail.
        path.appendOval(in: NSRect(x: 18.2, y: 6.3, width: 1.1, height: 1.1))
        path.windingRule = .evenOdd
        return path
    }
}
