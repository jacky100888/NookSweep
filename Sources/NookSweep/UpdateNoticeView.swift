import SwiftUI

struct UpdateNoticeView: View {
    @ObservedObject var model: AppUpdateModel

    var body: some View {
        if model.showsUpdateNotice, let release = model.availableRelease {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle").foregroundStyle(.tint)
                Text("新版本 \(release.version) 可下載").font(.callout).lineLimit(2)
                Spacer(minLength: 0)
                Link("下載更新", destination: release.pageURL)
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .help("前往 NookSweep 的 GitHub 發布頁下載")
                Button(action: model.dismissNotice) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("關閉這個版本的更新提示")
                    .help("關閉此版本提示，仍可從檢查更新再次查看")
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary)
        }
    }
}
