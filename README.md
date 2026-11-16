# davinci-sukisu-nova — Xiaomi Mi 9T / Redmi K20 (davinci) 自訂內核

以 **LineageOS 23.2（Android 16）** 為基底的 Xiaomi Mi 9T / Redmi K20（代號 **davinci**，Snapdragon 730 / sm6150，kernel 4.14）自訂內核。
內建 **[SukiSU-Nova](https://github.com/SukiSU-Nova/SukiSU-Nova)（`builtin` 分支）**、**SUSFS v2.4.0**、**KPM（Kernel Patch Module）**、進階防檢測隱藏與全套**不超頻**安全效能優化，並附帶一個有 WebUI 的「遊戲模式」模組。

> **核心原則：不超頻、不放寬溫控、不影響硬體壽命。** CPU、GPU、螢幕刷新率都維持原廠上限；不改電壓表、不提高充電電流。所有效能優化都是在原廠範圍內改善反應、精簡除錯開銷與提升編譯效率，絕不拉高硬體天花板。

---

## 功能總覽

### 1. Root、SUSFS 與防檢測隱藏
- **基底**：LineageOS `lineage-23.2`，kernel **4.14.357-openela**（4.14 最新 LTS）。
- **Root 方案：[SukiSU-Nova](https://github.com/SukiSU-Nova/SukiSU-Nova)**（`builtin` 分支，支援內建 `NyaZygisk` 與內核擴展中心）：
  - **KPM 支援**（`CONFIG_KPM=y`）：支援 Kernel Patch Module 內核模組注入。
  - **ADB Root 支援**（`CONFIG_KSU_FEATURE_ADBROOT=y`）。
  - **Android 16 `init.rc` fstat 修正**：在 `vfs_statx_fd` 實作 `ksu_handle_vfs_fstat`，確保 Android 16 `init` 完整讀取附加的 `ksud` 啟動區段。
- **SUSFS v2.4.0（4.14 穩定移植版）**：
  - `sus_path`（ENOENT 模型）、`spoof_uname`、`spoof_cmdline`、`hide_ksu_susfs_symbols`、`enable_log`。
  - **`priority_uid_filter`**（`CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER=y`）：攔截 `getpriority` / `setpriority` / `ioprio_get` / `ioprio_set` 跨 UID 探測。
  - 掛載隱藏走 SukiSU-Nova 的 `try_umount`（backport Linux 5.9 的 `path_umount`）。
- **LineageOS / Zygisk 記憶體映射隱藏（`69_hide_stuff`）**：
  - 在 `/proc/<pid>/maps` 與 `/proc/<pid>/map_files` 將包含 `"lineage"` 的路徑偽裝為 `/system/framework/framework-res.apk`。
  - 抹除 `"jit-zygote-cache"` 區段的 `x`（可執行）權限顯示，防止銀行與防作弊檢測。

### 2. 安全效能與續航優化（全數不超頻、不傷壽命）
- **Sultan `cpu_input_boost` + `devfreq_boost`**：觸控與亮螢幕時將 CPU 大小核與 DDR 頻寬拉到**原廠最高頻率**（`min(freq, policy->max)` 夾限，絕不超頻）。
- **Kryo 470 (ARMv8.2-A) 編譯器指令集優化**：啟用 `-mcpu=cortex-a76.cortex-a55` 原生指令排程。
- **ZRAM 預設 LZ4 + 關閉 Writeback**：使用高速 LZ4 壓縮並關閉 `CONFIG_ZRAM_WRITEBACK`，避免額外磨損 UFS 2.1 閃存壽命。
- **TCP BBR + `fq` qdisc**：預設啟用 BBR 擁塞控制演算法（並內建 WireGuard）。
- **核心熱路徑除錯去負載（Stage 3 Debloat）**：
  - 關閉 `CONFIG_SLUB_DEBUG`（降低 `kmalloc` 延遲）、`CONFIG_SCHED_DEBUG`、`CONFIG_IPC_LOGGING`、`CONFIG_QCOM_RTB`、`CONFIG_BLK_DEV_IO_TRACE`、`CONFIG_MSM_TZ_LOG`。
  - **完整保留** `CONFIG_AUDIT`、`CONFIG_KALLSYMS`、`CONFIG_KALLSYMS_ALL` 與 `CONFIG_FTRACE`，確保 Android 16、BPF 與 KPM 100% 穩定不重啟。
- **RCU Priority Boosting**（`CONFIG_RCU_BOOST=y`）：防止高負載時 RCU reader 延遲導致的 UI 掉幀。
- **KCAL 螢幕色彩控制**（`CONFIG_DRM_MSM_KCAL_CTRL=y`）與 **小米觸控硬體遊戲模式節點**（`/sys/class/touch/touch_dev/touch_mode`）。

### 3. 遊戲模式模組（Magisk / SukiSU，附 WebUI）
位於 [`minatok20/gamemode/`](minatok20/gamemode)。偵測前景 App，對清單中的遊戲自動套用效能設定、退出還原：
- 大核 CPU / GPU / DDR 頻寬**下限**拉高（最高頻率維持原廠不動）。
- 降低 WALT `sched_upmigrate` / `downmigrate`，主執行緒更快上 A76 大核。
- 硬體**觸控遊戲模式 / 高回報率**（透過 `/sys/class/touch/touch_dev/touch_mode`）。
- 開機微調：UFS I/O 排程切換為 `deadline`、ZRAM 擴充至 3GB。

---

## 編譯（GitHub Actions）

進入 GitHub Actions 的 **`Build SukiSU-Nova (davinci)`** workflow，點擊 **Run workflow**：
- `ksu_ref`：預設 `builtin`（對應 SukiSU-Nova 的 4.14 manual/inline hook 分支）。
- `susfs`：預設 `true`（啟用 SUSFS v2.4.0 inline hook；設為 `false` 則為純 Manual Hook）。
- `release`：勾選後自動發布至 GitHub Releases。

---

## 刷機（LineageOS Recovery）

**請先備份原廠 `boot.img` 與 `dtbo.img`。**

```bash
adb reboot recovery
# Recovery: Apply update -> Apply from ADB
adb sideload sukisu-nova-davinci-<variant>-<date>-<sha>.zip
```
刷入後開機，安裝對應的 **SukiSU-Nova Manager APK** 即可管理 Root、SUSFS（內核擴展中心）、NyaZygisk 與 KPM。

---

## 授權

Linux 內核與本專案的內核改動以 **GPL-2.0** 授權（見 [`COPYING`](COPYING)）。
