import AppKit
import NookSweepCore
import SwiftUI

struct ResultsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                TextField("搜尋名稱或路徑", text: $model.query)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                    .accessibilityLabel("搜尋名稱或路徑")
                Toggle("只顯示可整理項目", isOn: $model.eligibleOnly)
                    .toggleStyle(.checkbox).font(.caption)
                Spacer(minLength: 0)
                Menu {
                    Button("選取目前顯示的可整理項目") { model.selectVisible() }
                        .keyboardShortcut("a", modifiers: [.command, .shift])
                    Button("取消所有選取") { model.selected.removeAll() }
                } label: { Label("選取", systemImage: "checklist") }
                .fixedSize()
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            if model.visibleItems.isEmpty {
                ContentUnavailableView {
                    Label(model.items.isEmpty ? "沒有找到快取項目" : "目前沒有符合條件的項目",
                          systemImage: "checkmark.circle")
                } description: {
                    Text(model.eligibleOnly
                         ? "近期使用或受保護的資料會保留。取消「只顯示可整理項目」可查看原因。"
                         : "試著清除搜尋文字或切換清理分類。")
                }
            } else {
                Table(model.visibleItems, selection: $model.focusedID) {
                    TableColumn("") { item in
                        Toggle("選取 \(item.name)", isOn: Binding(
                            get: { model.selected.contains(item.id) },
                            set: { if $0 { model.selected.insert(item.id) }
                                   else { model.selected.remove(item.id) } }
                        ))
                        .labelsHidden().toggleStyle(.checkbox)
                        .disabled(!item.isEligible)
                        .help(item.state.reason ?? "選取此項目")
                    }.width(26)
                    TableColumn("名稱") { item in
                        HStack(spacing: 9) {
                            Image(systemName: item.category.symbol)
                                .foregroundStyle(.secondary).frame(width: 20)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).fontWeight(.medium).lineLimit(1)
                                Text(item.state.reason ?? item.aiToolName.map { "\($0) · \(item.category.rawValue)" } ?? item.category.rawValue)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .padding(.vertical, 5)
                        .contextMenu {
                            Button("在 Finder 顯示") { model.reveal(item) }
                            Button("複製路徑") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.url.path, forType: .string)
                            }
                        }
                    }.width(min: 160, ideal: 300)
                    TableColumn("大小") { item in
                        Text(item.measurementAvailable ? formatBytes(item.bytes) : "—").monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }.width(90)
                    TableColumn("最近修改") { item in
                        Text(item.modified, format: .dateTime.year().month().day())
                            .foregroundStyle(.secondary)
                    }.width(100)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
            HStack {
                Text("顯示 \(model.visibleItems.count) 項 · 大小由大到小")
                Spacer()
                Text("已選取 \(model.selectedItems.count) 項")
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 24).padding(.vertical, 10)
        }
        .disabled(model.isCleaning)
    }
}
