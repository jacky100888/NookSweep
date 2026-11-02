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
            if report.results.contains(where: \.needsPermissionHelp) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("macOS 權限不足")
                        .font(.subheadline.weight(.semibold))
                    Text("可在 Finder 選取被拒絕的項目後按 ⌘⌫，依系統提示驗證管理員身分。也可到「系統設定 → 隱私權與安全性 → App 管理」允許 NookSweep；若未列出，按「＋」加入 NookSweep.app。App 仍在原位置時，調整權限後可重新掃描；App 已移除時，請用下方 Finder 按鈕處理保留資料。若仍被拒絕，請使用該 App 的官方移除程式。")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("開啟 App 管理設定", systemImage: "gearshape", action: openPermissions)
                        .font(.caption)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
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
            }.frame(maxHeight: 140)
        }.padding(.horizontal, 24).padding(.vertical, 14)
    }
}
