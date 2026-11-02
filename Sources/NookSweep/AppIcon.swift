import AppKit

@MainActor
enum AppIcon {
    static let image: NSImage = {
        if let url = Bundle.main.url(forResource: "NookSweep", withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        return NSApplication.shared.applicationIconImage
    }()
}
