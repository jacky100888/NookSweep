import AppKit
import Foundation
import NookSweepCore
import SwiftUI

struct ApplicationsReportView: View {
    let report: ApplicationRemovalReport
    let reveal: (URL) -> Void
    let openPermissions: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("移除結果 · \(report.movedCount) 項已移到垃圾桶 · \(formatBytes(report.movedBytes))")
                .font(.subheadline.weight(.medium))
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if report.results.contains(where: \.needsPermissionHelp) {
                        let applicationURL = Bundle.main.bundleURL
                        VStack(alignment: .leading, spacing: 8) {
                            Text("上次移除遭系統拒絕")
                                .font(.subheadline.weight(.semibold))
                            Text("這是上次操作結果，不代表「App 管理」目前未開啟。該開關不會授予管理員身分；檔案擁有者、存取權限或系統保護也可能造成拒絕。")
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("若尚未允許 NookSweep，請至「App 管理」設定；未列出時按「＋」，再按 ⌘⇧G 貼上以下路徑。")
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(applicationURL.path)
                                .font(.caption.monospaced()).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("開啟 App 管理設定", systemImage: "gearshape", action: openPermissions)
                                .font(.caption)
                            HStack {
                                Button("複製 NookSweep 路徑", systemImage: "doc.on.doc") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(applicationURL.path, forType: .string)
                                }
                                Button("在 Finder 顯示 NookSweep", systemImage: "folder") {
                                    reveal(applicationURL)
                                }
                            }
                            .font(.caption)
                            Text("授權變更後，請先重新掃描再重試。若仍被拒絕，可在 Finder 選取項目後按 ⌘⌫，依系統提示驗證管理員身分。VPN、防毒或含系統服務的 App 請使用官方移除程式；App 已移除時，請用下方 Finder 按鈕處理保留資料。")
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    ForEach(report.results) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: item.succeeded ? "checkmark.circle" : "exclamationmark.triangle")
                                .foregroundStyle(item.succeeded ? Color.secondary : Color.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.originalURL.path).textSelection(.enabled)
                                Text(item.error ?? "已移到垃圾桶；復原時請放回上方原路徑。")
                                    .foregroundStyle(.secondary).textSelection(.enabled)
                            }.font(.caption)
                            Spacer(minLength: 8)
                            Button(item.needsPermissionHelp ? "在 Finder 處理" : "在 Finder 顯示") {
                                reveal(item.trashURL ?? item.originalURL)
                            }
                                .font(.caption)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 180)
        }.padding(.horizontal, 24).padding(.vertical, 14)
    }
}
