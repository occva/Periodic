import AppKit

let canvas = NSSize(width: 800, height: 400)
let image = NSImage(size: canvas)

func drawCentered(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let text = NSAttributedString(string: text, attributes: [
        .font: font,
        .foregroundColor: color
    ])
    let size = text.size()
    text.draw(at: NSPoint(x: (canvas.width - size.width) / 2, y: y))
}

for scale in [1, 2] {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas.width) * scale,
        pixelsHigh: Int(canvas.height) * scale,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "PeriodicPackaging", code: 1)
    }
    bitmap.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

    let bounds = NSRect(origin: .zero, size: canvas)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.90, green: 0.94, blue: 0.98, alpha: 1),
        NSColor(calibratedWhite: 0.98, alpha: 1)
    ])?.draw(in: bounds, angle: 90)

    for (color, center) in [
        (NSColor(calibratedRed: 0.92, green: 0.79, blue: 0.89, alpha: 0.35),
         NSPoint(x: 0, y: 400)),
        (NSColor(calibratedRed: 0.98, green: 0.89, blue: 0.66, alpha: 0.3),
         NSPoint(x: 740, y: 420))
    ] {
        NSGradient(starting: color, ending: color.withAlphaComponent(0))?.draw(
            fromCenter: center, radius: 0,
            toCenter: center, radius: 300,
            options: .drawsBeforeStartingLocation
        )
    }

    drawCentered(
        "将 Periodic 拖入应用程序，即可安装",
        y: 310,
        font: .systemFont(ofSize: 23, weight: .medium),
        color: NSColor(calibratedWhite: 0.16, alpha: 1)
    )
    drawCentered(
        "To install, drag Periodic to Applications",
        y: 286,
        font: .systemFont(ofSize: 14),
        color: NSColor(calibratedWhite: 0.43, alpha: 1)
    )

    for (offset, alpha) in [(-18.0, 0.18), (0.0, 0.40), (18.0, 0.85)] {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 394 + offset, y: 158))
        path.line(to: NSPoint(x: 404 + offset, y: 172))
        path.line(to: NSPoint(x: 394 + offset, y: 186))
        path.lineWidth = 4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor(calibratedWhite: 0.1, alpha: alpha).setStroke()
        path.stroke()
    }

    NSGraphicsContext.restoreGraphicsState()
    image.addRepresentation(bitmap)
}

guard CommandLine.arguments.count == 2, let data = image.tiffRepresentation else {
    throw NSError(domain: "PeriodicPackaging", code: 2)
}
try data.write(to: URL(filePath: CommandLine.arguments[1]), options: .atomic)
