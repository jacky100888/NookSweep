import AppKit

guard CommandLine.arguments.count == 2 else { fatalError("請提供 iconset 目錄") }
let destination = URL(fileURLWithPath: CommandLine.arguments[1])

func broomHead(small: Bool) -> NSBezierPath {
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 321, y: 418))
    head.line(to: NSPoint(x: 409, y: 418))
    head.curve(to: NSPoint(x: 430, y: 365), controlPoint1: NSPoint(x: 416, y: 397),
               controlPoint2: NSPoint(x: 418, y: 388))
    head.line(to: NSPoint(x: 482, y: 263))
    head.curve(to: NSPoint(x: 467, y: 235), controlPoint1: NSPoint(x: 491, y: 247),
               controlPoint2: NSPoint(x: 482, y: 235))
    head.line(to: NSPoint(x: 263, y: 235))
    head.curve(to: NSPoint(x: 248, y: 263), controlPoint1: NSPoint(x: 248, y: 235),
               controlPoint2: NSPoint(x: 240, y: 247))
    head.line(to: NSPoint(x: 300, y: 365))
    head.curve(to: NSPoint(x: 321, y: 418), controlPoint1: NSPoint(x: 312, y: 388),
               controlPoint2: NSPoint(x: 314, y: 397))
    head.close()
    head.windingRule = .evenOdd
    // 16 px 只留一道寬縫，避免刷毛細節縮成雜點。
    let grooves: [[NSPoint]] = small
        ? [[NSPoint(x: 350, y: 235), NSPoint(x: 355, y: 337),
            NSPoint(x: 375, y: 337), NSPoint(x: 385, y: 235)]]
        : [[NSPoint(x: 315, y: 235), NSPoint(x: 336, y: 350),
            NSPoint(x: 351, y: 350), NSPoint(x: 340, y: 235)],
           [NSPoint(x: 390, y: 235), NSPoint(x: 379, y: 350),
            NSPoint(x: 394, y: 350), NSPoint(x: 415, y: 235)]]
    for points in grooves {
        head.move(to: points[0])
        for point in points.dropFirst() { head.line(to: point) }
        head.close()
    }
    return head
}

func drawIcon(pixels: Int, context: NSGraphicsContext) {
    let scale = CGFloat(pixels) / 1024
    context.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    context.cgContext.scaleBy(x: scale, y: scale)
    let face = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864),
                            xRadius: 190, yRadius: 190)
    face.addClip()
    let gold = NSGradient(starting: NSColor(srgbRed: 0.91, green: 0.64, blue: 0.13, alpha: 1),
                          ending: NSColor(srgbRed: 1, green: 0.83, blue: 0.39, alpha: 1))!
    gold.draw(in: face, angle: 90)
    if pixels >= 64 {
        NSColor.white.withAlphaComponent(0.24).setStroke()
        let rim = NSBezierPath(roundedRect: NSRect(x: 82, y: 82, width: 860, height: 860),
                               xRadius: 188, yRadius: 188)
        rim.lineWidth = 2
        rim.stroke()
    }

    NSGraphicsContext.saveGraphicsState()
    if pixels >= 128 {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.14)
        shadow.shadowOffset = NSSize(width: 0, height: -5 * scale)
        shadow.shadowBlurRadius = 10 * scale
        shadow.set()
    }
    let charcoal = NSColor(srgbRed: 0.14, green: 0.15, blue: 0.13, alpha: 1)
    charcoal.setStroke()
    charcoal.setFill()
    let mark = NSBezierPath()
    mark.move(to: NSPoint(x: 365, y: 405))
    mark.line(to: NSPoint(x: 365, y: 735))
    mark.line(to: NSPoint(x: 710, y: 300))
    mark.line(to: NSPoint(x: 710, y: 735))
    mark.lineWidth = pixels <= 32 ? 112 : 104
    mark.lineCapStyle = .round
    mark.lineJoinStyle = .round
    mark.stroke()
    broomHead(small: pixels <= 16).fill()
    NSGraphicsContext.restoreGraphicsState()

    if pixels >= 64 {
        NSColor(srgbRed: 0.98, green: 0.78, blue: 0.32, alpha: 0.55).setStroke()
        let collar = NSBezierPath()
        collar.move(to: NSPoint(x: 324, y: 399))
        collar.line(to: NSPoint(x: 406, y: 399))
        collar.lineWidth = 5
        collar.lineCapStyle = .round
        collar.stroke()
    }
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
            pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            fatalError("無法建立圖示")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        drawIcon(pixels: pixels, context: context)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("無法輸出圖示")
        }
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
