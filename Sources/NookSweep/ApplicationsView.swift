import AppKit
import NookSweepCore
import SwiftUI

struct ApplicationsView: View {
    @ObservedObject var model: ApplicationsModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("軟體移除").font(.title2.weight(.semibold))
                Spacer()
                TextField("搜尋名稱、bundle ID 或路徑", text: $model.query)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                    .accessibilityLabel("搜尋應用程式")
                if model.isScanning {
                    ProgressView().controlSize(.small)
                    Button("取消") { model.cancelScan() }
                } else {
                    Button("重新掃描", systemImage: "arrow.clockwise") { model.startScan() }
                        .disabled(model.isRemoving)
                }
            }
            .padding(24)
            Divider()
            HSplitView {
                applicationList.frame(minWidth: 280, idealWidth: 360)
                ApplicationsDetailView(model: model).frame(minWidth: 320, idealWidth: 400)
            }
            if let report = model.report {
                Divider()
                ApplicationsReportView(report: report, reveal: model.reveal)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                if !model.warnings.isEmpty {
                    DisclosureGroup("\(model.warnings.count) 個項目無法完整檢查") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(model.warnings.enumerated()), id: \.offset) { _, warning in
                                    Text(warning).font(.caption).textSelection(.enabled)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 100)
                    }.font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 12)
        }
        .onChange(of: model.selectedID) { _, _ in model.inspectSelection() }
        .confirmationDialog("將「\(model.selectedApplication?.name ?? "App")」移到垃圾桶？",
            isPresented: $model.showConfirmation, titleVisibility: .visible) {
            Button("移到垃圾桶", role: .destructive) { model.removeSelected() }
            Button("取消", role: .cancel) { }
        } message: {
            Text(model.selectedRelatedItems.isEmpty
                ? "只會移除 App。相關資料會保留，您可從垃圾桶放回 App。"
                : "同時移除您勾選的 \(model.selectedRelatedItems.count) 項相關資料，可能包含設定、登入狀態與使用者內容。取回時需從垃圾桶放回原路徑。")
        }
    }

    private var applicationList: some View {
        Group {
            if model.applications.isEmpty && model.isScanning {
                ContentUnavailableView("正在讀取應用程式", systemImage: "app.dashed",
                    description: Text("清單會先出現，再逐一量測大小。"))
            } else if model.visibleApplications.isEmpty {
                ContentUnavailableView("沒有符合條件的 App", systemImage: "app",
                    description: Text("掃描範圍為 /Applications 與個人 Applications，包含一層子資料夾。"))
            } else {
                List(selection: $model.selectedID) {
                    ForEach(model.visibleApplications) { app in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                .resizable().frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.name).fontWeight(.medium).lineLimit(1)
                                Text(app.bundleID).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                if let reason = app.blockedReason {
                                    Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            Spacer(minLength: 4)
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(app.bytes == 0 && model.isScanning ? "量測中" : formatBytes(app.bytes))
                                    .monospacedDigit()
                                Text(app.version).font(.caption).foregroundStyle(.secondary)
                            }.font(.caption)
                        }
                        .padding(.vertical, 5).tag(app.id)
                        .contextMenu {
                            Button("在 Finder 顯示") { model.reveal(app.url) }
                        }
                    }
                }
                .listStyle(.inset).disabled(model.busy)
            }
        }
    }
}
