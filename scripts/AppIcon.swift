import AppKit

guard CommandLine.arguments.count == 2 else { fatalError("請提供 iconset 目錄") }
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let icon = NSImage(size: NSSize(width: 1024, height: 1024))
icon.lockFocus()
NSColor(srgbRed: 0.96, green: 0.75, blue: 0.18, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864),
             xRadius: 190, yRadius: 190).fill()
NSColor(srgbRed: 0.14, green: 0.14, blue: 0.12, alpha: 1).setStroke()
let mark = NSBezierPath()
mark.move(to: NSPoint(x: 310, y: 310))
mark.line(to: NSPoint(x: 310, y: 710))
mark.line(to: NSPoint(x: 714, y: 310))
mark.line(to: NSPoint(x: 714, y: 710))
mark.lineWidth = 104
mark.lineCapStyle = .round
mark.lineJoinStyle = .round
mark.stroke()
icon.unlockFocus()

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
        icon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("無法輸出圖示")
        }
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
