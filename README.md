# 🚀 Universal System & Multi-Drive Disk Cleaner & Deep Storage Analyzer

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-blue.svg?logo=powershell)](https://microsoft.com/PowerShell)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011%20%7C%20Server-0078D6.svg?logo=windows)](https://www.microsoft.com/windows)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Maintenance](https://img.shields.io/badge/Maintained%3F-Yes-brightgreen.svg)]()

> An all-in-one, high-performance PowerShell application designed for every Windows user experiencing low storage issues.
> Thoroughly scans the complete file system tree structure across all existing drives, classifies unnecessary bloat, forcefully terminates locking processes, and permanently reclaims disk space with zero traces and an automated 10-second safety cancellation window.

---

## 🌟 Key Features

### 🔍 1. Deep Structural Multi-Drive Tree Scanning
- **Dedicated Target Drive Selector:** Automatically discovers and lists all fixed drives (`C:`, `D:`, etc.) with free/total capacity. Select specific drives or scan all drives simultaneously.
- **Embedded C# High-Speed Sizing Engine:** Traverses deep directory hierarchies in milliseconds, bypassing directory junctions, phone sync mounts, and reparse points without errors.
- **Unified Path Deduplication:** Ensures zero duplicate entries across system and user profile paths.

### 🗂️ 2. Smart Bloat & Storage Classification

| Category | Description & Cleanable Targets |
| :--- | :--- |
| **GPU & Shader Caches** | DirectX Shader Cache (`D3DSCache`), NVIDIA (`DXCache`, `GLCache`, `NV_Cache`), AMD (`DxCache`, `GLCache`), Intel Graphics Cache, and WebGPU/Dawn application caches. |
| **System & Windows Junk** | User Temp, Windows Temp, Windows Update installer downloads (`SoftwareDistribution\Download`), Delivery Optimization P2P cache, Prefetch, CBS/DISM servicing logs, crash dumps (`MEMORY.DMP`, minidumps), and Recycle Bins across all drives. |
| **Browser & App Caches** | Dynamic AppData tree scanning across Chrome, Edge, Brave, Firefox, Discord, Claude, Spotify, Telegram, Steam, and Electron apps (`Cache`, `Code Cache`, `GPUCache`, `blob_storage`, `Service Worker`). |
| **Logs & Crash Reports** | Application crash memory dumps (`CrashDumps`), Windows Error Reporting (`WER`), Crashpad reports, and system log files. |
| **Uninstalled Software Residuals & Updater Caches** | Cross-references dormant AppData folders against registered installed software in the Windows Registry to identify abandoned leftovers. Cleans Electron `*-updater` installer caches and `Downloaded Installations`. |
| **Developer & Build Caches** | NPM local/roaming caches, Python PIP wheels, `uv` cache, Playwright browser binaries, Gradle caches & daemon logs, Cargo registry, Maven local repo, and NuGet package stores. |
| **AI & Local LLM Models** | Ollama model weight blobs (`.ollama\models`), AnythingLLM storage engines, Hugging Face transformers, PyTorch checkpoints, and LM Studio models. |
| **WSL & Virtual Hard Disks** | Dynamic detection of WSL2 distributions (`ext4.vhdx`), Docker Desktop virtual disks, and PC Manager WSL layers. |
| **Large Forgotten Files (> 100 MB)** | Stale archives (`.zip`, `.rar`, `.7z`, `.tar`, `.gz`), installers (`.iso`, `.exe`, `.msi`), and disk images across root directories and user libraries. |

---

### 🛡️ 3. Safety Mechanisms & Process Unlocker

* ⏱️ **10-Second Safety Cancellation Window:**
  - Before any deletion starts, an interactive modal dialog appears with an itemized preview list, count, and total space to reclaim.
  - A 10-second countdown with an animated progress bar begins.
  - A prominent **`[ STOP & CANCEL (I want to review) ]`** button allows instant abort with **zero files touched**.
* 🛑 **Drive Root & System File Protection:**
  - Hardened guards strictly prevent accidental deletion of drive roots (`C:\`, `D:\`) and critical system paths (`C:\Windows`, `System32`, `C:\Users`).
  - Essential Windows swap and page files (`pagefile.sys`, `swapfile.sys`, `hiberfil.sys`) are protected.
* 📦 **Container-Safe Deletion:**
  - Root container folders like `%TEMP%` have their contents purged without deleting the parent folder, safely skipping in-use Windows kernel handles without erroring out.
* ⚡ **Force-Stop Process Unlocker:**
  - Automatically identifies and force-terminates running processes locking target directories (browsers, background services, Docker, WSL, developer daemons) prior to deletion.
  - Employs high-speed Win32 kernel calls (`cmd.exe /c rd /s /q`) for immediate, zero-trace removal.

---

## 🖥️ User Interface Overview

```
+----------------------------------------------------------------------------------------------------+
| Universal Multi-Drive Storage Cleaner & Process Unlocker                                           |
| [=========================== Progress Bar ===========================] Scan complete! 70 items.   |
+----------------------------------------------------------------------------------------------------+
| TARGET DRIVES FOR DEEP STRUCTURAL SCAN:                                                            |
| [x] [C:] System (104.9 GB Free / 272.2 GB)  [x] [D:] New Volume (49.9 GB Free / 204.6 GB)          |
|                                           [ Deep Scan Selected Drives ]  [ Check All ]  [ Clear ]  |
+----------------------------------------------------------------------------------------------------+
| [ Select Safe Junk (Temp/Caches) ] [ Select All ] [ Deselect All ]   |   Filter Search: [________] |
+----------------------------------------------------------------------------------------------------+
| [x] Category             | Item Name              | Size      | Description          | Path        |
| [x] GPU & Shader Caches  | NVIDIA GLCache         | 136.02 MB | NVIDIA OpenGL Shader | C:\Users... |
| [x] System & Windows Junk| Windows System Temp    | 882.20 KB | OS temporary files   | C:\Windo... |
| [x] Browser & App Caches | Brave Browser Cache    | 26.95 MB  | Web browser cache    | C:\Users... |
| [ ] Uninstalled Residuals| anythingllm-updater    | 388.51 MB | Updater cache        | C:\Users... |
+----------------------------------------------------------------------------------------------------+
| Selected: 12 items | Total Disk Space to Reclaim: 1.45 GB   [ Force-Stop & Delete Selected ]       |
| Live Console: [02:35:10] Scanning GPU & DirectX Shader Caches...                                   |
+----------------------------------------------------------------------------------------------------+
```

---

## 🚀 Getting Started

### Prerequisites
- Windows 10, Windows 11, or Windows Server
- PowerShell 5.1 or PowerShell 7+
- Administrator privileges (the script prompts for elevation automatically if needed)

### Running the Application

#### Option A: Quick Launcher (Recommended)
Double-click **`launch.bat`**. It will automatically launch PowerShell as Administrator and run the cleaner.

#### Option B: PowerShell Direct
Right-click `SystemDiskCleaner.ps1` and select **Run with PowerShell**, or execute via terminal:
```powershell
powershell -ExecutionPolicy Bypass -File .\SystemDiskCleaner.ps1
```

#### Option C: CLI Mode (Headless / Remote)
Run the script without GUI:
```powershell
powershell -ExecutionPolicy Bypass -File .\SystemDiskCleaner.ps1 -NoGui
```

---

## 🧪 Testing & Verification

An automated sandbox test suite is included in `tests/test_cleaner_sandbox.ps1`.
It creates an isolated temporary directory to verify:
1. Exact file and directory size calculations
2. Simulation of exclusive file locks by active background processes
3. Automatic process detection, termination, and process unlocking
4. Zero-trace permanent deletion
5. Drive root and system protection guards

Run the tests:
```powershell
powershell -ExecutionPolicy Bypass -File .\tests\test_cleaner_sandbox.ps1
```

---

## 📄 License

This project is licensed under the [MIT License](LICENSE) - see the LICENSE file for details.
