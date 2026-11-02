import AppKit
import NookSweepCore
import SwiftUI

struct MenuBarStatusView: View {
    @ObservedObject var model: StatusModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("NookSweep", systemImage: "leaf.fill").font(.headline)
                Spacer()
                Text(model.snapshot?.thermalState ?? "讀取中").font(.caption).foregroundStyle(.secondary)
            }
            Text(model.uptimeText).font(.caption).foregroundStyle(.secondary)
            Grid(horizontalSpacing: 18, verticalSpacing: 15) {
                GridRow {
                    metric("CPU", value: model.snapshot?.cpu?.fraction.formatted(.percent.precision(.fractionLength(0))) ?? "取樣中")
                    metric("記憶體", value: model.snapshot?.memory?.fraction.formatted(.percent.precision(.fractionLength(0))) ?? "讀取中")
                }
                GridRow {
                    StatusSparkline(values: model.cpuHistory, maximum: 1)
                    StatusSparkline(values: model.memoryHistory, maximum: 1, color: .orange)
                }
                GridRow {
                    metric("磁碟可用", value: model.snapshot?.disk.map { formatBytes($0.available) } ?? "讀取中")
                    metric("下載", value: statusRate(model.snapshot?.network?.downloadPerSecond))
                }
            }
            if let battery = model.snapshot?.battery {
                HStack {
                    Label(battery.fraction.formatted(.percent.precision(.fractionLength(0))), systemImage: "battery.100percent")
                    Spacer()
                    Text(battery.isCharging ? "充電中" : battery.isPluggedIn ? "已接電源" : "使用電池")
                        .foregroundStyle(.secondary)
                }.font(.caption)
            }
            Divider()
            HStack {
                Text("高記憶體程序").font(.caption.weight(.medium))
                Spacer()
                Text("駐留記憶體").font(.caption2).foregroundStyle(.secondary)
            }
            StatusProcessList(processes: model.processes, compact: true)
            Divider()
            HStack {
                Button { model.togglePause() } label: {
                    Label(model.isPaused ? "繼續" : "暫停", systemImage: model.isPaused ? "play.fill" : "pause.fill")
                }
                Spacer()
                Button { model.refresh() } label: { Label("更新", systemImage: "arrow.clockwise") }
                    .disabled(model.isRefreshing)
            }
            Text(model.isPaused ? "監測已暫停" : "每 2 秒更新 · 全部資料留在本機")
                .font(.caption2).foregroundStyle(.secondary)
            Button("開啟主視窗", systemImage: "macwindow") {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }.frame(maxWidth: .infinity)
            Button("結束 NookSweep") { NSApplication.shared.terminate(nil) }
                .font(.caption).frame(maxWidth: .infinity)
        }.padding(20).frame(width: 330)
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
