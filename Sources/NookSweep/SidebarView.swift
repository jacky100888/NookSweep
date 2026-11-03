import AppKit
import NookSweepCore
import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: AppIcon.image)
                    .resizable().scaledToFit().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NookSweep").font(.headline)
                    Text("留空間給重要的事").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            List(selection: $model.scope) {
                Section("這部 Mac") {
                    Label("即時狀態", systemImage: "waveform.path.ecg").tag(SidebarScope.status)
                    Label("軟體移除", systemImage: "app.badge").tag(SidebarScope.applications)
                }
                Section("清理範圍") {
                    Label("全部項目", systemImage: "sparkles").tag(SidebarScope.all)
                    ForEach(CleanupCategory.allCases.filter { !$0.isAI }) { category in
                        Label(category.rawValue, systemImage: category.symbol)
                            .tag(SidebarScope.category(category))
                    }
                }
            }
            .listStyle(.sidebar)
            VStack(alignment: .leading, spacing: 12) {
                Label("這部 Mac", systemImage: "internaldrive").font(.subheadline.weight(.medium))
                if let disk = model.disk {
                    ProgressView(value: disk.fraction).tint(.secondary)
                    Text("\(formatBytes(disk.available)) 可用")
                        .font(.subheadline.weight(.medium)).monospacedDigit()
                    Text("容量 \(formatBytes(disk.total)) · 含系統可回收空間")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("無法讀取磁碟容量").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Label("只移到垃圾桶", systemImage: "checkmark.shield")
                    .font(.caption).foregroundStyle(.secondary)
                Text("快取閒置 7 天、記錄檔 30 天後才可清理。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
    }
}
