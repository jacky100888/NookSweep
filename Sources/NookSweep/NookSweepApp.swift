import AppKit
import SwiftUI

@main
struct NookSweepApp: App {
    @StateObject private var monitor = StatusModel()
    @StateObject private var updates = AppUpdateModel()
    @StateObject private var help = HelpModel()
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        WindowGroup("NookSweep", id: "main") {
            ContentView(monitor: monitor, updates: updates)
                .onAppear { NSApplication.shared.applicationIconImage = AppIcon.image }
        }
            .defaultSize(width: 1160, height: 740)
            .commands {
                CommandGroup(replacing: .newItem) { }
                CommandGroup(after: .appInfo) {
                    Button("檢查更新…") {
                        help.topic = .updates
                        openWindow(id: "help")
                        updates.checkForUpdates()
                    }
                    .disabled(updates.isChecking)
                }
                CommandGroup(replacing: .help) {
                    Button("NookSweep 使用說明") {
                        openWindow(id: "help")
                    }
                    .keyboardShortcut("/", modifiers: [.command, .shift])
                }
            }
        Window("NookSweep 使用說明", id: "help") {
            HelpView(model: help, updates: updates)
        }
        .defaultSize(width: 860, height: 680)
        MenuBarExtra("NookSweep", systemImage: "waveform.path.ecg") {
            MenuBarStatusView(model: monitor, updates: updates, help: help)
        }
        .menuBarExtraStyle(.window)
    }
}
