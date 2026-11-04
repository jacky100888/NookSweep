import SwiftUI

@MainActor
final class HelpModel: ObservableObject {
    @Published var topic: HelpTopic? = .start
}

struct HelpSection: Identifiable {
    let title: String
    let body: String
    var id: String { title }
}

enum HelpTopic: String, CaseIterable, Identifiable {
    case start = "開始使用"
    case cleaning = "快取與 AI"
    case applications = "軟體移除"
    case permissions = "權限與還原"
    case status = "即時狀態"
    case updates = "更新與版本"

    var id: Self { self }
    var symbol: String {
        switch self {
        case .start: "hand.wave"
        case .cleaning: "sparkles"
        case .applications: "app.badge"
        case .permissions: "checkmark.shield"
        case .status: "waveform.path.ecg"
        case .updates: "arrow.down.circle"
        }
    }
    var introduction: String {
        switch self {
        case .start: "先查看，再選取，確認後才移到垃圾桶。"
        case .cleaning: "了解各種資料的整理範圍與保留原因。"
        case .applications: "預覽 App 與相關資料，再選擇移除方式。"
        case .permissions: "分清楚授權與檔案權限，並保留還原所需的資訊。"
        case .status: "查看這部 Mac 的實際讀值與短期趨勢。"
        case .updates: "檢查正式版本，前往 GitHub 下載更新。"
        }
    }
    var sections: [HelpSection] {
        switch self {
        case .start:
            [HelpSection(title: "1. 掃描與預覽", body: "從側欄選擇清理範圍，按「開始掃描」。掃描只讀取資料，可隨時取消；點選項目可查看完整路徑、日期與保留原因。"),
             HelpSection(title: "2. 選取要整理的內容", body: "預設不選取任何資料。先結束相關 App、AI 工作或建置，再勾選可整理項目；日期與搜尋篩選不會取消已選項目，請留意底部的完整選取總量。"),
             HelpSection(title: "3. 確認移到垃圾桶", body: "檢查確認視窗的範圍與風險，再按移到垃圾桶。程式會重新驗證，逐項回報成功或保留原因。垃圾桶內的資料仍占用空間；本工具不會替你清空垃圾桶。")]
        case .cleaning:
            [HelpSection(title: "一般快取與記錄檔", body: "一般快取至少閒置 7 天、記錄檔至少 30 天才可整理。項目內有近期檔案、正在使用、無法讀取或布局不明時會保留；不清理任意系統檔案。"),
             HelpSection(title: "AI 工具清理入口", body: "選「開發工具快取 → AI 工具清理」，再以資料類型選擇快取、對話與本機歷史、舊版本或工作副本。列表依工具分組，可按日期或大小排序，並全選目前篩選範圍的可整理項目。"),
             HelpSection(title: "舊對話與歷史", body: "開啟頁內的「允許整理舊對話／歷史」後才可選取。15／30／60 天篩選依最近修改時間顯示資料，實際整理仍需至少閒置 30 天。索引管理、資料庫與執行中的對話會保留；移除可能失去對話上下文。"),
             HelpSection(title: "工作副本", body: "預設只整理乾淨、已合併且超過閒置門檻的副本。手動模式可能包含未提交、未追蹤與未合併工作，請先停止使用並確認完整路徑。會連同專屬 Git 管理目錄整組移到垃圾桶，並保留提交還原參照；主工作副本與不明結構仍保留。")]
        case .applications:
            [HelpSection(title: "預覽與相關資料", body: "掃描 /Applications 與個人 Applications，包含一層子資料夾。選取 App 後可查看名稱、版本、大小與路徑。相關資料可能包含設定、登入狀態與使用者內容，預設全部保留，請確認備份後再選填。"),
             HelpSection(title: "執行中的 App", body: "可在確認視窗選「結束並移到垃圾桶」或「強制結束並移到垃圾桶」，不用手動先關閉。強制結束會遺失未儲存內容；無法結束、再次啟動或內容已改變時會保留。Apple 系統 App 與 NookSweep 自身受保護。"),
             HelpSection(title: "含系統服務的工具", body: "VPN、防毒或含系統服務的 App，應使用官方移除程式處理服務、網路設定與管理員驗證。只移走 App 不等於完整解除安裝；強制結束也不會繞過 macOS 權限。")]
        case .permissions:
            [HelpSection(title: "App 管理與管理員權限不同", body: "「系統設定 → 隱私權與安全性 → App 管理」允許 NookSweep 更新或移除其他 App，但不會授予管理員身分。檔案擁有者、存取權限或系統保護仍可能拒絕操作；可在 Finder 選取項目後按 ⌘⌫，依系統提示驗證，或使用官方移除程式。"),
             HelpSection(title: "找不到 NookSweep 或仍看到警告", body: "權限結果提供目前 App 路徑與複製、Finder 定位按鈕。在 App 管理按「＋」後，可按 ⌘⇧G 貼上路徑選取。結果提示是上次操作記錄，調整授權後請重新掃描再重試；更新或搬動程式後，系統可能要求重新允許。"),
             HelpSection(title: "從垃圾桶還原", body: "先停止相關 App，再將項目放回結果所列的原始路徑；若已有同名資料，先確認要保留的版本。工作副本的工作區與 Git 管理目錄須一起還原，並保留原儲存庫；使用結果中的還原資訊核對路徑。垃圾桶清空後無法由本工具復原。")]
        case .status:
            [HelpSection(title: "讀值與取樣", body: "CPU、記憶體、磁碟、網路與電池由系統 API 取樣，每 2 秒更新。CPU 與網路首次需等第二次取樣；無法取得的項目會標示，不用模擬數值代替。熱狀態是系統等級，不是攝氏溫度。"),
             HelpSection(title: "趨勢與選單列", body: "主視窗與選單列波形圖示共用資料，可暫停、繼續或手動更新。高記憶體程序的駐留記憶體可能包含共用頁面，不能直接加總；磁碟可用量包含系統可回收空間。"),
             HelpSection(title: "關閉視窗後", body: "關閉主視窗後仍可從選單列開啟主視窗、閱讀說明與查看更新。要停止整個程式，請選「結束 NookSweep」。")]
        case .updates: []
        }
    }
}
