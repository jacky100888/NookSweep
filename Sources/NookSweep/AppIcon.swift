import AppKit

@MainActor
enum AppIcon {
    static let menuBarImage: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let mark = NSBezierPath()
            mark.move(to: NSPoint(x: 5, y: 6))
            mark.line(to: NSPoint(x: 5, y: 15))
            mark.line(to: NSPoint(x: 14, y: 3.8))
            mark.line(to: NSPoint(x: 14, y: 15))
            mark.lineWidth = 2.7
            mark.lineCapStyle = .round
            mark.lineJoinStyle = .round
            mark.stroke()
            let broom = NSBezierPath()
            broom.move(to: NSPoint(x: 3.8, y: 6.2))
            broom.line(to: NSPoint(x: 6.2, y: 6.2))
            broom.line(to: NSPoint(x: 7.7, y: 2))
            broom.line(to: NSPoint(x: 2.3, y: 2))
            broom.close()
            broom.windingRule = .evenOdd
            broom.move(to: NSPoint(x: 4.4, y: 2))
            broom.line(to: NSPoint(x: 4.9, y: 4.8))
            broom.line(to: NSPoint(x: 5.2, y: 4.8))
            broom.line(to: NSPoint(x: 5.6, y: 2))
            broom.close()
            broom.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "NookSweep"
        return image
    }()

    static let image: NSImage = {
        if let url = Bundle.main.url(forResource: "NookSweep", withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        return NSApplication.shared.applicationIconImage
    }()
}
