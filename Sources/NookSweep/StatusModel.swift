import Foundation
import NookSweepCore
import SwiftUI

@MainActor
final class StatusModel: ObservableObject {
    @Published private(set) var snapshot: SystemSnapshot?
    @Published private(set) var isPaused = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryHistory: [Double] = []
    @Published private(set) var downloadHistory: [Double] = []
    @Published private(set) var uploadHistory: [Double] = []
    @Published var showPerCore = true
    @Published var processSortByName = false
    private let sampler = SystemSampler()
    private var samplingTask: Task<Void, Never>?

    init() { start() }

    deinit { samplingTask?.cancel() }

    func start() {
        guard samplingTask == nil else { return }
        isPaused = false
        samplingTask = Task { [weak self] in
            guard let sampler = self?.sampler else { return }
            await sampler.reset()
            while !Task.isCancelled {
                await self?.sample(manual: false)
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
            }
        }
    }

    func pause() {
        isPaused = true
        samplingTask?.cancel()
        samplingTask = nil
    }

    func togglePause() { isPaused ? start() : pause() }

    func refresh() { Task { await sample(manual: true) } }

    var processes: [SystemProcessReading] {
        let values = snapshot?.processes ?? []
        return processSortByName ? values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } : values
    }

    var uptimeText: String {
        guard let uptime = snapshot?.uptime else { return "讀取開機時間…" }
        let minutes = Int(uptime / 60)
        let days = minutes / 1440
        let hours = minutes % 1440 / 60
        return days > 0 ? "已開機 \(days) 天 \(hours) 小時" : "已開機 \(hours) 小時 \(minutes % 60) 分鐘"
    }

    private func sample(manual: Bool) async {
        guard !isRefreshing, manual || !isPaused else { return }
        isRefreshing = true
        let value = await sampler.sample()
        defer { isRefreshing = false }
        guard manual || !isPaused else { return }
        snapshot = value
        if let cpu = value.cpu { cpuHistory = Array((cpuHistory + [cpu.fraction]).suffix(60)) }
        if let memory = value.memory { memoryHistory = Array((memoryHistory + [memory.fraction]).suffix(60)) }
        if let download = value.network?.downloadPerSecond {
            downloadHistory = Array((downloadHistory + [download]).suffix(60))
        }
        if let upload = value.network?.uploadPerSecond {
            uploadHistory = Array((uploadHistory + [upload]).suffix(60))
        }
    }
}

func statusBytes(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(min(UInt64(Int64.max), bytes)), countStyle: .memory)
}

func statusRate(_ bytes: Double?) -> String {
    guard let bytes, bytes.isFinite, bytes >= 0 else { return "取樣中" }
    return formatBytes(Int64(min(Double(Int64.max - 1024), bytes))) + "/s"
}
