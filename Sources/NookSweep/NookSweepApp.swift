import AppKit
import SwiftUI

@main
struct NookSweepApp: App {
    @StateObject private var monitor = StatusModel()
    var body: some Scene {
        WindowGroup("NookSweep", id: "main") {
            ContentView(monitor: monitor)
                .onAppear { NSApplication.shared.applicationIconImage = AppIcon.image }
        }
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
        MenuBarExtra("NookSweep", systemImage: "waveform.path.ecg") {
            MenuBarStatusView(model: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}
