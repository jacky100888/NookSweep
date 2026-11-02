import Foundation
import NookSweepCore
import SwiftUI

struct ApplicationsReportView: View {
    let report: ApplicationRemovalReport
    let reveal: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("移除結果 · \(report.movedCount) 項已移到垃圾桶 · \(formatBytes(report.movedBytes))")
                .font(.subheadline.weight(.medium))
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
                            Button("在 Finder 顯示") { reveal(item.trashURL ?? item.originalURL) }
                                .font(.caption)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 140)
        }.padding(.horizontal, 24).padding(.vertical, 14)
    }
}
