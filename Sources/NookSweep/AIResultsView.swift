import AppKit
import NookSweepCore
import SwiftUI

struct AIResultsView: View {
    @ObservedObject var model: AppModel

    private var inventory: [CleanupItem] {
        model.scopedItems
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
                Picker("資料類型", selection: $model.aiCategory) {
                    Text("全部資料").tag(CleanupCategory?.none)
                    Text("快取與暫存").tag(CleanupCategory?.some(.aiCaches))
                    Text("對話與本機歷史").tag(CleanupCategory?.some(.aiHistory))
                    Text("舊版本").tag(CleanupCategory?.some(.aiVersions))
                    Text("工作副本").tag(CleanupCategory?.some(.aiWorktrees))
                }
                .fixedSize().accessibilityLabel("AI 資料類型")
                if model.aiCategory == nil || model.aiCategory == .aiHistory {
                    Toggle("允許整理舊對話／歷史", isOn: Binding(
                        get: { model.includeAIHistory }, set: { model.setIncludeAIHistory($0) }
                    ))
                    .toggleStyle(.checkbox).font(.caption).disabled(model.busy)
                    Text(model.includeAIHistory
                        ? "僅能整理至少閒置 30 天的已知歷史，操作前另行確認。"
                        : "對話仍會列出，預設保留；索引管理或執行中的資料也會保留。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    TextField("搜尋 AI 資料路徑", text: $model.query)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("搜尋 AI 資料路徑")
                    Toggle("只顯示可整理", isOn: $model.eligibleOnly)
                        .toggleStyle(.checkbox).font(.caption).fixedSize()
                }
                if model.aiCategory == .aiHistory {
                    HStack(spacing: 12) {
                        Picker("日期篩選", selection: $model.historyAgeDays) {
                            Text("全部日期").tag(0)
                            Text("15 天以前").tag(15)
                            Text("30 天以前").tag(30)
                            Text("60 天以前").tag(60)
                        }
                        .fixedSize().accessibilityLabel("舊對話日期篩選")
                        Text("依最近修改時間篩選，已選項目保留。")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
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
                if model.aiCategory == nil || model.aiCategory == .aiWorktrees {
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
                        : model.aiCategory == .aiHistory
                            ? "可調整日期篩選、清除搜尋文字，或取消「只顯示可整理」查看保留原因。"
                            : "可清除搜尋文字，或取消「只顯示可整理」查看保留原因。"))
            } else {
                List(selection: $model.focusedID) {
                    columnHeaders.listRowSeparator(.hidden)
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

    private var columnHeaders: some View {
        HStack(spacing: 10) {
            Text("群組內排序").foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(action: model.sortByDate) {
                HStack(spacing: 4) {
                    Text("最近修改")
                    Image(systemName: model.dateSortOrder.map { $0 == .forward ? "chevron.up" : "chevron.down" }
                        ?? "arrow.up.arrow.down")
                }.frame(width: 112, height: 24, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("依最近修改排序")
            .accessibilityValue(model.dateSortOrder == nil ? "未使用日期排序" : model.sortDescription)
            .help("在各工具與類型群組內切換由舊到新／由新到舊")
            Button(action: model.sortBySize) {
                HStack(spacing: 4) {
                    Text("大小")
                    Image(systemName: model.sortOrder.first?.keyPath == \CleanupItem.bytes
                        ? (model.sortOrder.first?.order == .forward ? "chevron.up" : "chevron.down")
                        : "arrow.up.arrow.down")
                }.frame(width: 90, height: 24, alignment: .trailing).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("依大小排序")
            .help("在各工具與類型群組內切換大小由大到小／由小到大")
        }
        .font(.caption).padding(.vertical, 4)
        .accessibilityElement(children: .contain)
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
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(item.name).fontWeight(.medium).lineLimit(1)
                        Spacer(minLength: 8)
                        Group {
                            if item.measurementAvailable {
                                Text(item.modified, format: .dateTime.year().month().day())
                            } else {
                                Text("未取得")
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .frame(width: 112, alignment: .leading)
                        Text(item.measurementAvailable ? formatBytes(item.bytes) : "無法估算").monospacedDigit()
                            .frame(width: 90, alignment: .trailing)
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
