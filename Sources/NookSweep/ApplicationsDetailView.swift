import AppKit
import NookSweepCore
import SwiftUI

struct ApplicationsDetailView: View {
    @ObservedObject var model: ApplicationsModel

    var body: some View {
        ScrollView {
            if let app = model.selectedApplication {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                            .resizable().frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(app.name).font(.title3.weight(.semibold))
                            Text(app.version).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("App 大小", value: formatBytes(app.bytes))
                    LabeledContent("檔案數", value: app.fileCount.formatted())
                    Text(app.bundleID).font(.caption).textSelection(.enabled)
                    Text(app.url.path).font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("在 Finder 顯示 App", systemImage: "folder") { model.reveal(app.url) }
                    if let reason = app.blockedReason {
                        Label(reason, systemImage: "lock.shield").font(.callout)
                    }
                    Divider()
                    Text("相關資料（選填）").font(.headline)
                    Text("可能包含設定、登入狀態與使用者內容。請確認已備份後再勾選；全部不選也可以只移除 App。")
                        .font(.callout).foregroundStyle(.secondary)
                    if model.isInspecting {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("正在檢查精確對應的資料…").font(.caption)
                        }
                    } else if model.relatedItems.isEmpty {
                        Text("未找到可精確對應的相關資料。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(model.relatedItems) { item in relatedRow(item, app: app) }
                    }
                    Divider()
                    Button("將 App 移到垃圾桶", systemImage: "trash", role: .destructive) {
                        model.showConfirmation = true
                    }
                    .disabled(!model.canRemove)
                    if model.isRemoving {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("正在逐項移到垃圾桶…").font(.caption)
                        }
                    }
                    Text("執行中的 App 需先自行結束。權限不足時會提供 Finder 處理與 App 管理設定指引；垃圾桶可供復原。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView("預覽軟體與相關資料", systemImage: "app.badge.checkmark",
                    description: Text("選取 App 以查看移除範圍。相關資料預設全部保留。"))
                    .padding(.top, 55)
            }
        }
    }

    private func relatedRow(_ item: ApplicationRelatedItem, app: ApplicationRecord) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                Toggle(isOn: Binding(
                    get: { model.selectedRelatedIDs.contains(item.id) },
                    set: { selected in
                        if selected { model.selectedRelatedIDs.insert(item.id) }
                        else { model.selectedRelatedIDs.remove(item.id) }
                    })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.url.lastPathComponent).font(.callout).lineLimit(2)
                        Text("\(item.category) · \(formatBytes(item.bytes))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(!item.isSelectable || !app.isRemovable || model.busy)
                Spacer(minLength: 0)
                Button { model.reveal(item.url) } label: {
                    Image(systemName: "folder")
                }.buttonStyle(.borderless).help("在 Finder 顯示此資料")
            }
            Text(item.url.path).font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let reason = item.blockedReason {
                Label(reason, systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}
