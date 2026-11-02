import AppKit
import SwiftUI

@main
struct NookSweepApp: App {
    @StateObject private var monitor = StatusModel()
    var body: some Scene {
        WindowGroup("NookSweep", id: "main") { ContentView(monitor: monitor) }
            .defaultSize(width: 1160, height: 740)
            .commands {
                CommandGroup(replacing: .newItem) { }
                CommandGroup(replacing: .help) {
                    Button("NookSweep 使用說明") {
                        if let url = Bundle.main.url(forResource: "README", withExtension: "md") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        MenuBarExtra {
            MenuBarStatusView(model: monitor)
        } label: {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().scaledToFit().frame(width: 18, height: 18)
                .accessibilityLabel("NookSweep 狀態")
        }
        .menuBarExtraStyle(.window)
    }
}
