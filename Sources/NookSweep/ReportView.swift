import AppKit
import SwiftUI

struct ReportView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let report = model.report {
                Label(report.failures.isEmpty ? "整理完成" : "整理結果",
                      systemImage: report.failures.isEmpty ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.title2.weight(.semibold))
                Text("已將 \(report.moved.count) 項（\(formatBytes(report.bytes))）移到垃圾桶。")
                Text("資料仍可從垃圾桶取回。只有清空垃圾桶後，磁碟空間才會實際釋放。")
                    .foregroundStyle(.secondary)
                if !report.failures.isEmpty {
                    Text("以下項目已保留：").fontWeight(.medium)
                    ScrollView {
                        Text(report.failures.joined(separator: "\n\n"))
                            .font(.caption).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 200)
                    Text("請重新掃描後再試，或在 Finder 確認權限。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("開啟垃圾桶", systemImage: "trash") {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent(".Trash"))
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(28).frame(width: 520)
    }
}

struct MessageSheet: View {
    let title: String
    let messages: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title2.weight(.semibold))
            Text("無法完整讀取、包含連結或不符規則的項目不會被清理。")
                .foregroundStyle(.secondary)
            ScrollView {
                Text(messages.joined(separator: "\n\n"))
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 300)
            HStack { Spacer(); Button("關閉") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(28).frame(width: 650)
    }
}
