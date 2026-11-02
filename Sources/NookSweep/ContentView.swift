import NookSweepCore
import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()
    @StateObject private var applications = ApplicationsModel(automaticallyScans: false)
    @ObservedObject var monitor: StatusModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model).navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 270)
                .disabled(model.isCleaning || applications.isRemoving)
        } detail: {
            if model.scope == .status {
                StatusView(model: monitor)
            } else if model.scope == .applications {
                ApplicationsView(model: applications)
            } else {
            VStack(spacing: 0) {
                header
                Divider()
                if model.isScanning { scanning }
                else if model.result == nil { welcome }
                else if model.isAIScope { AIResultsView(model: model) }
                else { ResultsView(model: model) }
                Divider()
                footer
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem {
                    Button {
                        model.startScan()
                    } label: { Label("重新掃描", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.busy)
                    .help("重新掃描（⌘R）")
                }
                ToolbarItem {
                    Button { model.showDetails.toggle() } label: {
                        Label("項目資訊", systemImage: "sidebar.right")
                    }
                    .help("顯示項目資訊")
                }
            }
            .inspector(isPresented: $model.showDetails) {
                ItemDetailView(model: model)
                    .inspectorColumnWidth(min: 240, ideal: 270, max: 330)
            }
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .onChange(of: model.focusedID) { _, value in
            if value != nil { model.showDetails = true }
        }
        .onChange(of: model.scope) { _, value in
            model.scopeDidChange()
            if value == .applications, applications.applications.isEmpty, !applications.busy {
                applications.startScan()
            }
        }
        .confirmationDialog("將 \(model.selectedItems.count) 個項目移到垃圾桶？",
                            isPresented: $model.confirmCleanup, titleVisibility: .visible) {
            Button(model.selectedHistoryCount + model.selectedWorktreeCount > 0 ? "確認整理所選資料" : "移到垃圾桶", role: .destructive) {
                model.cleanSelected(confirmedAIHistory: model.selectedHistoryCount > 0,
                                    confirmedAIWorktrees: model.selectedWorktreeCount > 0)
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text(model.cleanupWarning)
        }
        .sheet(isPresented: $model.showReport) { ReportView(model: model) }
        .sheet(isPresented: $model.showWarnings) {
            MessageSheet(title: "略過的項目", messages: model.result?.warnings ?? [])
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text((model.scope ?? .all).title).font(.system(size: 25, weight: .semibold))
                Text("先看清楚，再騰出空間。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if model.result != nil {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatBytes(model.eligibleBytes)).font(.title2.weight(.semibold)).monospacedDigit()
                    Text("\(model.eligibleItems.count) 項可整理").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 22)
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.system(size: 58, weight: .light)).foregroundStyle(.secondary)
            Text("讓 Mac 多一點空間").font(.system(size: 26, weight: .semibold))
            Text(model.isAIScope
                 ? "完整列出 AI 快取、版本、對話與工作副本，並說明保留原因。\n舊對話與工作副本需要另外確認；索引管理的紀錄會保留。"
                 : "找出閒置的應用程式快取、AI 暫存與舊記錄檔。\n掃描只會讀取資料，完成後由你選擇要整理的項目。")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).lineSpacing(5)
            Button("開始掃描", systemImage: "magnifyingglass") { model.startScan() }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction).padding(.top, 6)
            Text("本機處理 · 不需管理員權限").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(model.status).font(.caption).foregroundStyle(.secondary).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }

    private var scanning: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("正在檢查可整理的資料").font(.title3.weight(.semibold))
            Text("已檢查 \(model.inspectedCount.formatted()) 個檔案")
                .monospacedDigit().foregroundStyle(.secondary)
            Text(model.progressPath).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 500)
            Button("取消掃描") { model.cancelScan() }.keyboardShortcut(.cancelAction)
            Spacer()
            Text("掃描不會更動任何檔案").font(.caption).foregroundStyle(.secondary).padding(.bottom, 24)
        }.frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if model.isCleaning {
                ProgressView().controlSize(.small)
                Text("正在重新驗證並移到垃圾桶…").font(.caption)
            } else {
                Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let warnings = model.result?.warnings, !warnings.isEmpty {
                Button("略過 \(warnings.count) 項") { model.showWarnings = true }
                    .font(.caption).disabled(model.busy)
            }
            if model.result != nil {
                Button("移到垃圾桶 · \(formatBytes(model.selectedBytes))", systemImage: "trash") {
                    model.confirmCleanup = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedItems.isEmpty || model.busy)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }
}
