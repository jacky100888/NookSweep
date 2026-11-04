import AppKit
import SwiftUI

struct HelpView: View {
    @ObservedObject var model: HelpModel
    @ObservedObject var updates: AppUpdateModel

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $model.topic) { topic in
                Label(topic.rawValue, systemImage: topic.symbol).tag(topic)
            }
            .listStyle(.sidebar).navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            let topic = model.topic ?? .start
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(topic.rawValue).font(.title.weight(.semibold))
                        Text(topic.introduction).foregroundStyle(.secondary)
                    }
                    if topic == .updates { updateSettings }
                    else {
                        ForEach(topic.sections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title).font(.headline)
                                Text(section.body).lineSpacing(4).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: 620, alignment: .leading).padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 720, minHeight: 540)
        .navigationTitle("NookSweep 使用說明")
        .task { updates.checkForUpdates(automatic: true) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            updates.checkForUpdates(automatic: true)
        }
    }

    private var updateSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            LabeledContent("目前版本", value: updates.currentVersion)
            Toggle("自動檢查新版本", isOn: $updates.automaticallyChecks)
                .toggleStyle(.checkbox)
            Text("啟動或回到前景時，每 24 小時最多檢查一次正式版本。只向 GitHub 讀取公開更新資訊，不傳送掃描結果或對話內容。")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(updates.isChecking ? "正在檢查…" : "檢查更新") { updates.checkForUpdates() }
                    .disabled(updates.isChecking)
                if updates.isChecking { ProgressView().controlSize(.small) }
            }
            Text(updates.status).textSelection(.enabled).accessibilityLabel("更新檢查結果")
            if let date = updates.lastCheckedAt {
                Text("最近檢查：\(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let release = updates.availableRelease {
                Link("前往 GitHub 下載 \(release.version)", destination: release.pageURL)
                    .buttonStyle(.borderedProminent)
            }
            Divider()
            Text("下載與安裝").font(.headline)
            Text("從發布頁下載 NookSweep-app.zip，解壓縮後結束舊版，再將 App 放入「應用程式」取代舊版。更新不會自動下載或覆寫程式。若系統要求重新授權，請在 App 管理選取更新後的 NookSweep。")
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            Text("同一份 App 支援 Apple Silicon 與 Intel，最低需要 macOS 14。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
