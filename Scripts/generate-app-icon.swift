import AppKit

/// Renders the shared llama mark above a server stack and exports macOS icon representations.
@main
struct AppIconGenerator {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw failure("Usage: generate-app-icon <output-directory>")
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let iconset = directory.appendingPathComponent("AppIcon.iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let suffix = scale == 2 ? "@2x" : ""
                let data = try render(side: size * scale)
                let name = "icon_\(size)x\(size)\(suffix).png"
                try data.write(to: iconset.appendingPathComponent(name), options: .atomic)
            }
        }
        try render(side: 1024).write(to: directory.appendingPathComponent("AppIcon.png"), options: .atomic)
    }

    @MainActor
    private static func render(side: Int) throws -> Data {
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let graphics = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            throw failure("Could not allocate the \(side)-pixel icon.")
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: CGFloat(side) / 1024, y: -CGFloat(side) / 1024)
        context.setAllowsAntialiasing(true)
        try drawTile(context)
        try drawServer(y: 640, context: context)
        try drawServer(y: 776, context: context)
        drawLlama(context)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw failure("Could not encode the \(side)-pixel icon.")
        }
        return data
    }

    private static func drawTile(_ context: CGContext) throws {
        let tile = NSBezierPath(
            roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
            xRadius: 192, yRadius: 192)
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: 10), blur: 22,
            color: NSColor.black.withAlphaComponent(0.22).cgColor)
        color(23, 43, 64).setFill()
        tile.fill()
        context.restoreGState()
        context.saveGState()
        tile.addClip()
        try gradient(
            context, top: color(36, 70, 97), bottom: color(11, 27, 43),
            start: CGPoint(x: 512, y: 64), end: CGPoint(x: 512, y: 960))
        context.restoreGState()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        tile.lineWidth = 2
        tile.stroke()
    }

    private static func drawServer(y: CGFloat, context: CGContext) throws {
        let shell = NSBezierPath(
            roundedRect: NSRect(x: 210, y: y, width: 604, height: 112),
            xRadius: 26, yRadius: 26)
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: 7), blur: 10,
            color: NSColor.black.withAlphaComponent(0.25).cgColor)
        color(46, 74, 94).setFill()
        shell.fill()
        context.restoreGState()
        context.saveGState()
        shell.addClip()
        try gradient(
            context, top: color(82, 118, 143), bottom: color(44, 69, 88),
            start: CGPoint(x: 512, y: y), end: CGPoint(x: 512, y: y + 112))
        context.restoreGState()
        NSColor.white.withAlphaComponent(0.22).setStroke()
        shell.lineWidth = 2
        shell.stroke()
        color(16, 35, 51).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 254, y: y + 43, width: 338, height: 26),
            xRadius: 13, yRadius: 13
        ).fill()
        color(132, 235, 193).setFill()
        NSBezierPath(ovalIn: NSRect(x: 736, y: y + 42, width: 28, height: 28)).fill()
    }

    @MainActor
    private static func drawLlama(_ context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: 210, y: 100)
        context.scaleBy(x: 24, y: 24)
        color(255, 247, 231).setFill()
        LlamaPerchIcon.silhouette().fill()
    }

    private static func gradient(
        _ context: CGContext, top: NSColor, bottom: NSColor,
        start: CGPoint, end: CGPoint
    ) throws {
        // The fixed two-stop palette does not require an external color profile or asset.
        let colors = [top.cgColor, bottom.cgColor] as CFArray
        guard
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                locations: [0, 1])
        else {
            throw failure("Could not allocate the icon gradient.")
        }
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
    }

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }

    private static func failure(_ message: String) -> NSError {
        NSError(
            domain: "AppIconGenerator", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message])
    }
}
