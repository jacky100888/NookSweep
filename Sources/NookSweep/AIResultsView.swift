import AppKit
import NookSweepCore
import SwiftUI

struct AIResultsView: View {
    @ObservedObject var model: AppModel

    private var inventory: [CleanupItem] {
        model.items.filter { $0.category.isAI && (model.scope?.category == nil || $0.category == model.scope?.category) }
    }
    private var visible: [CleanupItem] { model.visibleItems.filter { $0.category.isAI } }
    private var selectableCount: Int { visible.filter(\.isEligible).count }
    private var tools: [String] {
        Set(visible.map { $0.aiToolID ?? "unknown" }).sorted {
            toolName($0).localizedStandardCompare(toolName($1)) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("目前範圍已偵測 \(summary(inventory))")
                    .font(.subheadline).monospacedDigit()
                Text("統計包含目前範圍的全部項目，搜尋與篩選僅影響列表。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    TextField("搜尋 AI 資料路徑", text: $model.query)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("搜尋 AI 資料路徑")
                    Toggle("只顯示可整理", isOn: $model.eligibleOnly)
                        .toggleStyle(.checkbox).font(.caption).fixedSize()
                }
                HStack {
                    Button("全選可整理 · \(selectableCount.formatted()) 項", systemImage: "checklist") {
                        model.selectVisible()
                    }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(selectableCount == 0)
                    .help("選取符合目前搜尋與分類的全部可整理項目，包含收合群組內的項目（⌘⇧A）")
                    Button("取消全選") { model.selected.removeAll() }
                        .disabled(model.selected.isEmpty)
                    Spacer()
                    Text("顯示 \(visible.count.formatted()) 項 · 已選 \(model.selectedItems.count.formatted()) 項")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.scope?.category == .aiHistory, !model.includeAIHistory {
                    Text("先開啟左側「允許整理舊對話／歷史」，即可全選可整理的舊對話。索引管理或執行中的資料仍會保留。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.scope == .aiOverview || model.scope?.category == .aiWorktrees {
                    Toggle("手動整理工作副本（包含近期、未提交或未合併內容）", isOn: Binding(
                        get: { model.manualWorktreeReview }, set: { model.setManualWorktreeReview($0) }))
                        .toggleStyle(.checkbox).font(.caption)
                    Text(model.manualWorktreeReview
                        ? "先停止使用要整理的工作副本，再查看各項風險。會保留 Git 提交參照；鎖定、Git 操作未完成或結構不明的項目仍保留。"
                        : "預設只整理乾淨且已合併的工作副本；含變更或未合併的項目可開啟手動整理後預覽。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            Divider()
            if visible.isEmpty {
                ContentUnavailableView("目前沒有符合條件的 AI 資料", systemImage: "sparkles",
                    description: Text(inventory.isEmpty
                        ? "目前範圍沒有偵測到已知格式的 AI 資料。"
                        : "可清除搜尋文字，或取消「只顯示可整理」查看保留原因。"))
            } else {
                List(selection: $model.focusedID) {
                    ForEach(tools, id: \.self) { tool in
                        Section {
                            ForEach(AIDataKind.allCases, id: \.self) { kind in
                                let shown = visible.filter { toolID($0) == tool && dataKind($0) == kind }
                                if !shown.isEmpty {
                                    DisclosureGroup {
                                        ForEach(shown) { item in itemRow(item).tag(item.id) }
                                    } label: {
                                        groupLabel(kindTitle(kind), items: inventory.filter {
                                            toolID($0) == tool && dataKind($0) == kind
                                        }, shown: shown.count)
                                    }
                                }
                            }
                        } header: {
                            groupLabel(toolName(tool), items: inventory.filter { toolID($0) == tool },
                                       shown: visible.filter { toolID($0) == tool }.count)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .disabled(model.isCleaning)
    }

    private func groupLabel(_ title: String, items: [CleanupItem], shown: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).fontWeight(.semibold)
                Spacer(minLength: 8)
                if shown != items.count {
                    Text("顯示 \(shown.formatted()) 項").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(summary(items)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private func itemRow(_ item: CleanupItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("選取 \(item.name)", isOn: Binding(
                get: { model.selected.contains(item.id) },
                set: { selected in
                    if selected { model.selected.insert(item.id) }
                    else { model.selected.remove(item.id) }
                }))
                .labelsHidden().toggleStyle(.checkbox).padding(.top, 3)
                .disabled(!item.isEligible)
                .help(item.state.reason ?? "選取此項目")
            Button {
                model.focusedID = item.id
                model.showDetails = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.name).fontWeight(.medium).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(item.measurementAvailable ? formatBytes(item.bytes) : "無法估算").monospacedDigit().fixedSize()
                    }
                    Text("\(item.fileCount.formatted()) 個檔案 · \(item.state.reason ?? "可整理")")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    if let note = item.aiMetadata?.note {
                        Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Text(item.url.path).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityHint("查看完整路徑與保留原因")
        }
        .padding(.vertical, 5)
        .contextMenu {
            Button("查看項目資訊", systemImage: "info.circle") {
                model.focusedID = item.id
                model.showDetails = true
            }
            Button("在 Finder 顯示", systemImage: "folder") { model.reveal(item) }
            Button("複製路徑", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
        }
    }

    private func summary(_ items: [CleanupItem]) -> String {
        let eligible = items.filter(\.isEligible).count
        let unknown = items.filter { !$0.measurementAvailable }.count
        return "\(formatBytes(items.reduce(0) { $0 + $1.bytes })) · \(items.count.formatted()) 項 · 可整理 \(eligible.formatted())／保留 \((items.count - eligible).formatted())" +
            (unknown == 0 ? "" : " · \(unknown) 項無法估算")
    }

    private func toolID(_ item: CleanupItem) -> String { item.aiToolID ?? "unknown" }

    private func toolName(_ id: String) -> String {
        inventory.first { toolID($0) == id }?.aiToolName ?? "其他 AI 工具"
    }

    private func dataKind(_ item: CleanupItem) -> AIDataKind {
        if let kind = item.aiMetadata?.kind { return kind }
        switch item.category {
        case .aiHistory: return .conversation
        case .aiVersions: return .oldVersion
        case .aiWorktrees: return .worktree
        default: return .cache
        }
    }

    private func kindTitle(_ kind: AIDataKind) -> String {
        switch kind {
        case .cache: "快取與暫存"
        case .oldVersion: "工具版本"
        case .conversation: "對話紀錄"
        case .localHistory: "本機歷史"
        case .worktree: "工作副本"
        }
    }
}
