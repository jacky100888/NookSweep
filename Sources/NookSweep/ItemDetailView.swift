import NookSweepCore
import SwiftUI

struct ItemDetailView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            if let item = model.focusedItem {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: item.category.symbol).font(.system(size: 32)).foregroundStyle(.secondary)
                    Text(item.name).font(.title3.weight(.semibold)).textSelection(.enabled)
                    LabeledContent("大小", value: item.measurementAvailable ? formatBytes(item.bytes) : "無法估算")
                    LabeledContent("檔案數", value: item.fileCount.formatted())
                    LabeledContent("分類", value: item.category.rawValue)
                    if let tool = item.aiToolName { LabeledContent("AI 工具", value: tool) }
                    if let metadata = item.aiMetadata {
                        LabeledContent("資料類型", value: metadata.kind.rawValue)
                        if let note = metadata.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                    }
                    if item.relatedItemCount > 0 {
                        Text("另含 \(item.relatedItemCount) 個關聯目錄／檔案，整理時會一併處理。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("最近修改").font(.caption).foregroundStyle(.secondary)
                        Text(item.measurementAvailable ? item.modified.formatted(date: .abbreviated, time: .shortened) : "未取得")
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("完整路徑").font(.caption).foregroundStyle(.secondary)
                        Text(item.url.path).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Button("在 Finder 顯示", systemImage: "folder") { model.reveal(item) }
                    }
                    Divider()
                    Label(item.isEligible ? (item.category == .aiWorktrees ? "可整理，需先確認工作副本風險" : "符合閒置天數，可移到垃圾桶") : "保留此項目",
                          systemImage: item.isEligible ? "checkmark.shield" : "lock.shield")
                        .font(.subheadline.weight(.medium))
                    Text(item.state.reason ?? (item.category == .aiWorktrees
                        ? "請先停止使用這個工作副本的 AI 工作、編輯器、終端機及建置程序，再確認整理。"
                        : "所有內容至少 \(item.category.minimumDays) 天未修改。清理前請先結束相關應用程式與建置工作，避免快取重新產生。"))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(item.category == .aiWorktrees
                         ? "工作副本含專案檔案，不能當成可重新產生的快取。還原時須一起放回工作區及 Git 管理目錄；手動模式會另建 Git 保留參照，原儲存庫仍須保留。"
                         : item.isAIHistory
                         ? "這是對話紀錄，並非可重建的快取。移除後會失去該段上下文；取回時須放回原路徑。"
                         : "快取可由應用程式重新產生；舊記錄檔移除後會失去當時的診斷資訊。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView("查看項目資訊", systemImage: "info.circle",
                    description: Text("點選列表中的項目，即可查看完整路徑與保留原因。"))
                    .padding(.top, 70)
            }
        }
        .disabled(model.isCleaning)
    }
}
