# MoleDesk

免費、開源的 macOS SwiftUI 清理工具（早期測試版）。

## 目標平台
- macOS Monterey 12 或以上
- Intel x86_64
- 繁體中文介面

## 目前源碼
- **總覽**：磁碟空間及實體記憶體資訊（CPU 監測尚未實作）
- **安全清理**：只掃描用戶 `~/Library/Caches`、`~/Library/Logs` 的頂層項目
- **App 卸載**：將所選 `.app` 移到垃圾桶
- **App 殘留**：保守地以 App 名／Bundle ID 尋找 Library 項目，必須由用戶檢查
- **磁碟分析**：資料夾大小估算及彩色水平比例圖，並非完整 Treemap
- **還原紀錄**：記錄本工具移入垃圾桶的檔案，原位置無衝突時嘗試還原
- **Mole 預覽**：需要自行安裝官方 Mole CLI，執行 `mo clean --dry-run`

## 編譯
1. 開啟 [Actions](https://github.com/appbuilderlee2/MoleDesk/actions)
2. 選擇 **Build macOS Intel**，按 **Run workflow**，或等待推送自動編譯
3. 如果 workflow 成功，下載 `MoleDesk-Intel` artifact

**重要**：目前未在 macOS Monterey Intel 真機上編譯或測試成功；不得視為正式版。產生的 App 未簽名或 Apple 公證。請先用可丟棄的測試資料驗證垃圾桶和還原流程。

## 安全性
- 掃描預設不勾選任何項目。
- 移除前需再次確認。
- 不會以 GUI 呼叫 Mole 的永久清理。
- App 殘留比對只是候選名單，可能包含重要個人資料。
- 不要直接對重要工作資料執行清理；先備份。

本專案程式碼以 GNU GPL v3 或更新版本授權。
