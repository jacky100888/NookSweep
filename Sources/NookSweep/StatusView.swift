import NookSweepCore
import SwiftUI

struct StatusView: View {
    @ObservedObject var model: StatusModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("系統狀態").font(.system(size: 25, weight: .semibold))
                        Text("\(model.snapshot?.thermalState ?? "讀取系統資訊…") · \(model.uptimeText)")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.togglePause() } label: {
                        Label(model.isPaused ? "繼續監測" : "暫停監測",
                              systemImage: model.isPaused ? "play.fill" : "pause.fill")
                    }
                    Button { model.refresh() } label: { Label("重新整理", systemImage: "arrow.clockwise") }
                        .disabled(model.isRefreshing)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 16) {
                    cpu
                    memory
                    disk
                    network
                }
                HStack(alignment: .top, spacing: 20) {
                    battery
                    VStack(alignment: .leading, spacing: 10) {
                        Label("系統資訊", systemImage: "desktopcomputer").font(.headline)
                        Text(ProcessInfo.processInfo.operatingSystemVersionString).font(.subheadline)
                        Text("\(ProcessInfo.processInfo.processorCount) 個邏輯核心 · \(model.uptimeText)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("每 2 秒取樣，曲線保留最近 60 次記錄。記憶體為活躍、核心與壓縮頁面估算。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        StatusProcessList(processes: model.processes)
                        Text("駐留記憶體可能包含共用頁面；系統限制存取的程序不會列出。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(6)
                } label: {
                    HStack {
                        Label("高記憶體程序", systemImage: "list.bullet.rectangle")
                        Spacer()
                        Toggle("依名稱排序", isOn: $model.processSortByName).toggleStyle(.checkbox).font(.caption)
                    }
                }
                HStack {
                    Label(model.isPaused ? "監測已暫停" : "即時監測中",
                          systemImage: model.isPaused ? "pause.circle" : "waveform.path")
                    Spacer()
                    if let date = model.snapshot?.sampledAt {
                        Text("更新於 \(date.formatted(date: .omitted, time: .standard))")
                    }
                }.font(.caption).foregroundStyle(.secondary)
                if let missing = model.snapshot?.unavailable, !missing.isEmpty {
                    Label("目前無法讀取：\(missing.joined(separator: "、"))", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(28)
        }
    }

    private var cpu: some View {
        StatusMetric(title: "CPU", symbol: "cpu") {
            HStack {
                Text(model.snapshot?.cpu?.fraction.formatted(.percent.precision(.fractionLength(0))) ?? "取樣中")
                    .font(.title.weight(.semibold)).monospacedDigit()
                Spacer()
                Toggle("各核心", isOn: $model.showPerCore).toggleStyle(.checkbox).font(.caption)
            }
            if model.showPerCore, let cores = model.snapshot?.cpu?.cores {
                StatusCoreBars(cores: cores)
            } else { StatusSparkline(values: model.cpuHistory, maximum: 1) }
            Text("\(ProcessInfo.processInfo.processorCount) 個核心 · \(model.snapshot?.thermalState ?? "讀取中")")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var memory: some View {
        StatusMetric(title: "記憶體", symbol: "memorychip") {
            HStack {
                Text(model.snapshot?.memory?.fraction.formatted(.percent.precision(.fractionLength(0))) ?? "讀取中")
                    .font(.title.weight(.semibold)).monospacedDigit()
                Spacer()
                Text(model.snapshot?.memory?.pressure.rawValue ?? "")
                    .font(.caption).foregroundStyle(model.snapshot?.memory?.pressure == .normal ? .secondary : Color.orange)
            }
            StatusSparkline(values: model.memoryHistory, maximum: 1, color: .orange)
            Text(model.snapshot?.memory.map { "\(statusBytes($0.used)) / \(statusBytes($0.total))" } ?? "無法取得記憶體資料")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var disk: some View {
        StatusMetric(title: "可用空間", symbol: "internaldrive") {
            Text(model.snapshot?.disk.map { formatBytes($0.available) } ?? "讀取中")
                .font(.title.weight(.semibold)).monospacedDigit()
            ProgressView(value: model.snapshot?.disk?.fraction ?? 0).tint(.blue).frame(height: 30)
            Text(model.snapshot?.disk.map { "總容量 \(formatBytes($0.total)) · 含系統可回收空間" } ?? "無法取得磁碟資料")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var network: some View {
        StatusMetric(title: "網路", symbol: "network") {
            Text(statusRate(model.snapshot?.network?.downloadPerSecond))
                .font(.title.weight(.semibold)).monospacedDigit()
            StatusSparkline(values: model.downloadHistory, color: .mint)
            Text("下載 ↓ · 上傳 ↑ \(statusRate(model.snapshot?.network?.uploadPerSecond)) · \(model.snapshot?.network?.interface ?? "未連線")")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var battery: some View {
        StatusMetric(title: "電池", symbol: "battery.100percent") {
            if let battery = model.snapshot?.battery {
                HStack {
                    Text(battery.fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.title.weight(.semibold)).monospacedDigit()
                    Spacer()
                    Text(battery.isCharging ? "充電中" : battery.isPluggedIn ? "已接電源" : "使用電池")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ProgressView(value: battery.fraction).tint(.green)
            } else { Text("未偵測到內建電池").foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity)
    }
}
