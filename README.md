# NookSweep

NookSweep 是以 SwiftUI 製作的 macOS 清理與狀態監測工具。先查看路徑與內容狀態，再選擇要移到垃圾桶的資料；所有掃描與系統指標都在本機處理，沒有遙測或雲端服務。

使用 Swift、Foundation 與 macOS 系統框架，無第三方相依套件，以 [MIT 授權](LICENSE) 開源。

## 功能

- 掃描應用程式快取、舊記錄檔、開發工具快取與明確列出的 AI 工具暫存。
- 分類搜尋、查看大小與完整路徑、在 Finder 顯示、逐項選取與清理結果回報。
- 選擇開啟舊 AI 對話掃描，與可重建的暫存分開呈現。
- 狀態頁與選單列面板：CPU 與每核心使用率、記憶體與壓力、磁碟可用量、網路速率、電池、開機時間及高記憶體程序。
- 每 2 秒更新系統指標，可暫停、繼續、手動更新及查看短期趨勢。

## 開啟與使用

從 [GitHub Releases](https://github.com/jacky100888/NookSweep/releases) 下載 App；首個手動發布版本適用 Apple Silicon。

需要 macOS 14 以上。開啟 `NookSweep.app`，也可以將它移到「應用程式」。下載產物的架構以發布說明為準；自行建置時會使用目前工具鏈的目標架構。

側欄「即時狀態」提供完整指標；選單列的 N 圖示提供簡短面板。關閉主視窗後仍可從選單列查看、暫停監測、重新開啟主視窗或結束 App。

1. 在側欄選「全部項目」，再按「開始掃描」。掃描只會讀取檔案，可隨時取消。
2. 依分類或名稱篩選，點選項目查看完整路徑、大小、最近修改時間與保留原因。
3. 先結束相關應用程式、AI CLI、建置與套件安裝工作，再勾選要清理的項目。
4. 按「移到垃圾桶」並確認。App 會重新驗證路徑與狀態，再逐項回報成功或保留原因。

預設不勾選任何項目。「選取」只勾選目前顯示的可整理項目；切換篩選後會保留已選項目，底部顯示完整選取總量。

資料移到垃圾桶後仍占用磁碟；清空垃圾桶才會釋放空間。App 不會清空垃圾桶。需要取回時，請從垃圾桶將項目移回原路徑；若應用程式已產生同名資料，先結束它並確認要保留的版本。

## 清理範圍

| 分類 | 範圍 | 最低閒置天數 |
| --- | --- | --- |
| 應用程式快取 | `~/Library/Caches` 的直接子項目 | 7 天 |
| 舊記錄檔 | `~/Library/Logs` 的直接子項目 | 30 天 |
| 開發工具快取 | Xcode DerivedData、npm、pip、uv、Gradle 的明確快取目錄 | 7 天 |
| AI 工具暫存 | Codex、Claude、Gemini 的明確暫存與記錄目錄，以及已辨識的 App 快取 | 7 天 |
| 舊 AI 對話 | 手動開啟後才掃描的已知對話檔案格式 | 30 天 |

開發工具路徑為 `~/Library/Developer/Xcode/DerivedData`、`~/.npm/_cacache`、`~/.cache/pip`、`~/.cache/uv`、`~/.gradle/caches`。

AI 暫存包括 `~/.claude/debug`、`~/.claude/paste-cache`、`~/.claude/shell-snapshots`、`~/.codex/log`、`~/.codex/shell_snapshots` 與 `~/.gemini/logs`。這些目錄可能含提示文字或診斷資訊，清理前仍應查看項目。

### AI 對話與暫存

舊對話掃描預設關閉。開啟後只辨識已知路徑與檔名格式，不讀取對話內容：

- Claude CLI：專案目錄內的已知 JSONL 對話檔，以及已知結構的子代理紀錄；不搬移整個專案資料夾。
- Gemini CLI：`~/.gemini/tmp/<project>/chats/session-*.json`。
- Codex：可查看 sessions 與 archived sessions，但保留並禁止清理，請由 Codex 管理對話。直接移走檔案可能讓 SQLite 索引與對話內容失去一致性。

舊對話不是可重建的快取，移除後可能失去聊天內容與接續工作的上下文。清理時需另外明確確認。設定、登入憑證、skills、rules、記憶、專案原始碼與 SQLite 主檔／WAL／SHM 均不在可清理範圍。

### 保留規則

一般資料夾的所有內容都必須超過閒置門檻；資料夾內有新檔案就會保留整個項目。不跟隨符號連結或 Finder 替身，不清理雲端項目、Apple 系統快取或受保護的設定快取。直接子項目中的鎖定檔與快取標記會保留；零容量與無法完整讀取的項目會保留或略過。

清理前會重新讀取檔案中繼資料，比對路徑、身分、大小與修改時間的指紋。掃描後有變動的項目會保留；這不是快照或跨程序鎖定。執行中的 App 與可辨識的 AI 工具會保留，但無法涵蓋所有共享快取或由 Node 等 runtime 啟動的 CLI，請先結束相關工作。

## 系統狀態的讀值範圍

系統指標透過 Mach、IOKit、SystemConfiguration 等系統 API 讀取，不需要管理員權限。CPU 與網路速率需要兩次取樣；首次顯示「取樣中」，無法讀取的指標會明確標示。

熱狀態採用 macOS 提供的狀態等級，不是攝氏溫度。本版不提供 GPU 使用率、硬體溫度或風扇轉速／控制，也不提供終止程序功能。高記憶體列表顯示程序的駐留記憶體，不應加總成整機用量。網路速率依主要介面取樣，介面切換或計數器回捲時會重新取樣。

磁碟可用量包含系統可回收容量。檔案大小以已配置容量估算；APFS 壓縮、複製與硬連結可能共用空間，與最終釋放容量不一定相同。

## 建置與測試

需要 macOS 與 Swift 6；可使用 Command Line Tools 或完整 Xcode。

```bash
git clone https://github.com/jacky100888/NookSweep.git
cd NookSweep
bash scripts/test.sh
bash scripts/build-app.sh
```

建置腳本會在專案上層產出 `NookSweep.app` 與 `NookSweep-app.zip`，並進行本機 ad hoc 簽署。腳本使用 SwiftPM 傳統建置模式；測試腳本在需要時明確指定 Command Line Tools 內附的 Swift Testing 與巨集位置，不下載套件。

測試只使用臨時夾具，其中部分測試會透過系統垃圾桶 API 移動自己建立的檔案，再移除該夾具。請勿將測試根目錄改成真實使用者資料，也不需要以 `sudo` 執行。

GitHub Actions 會執行測試、建置 App 並上傳 App ZIP。實際測試與發布結果請以儲存庫的 Actions 與發布說明為準。

App 尚未經 Apple Developer ID 簽署或公證。下載的 App 可能受到 Gatekeeper 限制；請自行檢視原始碼並建置，對外正式散布前需完成適當的簽署與公證。Intel 與 macOS 14 實機相容性仍需個別驗證。

## 專案結構

- `Sources/NookSweepCore`：清理政策、量測、AI 路徑辨識與系統指標取樣。
- `Sources/NookSweep`：SwiftUI 主視窗、選單列、篩選與結果回報。
- `Tests/NookSweepCoreTests`：清理邊界、狀態變動與系統指標計算測試。
- `scripts`：測試、App 打包與圖示產生。

## 參與與授權

參與方式請見 [CONTRIBUTING.md](CONTRIBUTING.md)，安全問題請見 [SECURITY.md](SECURITY.md)。程式碼採 [MIT 授權](LICENSE)，Copyright © 2026 Jacky。

清理流程受到 Mole 這類工具啟發。本專案獨立實作，不附帶或呼叫 Mole 的管理員 helper，也不使用它的程式碼或圖像資產。App 圖示為本專案以幾何路徑自繪的 N 標記。
