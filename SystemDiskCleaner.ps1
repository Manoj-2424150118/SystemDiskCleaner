<#
.SYNOPSIS
    Universal System & Multi-Drive Disk Cleaner & Deep Storage Analyzer
    Designed for all Windows users experiencing low storage issues.
    Thoroughly scans the entire file system tree structure across selected drives:
    - GPU & DirectX Shader Caches
    - System & Windows Junk (Temp, Prefetch, SoftwareDistribution, CBS Logs, Recycle Bins)
    - Browser & Electron App Caches (Chrome, Edge, Brave, Firefox, Discord, Spotify, Claude, etc.)
    - Application Logs, Bug Reports & Crash Dumps
    - Uninstalled Software Residuals & Updater Caches in AppData & ProgramData
    - Developer & Build Caches (NPM, PIP, UV, Gradle, Maven, NuGet, Cargo, Playwright)
    - AI & Local LLM Models (Ollama, AnythingLLM, HuggingFace, PyTorch)
    - WSL & Virtual Hard Disks (.vhdx)
    - Large Stale Archives & Files (> 100 MB)
    Includes a dedicated drive selector, 10-second safety cancellation countdown,
    automatic process unlocking, and zero-trace permanent deletion.
#>

param(
    [switch]$NoElevate,
    [switch]$NoGui,
    [switch]$ExportFunctionsOnly,
    [string[]]$CustomDrives
)

# -------------------------------------------------------------
# 1. AUTO-ELEVATION (Run as Administrator)
# -------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $NoElevate) {
    try {
        $scriptPath = $MyInvocation.MyCommand.Path
        if (-not $scriptPath) { $scriptPath = $PSCommandPath }
        if ($scriptPath) {
            Start-Process powershell.exe -Verb RunAs -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $scriptPath)
            exit
        }
    } catch {
        Write-Warning "Could not auto-elevate. Continuing with current privileges."
    }
}

# Load Windows Forms and Drawing assemblies when UI is needed
if (-not $NoGui -and -not $ExportFunctionsOnly) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
}

# -------------------------------------------------------------
# 2. HIGH-PERFORMANCE COMPILED C# FOLDER SIZE ENGINE
# -------------------------------------------------------------
if (-not ([System.Management.Automation.PSTypeName]'FastFolderSize').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.IO;

public static class FastFolderSize {
    public static long GetSize(string path) {
        if (string.IsNullOrEmpty(path)) return 0;
        try {
            if (!Directory.Exists(path)) return 0;
            var di = new DirectoryInfo(path);
            if ((di.Attributes & FileAttributes.ReparsePoint) != 0) return 0;
            return CalculateSize(di, 0);
        } catch { return 0; }
    }
    private static long CalculateSize(DirectoryInfo dir, int depth) {
        if (depth > 18) return 0;
        long size = 0;
        try {
            foreach (var fi in dir.EnumerateFiles()) {
                try { size += fi.Length; } catch {}
            }
        } catch {}

        try {
            foreach (var sub in dir.EnumerateDirectories()) {
                try {
                    if ((sub.Attributes & FileAttributes.ReparsePoint) == 0) {
                        size += CalculateSize(sub, depth + 1);
                    }
                } catch {}
            }
        } catch {}
        return size;
    }
}
"@
}

# -------------------------------------------------------------
# 3. CORE HELPER FUNCTIONS & SAFETY ENGINE
# -------------------------------------------------------------

function Get-FolderSizeFast {
    param([string]$Path)
    if (-not [System.IO.Directory]::Exists($Path)) { return 0 }
    try {
        return [FastFolderSize]::GetSize($Path)
    } catch {
        return 0
    }
}
Set-Alias -Name Get-FolderSizeSafe -Value Get-FolderSizeFast -ErrorAction SilentlyContinue

function Format-FileSize {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) {
        return ("{0:N2} GB" -f ($Bytes / 1GB))
    } elseif ($Bytes -ge 1MB) {
        return ("{0:N2} MB" -f ($Bytes / 1MB))
    } elseif ($Bytes -ge 1KB) {
        return ("{0:N2} KB" -f ($Bytes / 1KB))
    } else {
        return ("{0} B" -f $Bytes)
    }
}

function Stop-LockingProcessesForPath {
    param(
        [string]$TargetCategory,
        [string]$TargetPath,
        [scriptblock]$LogCallback
    )

    # 1. Category and known app process termination
    switch -Wildcard ($TargetCategory) {
        "*WSL*" {
            & $LogCallback "Shutting down WSL distributions to release virtual disks..."
            try { wsl.exe --shutdown 2>&1 | Out-Null } catch {}
            Start-Sleep -Milliseconds 600
        }
        "*Docker*" {
            & $LogCallback "Terminating Docker services and daemon..."
            $dockerProcs = @("Docker Desktop", "com.docker.backend", "dockerd", "docker", "vpnkit")
            foreach ($dp in $dockerProcs) {
                Get-Process -Name $dp -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            }
        }
        "*Ollama*" {
            & $LogCallback "Terminating Ollama background service..."
            @("ollama", "ollama app") | ForEach-Object {
                Get-Process -Name $_ -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            }
        }
        "*AnythingLLM*" {
            & $LogCallback "Closing AnythingLLM application..."
            Get-Process -Name "AnythingLLM" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        "*Chrome*" {
            & $LogCallback "Closing Google Chrome to release cache locks..."
            Get-Process -Name "chrome" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        "*Edge*" {
            & $LogCallback "Closing Microsoft Edge..."
            Get-Process -Name "msedge" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        "*Firefox*" {
            & $LogCallback "Closing Mozilla Firefox..."
            Get-Process -Name "firefox" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        "*Brave*" {
            & $LogCallback "Closing Brave Browser..."
            Get-Process -Name "brave" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        "*Discord*" {
            & $LogCallback "Closing Discord..."
            Get-Process -Name "Discord" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        "*Telegram*" {
            & $LogCallback "Closing Telegram..."
            Get-Process -Name "Telegram" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        "*Spotify*" {
            & $LogCallback "Closing Spotify..."
            Get-Process -Name "Spotify" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        "*Teams*" {
            & $LogCallback "Closing Microsoft Teams..."
            @("Teams", "ms-teams") | ForEach-Object {
                Get-Process -Name $_ -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            }
        }
        "*Developer*" {
            $devProcs = @("java", "node", "adb", "gradle", "studio64")
            foreach ($dp in $devProcs) {
                Get-Process -Name $dp -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # 2. Generic locking processes whose executable is located inside the TargetPath
    try {
        $runningProcesses = Get-Process -ErrorAction SilentlyContinue
        foreach ($proc in $runningProcesses) {
            try {
                if ($proc.MainModule.FileName -and $proc.MainModule.FileName.StartsWith($TargetPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                    & $LogCallback ("Terminating process '{0}' (PID: {1}) running from target directory..." -f $proc.ProcessName, $proc.Id)
                    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                }
            } catch {}
        }
    } catch {}
}

function Clean-FolderContentsSafe {
    param(
        [string]$Path,
        [scriptblock]$LogCallback
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    & $LogCallback ("Cleaning contents inside: {0}" -f $Path)
    
    $children = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    $deletedCount = 0
    $lockedCount = 0
    
    foreach ($item in $children) {
        try { [System.Windows.Forms.Application]::DoEvents() } catch {}
        
        try {
            if ($item.PSIsContainer) {
                cmd.exe /c "rd /s /q `"$($item.FullName)`"" 2>&1 | Out-Null
                if (Test-Path -LiteralPath $item.FullName) {
                    Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
            } else {
                [System.IO.File]::SetAttributes($item.FullName, [System.IO.FileAttributes]::Normal)
                [System.IO.File]::Delete($item.FullName)
            }
            
            if (-not (Test-Path -LiteralPath $item.FullName)) {
                $deletedCount++
            } else {
                $lockedCount++
            }
        } catch {
            $lockedCount++
        }
    }
    
    & $LogCallback ("Completed: Cleared {0} items ({1} active Windows session locks safely retained)." -f $deletedCount, $lockedCount)
    return $true
}

function Remove-ItemCompletely {
    param(
        [string]$Path,
        [scriptblock]$LogCallback
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        & $LogCallback ("Item does not exist or was already removed: {0}" -f $Path)
        return $true
    }

    # 1. Drive Root Guard: Instant block if path is a drive root (e.g. C:\ or D:)
    $cleanPath = $Path.Trim().TrimEnd('\')
    if ($cleanPath -match '^[a-zA-Z]:?$') {
        & $LogCallback ("[SAFETY BLOCKED] Drive root cannot be deleted: {0}" -f $Path)
        return $false
    }

    # 2. Critical System Directory Guard
    $normalized = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $forbidden = @(
        $env:SystemRoot,
        "$env:SystemRoot\System32",
        "$env:SystemRoot\SysWOW64",
        $env:USERPROFILE,
        $env:ProgramFiles,
        "${env:ProgramFiles(x86)}",
        "C:\Users",
        "C:\Users\Manoj\CrossDevice"
    )
    foreach ($fb in $forbidden) {
        if ($fb) {
            try {
                $normFb = [System.IO.Path]::GetFullPath($fb).TrimEnd('\')
                if ($normalized -ieq $normFb) {
                    & $LogCallback ("[SAFETY BLOCKED] Protected system path cannot be deleted: {0}" -f $Path)
                    return $false
                }
            } catch {}
        }
    }

    # 3. Handle Temp & Cache Containers: Clean contents inside without removing parent folder
    $isContainerOnly = (
        $Path -like "*\AppData\Local\Temp*" -or
        $Path -like "*\Windows\Temp*" -or
        $Path -like "*\SoftwareDistribution\Download*" -or
        $Path -like "*\CrashDumps*" -or
        $Path -like "*\Microsoft\Windows\WER*" -or
        $Path -like "*\Windows\Prefetch*"
    )
    if ($isContainerOnly) {
        return (Clean-FolderContentsSafe -Path $Path -LogCallback $LogCallback)
    }

    try { [System.Windows.Forms.Application]::DoEvents() } catch {}

    try {
        # Handle Recycle Bin across drives
        if ($Path -like "*`$Recycle.Bin*") {
            & $LogCallback "Purging Recycle Bin on all drives..."
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            return $true
        }

        $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue

        if (-not $item.PSIsContainer) {
            # Single File: Reset attributes and permanently delete
            [System.IO.File]::SetAttributes($Path, [System.IO.FileAttributes]::Normal)
            [System.IO.File]::Delete($Path)
            & $LogCallback ("Permanently removed file: {0}" -f $Path)
            return $true
        } else {
            # Directory: High-speed Win32 kernel deletion first
            cmd.exe /c "rd /s /q `"$Path`"" 2>&1 | Out-Null
            if (-not (Test-Path -LiteralPath $Path)) {
                & $LogCallback ("Permanently removed directory: {0}" -f $Path)
                return $true
            }

            # Fallback: Reset attributes recursively and delete
            Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try { [System.IO.File]::SetAttributes($_.FullName, [System.IO.FileAttributes]::Normal) } catch {}
            }
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            & $LogCallback ("Permanently removed directory: {0}" -f $Path)
            return $true
        }
    } catch {
        & $LogCallback ("Error deleting {0} : {1}" -f $Path, $_.Exception.Message)
        return $false
    }
}

# -------------------------------------------------------------
# 4. COMPREHENSIVE FILE SYSTEM TREE SCANNER & CLASSIFIER
# -------------------------------------------------------------
function Start-SystemDeepScan {
    param(
        [string[]]$SelectedDrives = @(),
        [scriptblock]$ProgressCallback
    )

    $itemsFound = [System.Collections.Generic.List[PSCustomObject]]::new()
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $addItem = {
        param([string]$Category, [string]$Name, [string]$Path, [bool]$Safe, [string]$Desc, [double]$CustomBytes = 0)
        try {
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return }
        } catch { return }
        $norm = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
        if ($seenPaths.Contains($norm)) { return }

        try {
            $bytes = $CustomBytes
            if ($bytes -le 0) {
                $fi = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
                if ($fi.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return }
                if (-not $fi.PSIsContainer) {
                    $bytes = $fi.Length
                } else {
                    $bytes = Get-FolderSizeFast -Path $Path
                }
            }

            if ($bytes -gt 200KB) {
                $seenPaths.Add($norm) | Out-Null
                $itemsFound.Add([PSCustomObject]@{
                    Selected    = $Safe
                    Category    = $Category
                    Name        = $Name
                    Size        = (Format-FileSize $bytes)
                    SizeBytes   = $bytes
                    Path        = $Path
                    Description = $Desc
                })
            }
        } catch {}
    }

    # Discover and filter fixed drives according to user selection
    $allFixedDrives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -eq [System.IO.DriveType]::Fixed }
    if ($SelectedDrives -and $SelectedDrives.Count -gt 0) {
        $normSelected = $SelectedDrives | ForEach-Object { $_.Trim().TrimEnd('\').ToUpper() + "\" }
        $drives = $allFixedDrives | Where-Object { $normSelected -contains $_.Name.ToUpper() }
    } else {
        $drives = $allFixedDrives
    }

    if ($drives.Count -eq 0) { $drives = $allFixedDrives }

    $selectedDriveLetters = $drives | ForEach-Object { $_.Name.Substring(0,1).ToUpper() }
    $sysDriveLetter = (Split-Path $env:SystemRoot -Qualifier).TrimEnd(':').ToUpper()
    $hasSystemDrive = $selectedDriveLetters -contains $sysDriveLetter

    # Discover all user profiles dynamically and filter by selected drives
    $allUserProfiles = @()
    $profileList = Get-ChildItem "C:\Users" -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @("Public", "Default", "Default User", "All Users") }
    foreach ($p in $profileList) {
        $allUserProfiles += $p.FullName
    }
    if ($allUserProfiles.Count -eq 0) { $allUserProfiles = @($env:USERPROFILE) }

    $userProfiles = $allUserProfiles | Where-Object {
        $pLetter = ([System.IO.Path]::GetPathRoot($_)).Substring(0,1).ToUpper()
        $selectedDriveLetters -contains $pLetter
    }

    # =========================================================
    # CATEGORY 1: GPU & SHADER CACHES
    # =========================================================
    & $ProgressCallback "Scanning GPU & DirectX Shader Caches..." 10
    foreach ($uPath in $userProfiles) {
        & $addItem "GPU & Shader Caches" "DirectX Shader Cache" "$uPath\AppData\Local\D3DSCache" $true "DirectX compiled shader cache"
        & $addItem "GPU & Shader Caches" "NVIDIA DirectX Cache" "$uPath\AppData\Local\NVIDIA\DXCache" $true "NVIDIA compiled DirectX shaders"
        & $addItem "GPU & Shader Caches" "NVIDIA OpenGL Cache" "$uPath\AppData\Local\NVIDIA\GLCache" $true "NVIDIA OpenGL compiled shaders"
        & $addItem "GPU & Shader Caches" "AMD DirectX Shader Cache" "$uPath\AppData\Local\AMD\DxCache" $true "AMD compiled DirectX shaders"
        & $addItem "GPU & Shader Caches" "AMD OpenGL Shader Cache" "$uPath\AppData\Local\AMD\GLCache" $true "AMD compiled OpenGL shaders"
        & $addItem "GPU & Shader Caches" "Intel Shader Cache" "$uPath\AppData\Local\Intel\ShaderCache" $true "Intel graphics shader cache"
    }

    # =========================================================
    # CATEGORY 2: SYSTEM & WINDOWS JUNK
    # =========================================================
    if ($hasSystemDrive) {
        & $ProgressCallback "Scanning Windows System Junk & Update Caches..." 22
        & $addItem "System & Windows Junk" "Windows System Temp" "C:\Windows\Temp" $true "Operating system temporary installation and update files"
        & $addItem "System & Windows Junk" "Windows Update Download Cache" "C:\Windows\SoftwareDistribution\Download" $true "Downloaded Windows update installer files"
        & $addItem "System & Windows Junk" "Windows Delivery Optimization" "C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache" $true "P2P peer download cache for Windows updates"
        & $addItem "System & Windows Junk" "Windows Prefetch Cache" "C:\Windows\Prefetch" $true "Old application prefetch traces"
        & $addItem "System & Windows Junk" "Windows CBS Servicing Logs" "C:\Windows\Logs\CBS" $true "Component-Based Servicing installation logs"
        & $addItem "System & Windows Junk" "Windows DISM Logs" "C:\Windows\Logs\DISM" $true "DISM deployment image servicing logs"
        & $addItem "System & Windows Junk" "Windows Memory Dump" "C:\Windows\MEMORY.DMP" $true "System kernel crash dump file"
        & $addItem "System & Windows Junk" "Windows Minidumps" "C:\Windows\Minidump" $true "BSOD crash minidump files"
        & $addItem "System & Windows Junk" "Downloaded Program Files" "C:\Windows\Downloaded Program Files" $true "Legacy ActiveX / downloaded program controls"
    }

    # User Profile Temp & Crash Dumps
    foreach ($uPath in $userProfiles) {
        $pLeaf = Split-Path $uPath -Leaf
        & $addItem "System & Windows Junk" ("User Temp Files ({0})" -f $pLeaf) "$uPath\AppData\Local\Temp" $true "Temporary files created by running user applications"
        & $addItem "Logs & Crash Reports" ("Crash Dumps ({0})" -f $pLeaf) "$uPath\AppData\Local\CrashDumps" $true "Application crash memory dumps (*.dmp)"
        & $addItem "Logs & Crash Reports" "Windows Error Reporting Telemetry" "C:\ProgramData\Microsoft\Windows\WER" $true "Windows error reporting telemetry and crash reports"
        & $addItem "Logs & Crash Reports" ("User WER Queue ({0})" -f $pLeaf) "$uPath\AppData\Local\Microsoft\Windows\WER" $true "User crash reports and error queues"
    }

    # Recycle Bin across selected drives
    foreach ($dr in $drives) {
        $rbPath = Join-Path $dr.RootDirectory.FullName "`$Recycle.Bin"
        & $addItem "System & Windows Junk" ("Recycle Bin ({0})" -f $dr.Name.TrimEnd('\')) $rbPath $true ("Deleted files stored in Recycle Bin on drive {0}" -f $dr.Name)
    }

    # =========================================================
    # CATEGORY 3: DYNAMIC APPDATA TREE SCAN (CACHES, SHADERS, LOGS)
    # =========================================================
    & $ProgressCallback "Deep Scanning AppData Tree for Application Caches & Shaders..." 38
    $cacheSubTargets = @(
        @{ Sub = "Cache"; Cat = "Browser & App Caches"; Desc = "Application web and media cache" },
        @{ Sub = "Code Cache"; Cat = "Browser & App Caches"; Desc = "Compiled JavaScript and WebAssembly bytecode cache" },
        @{ Sub = "GPUCache"; Cat = "GPU & Shader Caches"; Desc = "Hardware GPU texture and shader cache" },
        @{ Sub = "DawnGraphiteCache"; Cat = "GPU & Shader Caches"; Desc = "Dawn WebGPU compiled cache" },
        @{ Sub = "DawnWebGPUCache"; Cat = "GPU & Shader Caches"; Desc = "WebGPU shader pipeline cache" },
        @{ Sub = "ShaderCache"; Cat = "GPU & Shader Caches"; Desc = "Application compiled shader cache" },
        @{ Sub = "blob_storage"; Cat = "Browser & App Caches"; Desc = "Electron cached binary blobs" },
        @{ Sub = "logs"; Cat = "Logs & Crash Reports"; Desc = "Application runtime log files" },
        @{ Sub = "Crashpad"; Cat = "Logs & Crash Reports"; Desc = "Application crash reporting database" }
    )

    foreach ($uPath in $userProfiles) {
        $appDataRoots = @("$uPath\AppData\Local", "$uPath\AppData\Roaming")
        foreach ($base in $appDataRoots) {
            if (-not (Test-Path $base)) { continue }
            $firstLevel = Get-ChildItem -LiteralPath $base -Directory -Force -ErrorAction SilentlyContinue
            foreach ($fl in $firstLevel) {
                # Direct subdirectories (e.g. AppData\Local\App\Cache)
                foreach ($t in $cacheSubTargets) {
                    $targetPath = Join-Path $fl.FullName $t.Sub
                    if (Test-Path $targetPath) {
                        & $addItem $t.Cat ("{0} {1}" -f $fl.Name, $t.Sub) $targetPath $true $t.Desc
                    }
                }

                # Second-level subdirectories (e.g. AppData\Local\Google\Chrome\User Data\Default\Cache)
                $secondLevel = Get-ChildItem -LiteralPath $fl.FullName -Directory -Force -ErrorAction SilentlyContinue
                foreach ($sl in $secondLevel) {
                    foreach ($t in $cacheSubTargets) {
                        $targetPath = Join-Path $sl.FullName $t.Sub
                        if (Test-Path $targetPath) {
                            & $addItem $t.Cat ("{0}/{1} {2}" -f $fl.Name, $sl.Name, $t.Sub) $targetPath $true $t.Desc
                        }
                    }

                    # Check Chromium User Data\Default profile pattern
                    $defaultProfile = Join-Path $sl.FullName "User Data\Default"
                    if (Test-Path $defaultProfile) {
                        foreach ($t in $cacheSubTargets) {
                            $targetPath = Join-Path $defaultProfile $t.Sub
                            if (Test-Path $targetPath) {
                                & $addItem $t.Cat ("{0} ({1}) {2}" -f $fl.Name, $sl.Name, $t.Sub) $targetPath $true $t.Desc
                            }
                        }
                    }
                }
            }
        }

        # Specific known browser & media caches
        $extraGlobs = @(
            @{ Name = "Discord Media Cache"; Path = "$uPath\AppData\Roaming\discord\Cache" },
            @{ Name = "Discord Code Cache"; Path = "$uPath\AppData\Roaming\discord\Code Cache" },
            @{ Name = "Spotify Storage Cache"; Path = "$uPath\AppData\Local\Spotify\Storage" },
            @{ Name = "Telegram Desktop Cache"; Path = "$uPath\AppData\Roaming\Telegram Desktop\tdata\user_data" },
            @{ Name = "Steam Download Cache"; Path = "C:\Program Files (x86)\Steam\steamapps\downloading" }
        )
        foreach ($eg in $extraGlobs) {
            & $addItem "Browser & App Caches" $eg.Name $eg.Path $true "Cached media and application content"
        }

        # Mozilla Firefox cache
        $ffProfiles = "$uPath\AppData\Local\Mozilla\Firefox\Profiles"
        if (Test-Path -LiteralPath $ffProfiles) {
            Get-ChildItem -LiteralPath $ffProfiles -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $ffc = Join-Path $_.FullName "cache2"
                & $addItem "Browser & App Caches" "Mozilla Firefox Cache" $ffc $true "Firefox cached web content"
            }
        }
    }

    # =========================================================
    # CATEGORY 4: UNINSTALLED SOFTWARE RESIDUALS & UPDATER CACHES
    # =========================================================
    & $ProgressCallback "Analyzing Uninstalled Software Residuals & Updater Caches..." 55

    # 1. Collect installed application registry records for smart residual matching
    $installedSoftwareNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $uninstallRegKeys = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($rk in $uninstallRegKeys) {
        Get-ItemProperty $rk -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.DisplayName) { $installedSoftwareNames.Add($_.DisplayName) | Out-Null }
            if ($_.PSChildName) { $installedSoftwareNames.Add($_.PSChildName) | Out-Null }
        }
    }

    $systemIgnoreFolders = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    @("Microsoft", "Packages", "Windows", "Programs", "System32", "SysWOW64", "Android", "Google", "npm", "pip", "Temp", "CrashDumps", "D3DSCache", "NVIDIA", "Intel", "AMD", "uv", "Antigravity", "Windsurf", "Trae", "Local", "Roaming", "LocalLow", "Package Cache", "Application Data", "BraveSoftware", "Claude") | ForEach-Object { $systemIgnoreFolders.Add($_) | Out-Null }

    foreach ($uPath in $userProfiles) {
        $appRoots = @("$uPath\AppData\Local", "$uPath\AppData\Roaming")
        foreach ($ar in $appRoots) {
            if (-not (Test-Path $ar)) { continue }
            $folders = Get-ChildItem -LiteralPath $ar -Directory -Force -ErrorAction SilentlyContinue
            foreach ($dir in $folders) {
                $folderName = $dir.Name

                # A. Automatic detection of Electron & App updater caches (e.g. *-updater)
                if ($folderName -like "*-updater" -or $folderName -like "*updater-cache*") {
                    $sz = Get-FolderSizeFast -Path $dir.FullName
                    if ($sz -gt 5MB) {
                        & $addItem "Uninstalled Software Residuals" ("Updater Cache: {0}" -f $folderName) $dir.FullName $true "Stale auto-update installer package cache left behind by application" $sz
                    }
                    continue
                }

                # B. Skip core system and recognized tools
                if ($systemIgnoreFolders.Contains($folderName)) { continue }

                # C. Check if folder belongs to any currently registered installed software
                $matchedInstalled = $false
                foreach ($app in $installedSoftwareNames) {
                    if ($app.IndexOf($folderName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                        $folderName.IndexOf($app, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $matchedInstalled = $true
                        break
                    }
                }

                # D. If not registered, measure folder size; if > 15MB, present as candidate residual
                if (-not $matchedInstalled) {
                    $sz = Get-FolderSizeFast -Path $dir.FullName
                    if ($sz -gt 15MB) {
                        & $addItem "Uninstalled Software Residuals" ("Residual: {0}" -f $folderName) $dir.FullName $false "Data folder belonging to uninstalled, dormant, or portable application" $sz
                    }
                }
            }
        }

        # Downloaded Installations cache
        $downInst = "$uPath\AppData\Local\Downloaded Installations"
        & $addItem "Uninstalled Software Residuals" "Downloaded Installations Leftovers" $downInst $true "Cached setup packages left behind after software installations"
    }

    # ProgramData Package Cache
    if ($hasSystemDrive) {
        $pkgCache = "C:\ProgramData\Package Cache"
        if (Test-Path $pkgCache) {
            $sz = Get-FolderSizeFast -Path $pkgCache
            if ($sz -gt 50MB) {
                & $addItem "Uninstalled Software Residuals" "Visual Studio / MSI Package Cache" $pkgCache $false "Cached installer MSI packages for installed and updated tools" $sz
            }
        }
    }

    # =========================================================
    # CATEGORY 5: DEVELOPER & BUILD CACHES
    # =========================================================
    & $ProgressCallback "Scanning Developer Tools & Package Build Caches..." 70
    foreach ($uPath in $userProfiles) {
        $devCaches = @(
            @{ Name = "NPM Local Cache"; Path = "$uPath\AppData\Local\npm-cache"; Safe = $true; Desc = "NPM downloaded tarballs cache (auto-restored on npm install)" },
            @{ Name = "NPM Roaming Cache"; Path = "$uPath\AppData\Roaming\npm-cache"; Safe = $true; Desc = "NPM roaming metadata cache" },
            @{ Name = "Python PIP Wheel Cache"; Path = "$uPath\AppData\Local\pip\cache"; Safe = $true; Desc = "Cached Python pip wheels and download tarballs" },
            @{ Name = "uv Python Cache"; Path = "$uPath\AppData\Local\uv\cache"; Safe = $true; Desc = "uv package installer cache" },
            @{ Name = "Playwright Browser Binaries"; Path = "$uPath\AppData\Local\ms-playwright"; Safe = $true; Desc = "Bundled Chromium, Firefox, WebKit binaries for Playwright" },
            @{ Name = "Playwright Go Binaries"; Path = "$uPath\AppData\Local\ms-playwright-go"; Safe = $true; Desc = "Playwright Go browser binaries" },
            @{ Name = "Gradle Dependency Caches"; Path = "$uPath\.gradle\caches"; Safe = $true; Desc = "Java/Android Gradle build dependencies" },
            @{ Name = "Gradle Daemon Logs"; Path = "$uPath\.gradle\daemon"; Safe = $true; Desc = "Gradle background worker daemon logs" },
            @{ Name = "Maven Local Repository"; Path = "$uPath\.m2\repository"; Safe = $false; Desc = "Downloaded Java JARs & libraries" },
            @{ Name = "NuGet Package Cache"; Path = "$uPath\.nuget\packages"; Safe = $false; Desc = ".NET global library packages cache" },
            @{ Name = "Rust Cargo Registry"; Path = "$uPath\.cargo\registry"; Safe = $true; Desc = "Cargo downloaded crates and checkouts" },
            @{ Name = "Yarn Global Cache"; Path = "$uPath\AppData\Local\Yarn\Cache"; Safe = $true; Desc = "Yarn package cache" },
            @{ Name = "PNPM Global Store"; Path = "$uPath\AppData\Local\pnpm\store"; Safe = $true; Desc = "PNPM global package content store" },
            @{ Name = "Go Build Cache"; Path = "$uPath\AppData\Local\go-build"; Safe = $true; Desc = "Go compiler build cache" }
        )
        foreach ($dc in $devCaches) {
            & $addItem "Developer & Build Caches" $dc.Name $dc.Path $dc.Safe $dc.Desc
        }
    }

    # =========================================================
    # CATEGORY 6: AI & LOCAL LLM MODELS
    # =========================================================
    & $ProgressCallback "Scanning AI & Local LLM Models (Ollama, AnythingLLM, HuggingFace)..." 80
    foreach ($uPath in $userProfiles) {
        $aiCaches = @(
            @{ Name = "Ollama Models Blob Storage"; Path = "$uPath\.ollama\models"; Safe = $false; Desc = "Ollama model weight blobs" },
            @{ Name = "AnythingLLM Storage Engines"; Path = "$uPath\AppData\Roaming\anythingllm-desktop\storage\engines"; Safe = $false; Desc = "Local inference engines bundled with AnythingLLM" },
            @{ Name = "AnythingLLM Models"; Path = "$uPath\AppData\Roaming\anythingllm-desktop\storage\models"; Safe = $false; Desc = "Local AI models in AnythingLLM" },
            @{ Name = "Hugging Face Model Cache"; Path = "$uPath\.cache\huggingface"; Safe = $true; Desc = "Cached pretrained transformers models" },
            @{ Name = "PyTorch Model Checkpoints"; Path = "$uPath\.cache\torch"; Safe = $true; Desc = "PyTorch cached hub checkpoints" },
            @{ Name = "LM Studio Model Downloads"; Path = "$uPath\.cache\lm-studio"; Safe = $false; Desc = "LM Studio downloaded GGUF models" },
            @{ Name = "Colibri AI Models"; Path = "$uPath\colibri-models"; Safe = $false; Desc = "Downloaded safetensors model weights" }
        )
        foreach ($ai in $aiCaches) {
            & $addItem "AI & Local LLM Models" $ai.Name $ai.Path $ai.Safe $ai.Desc
        }
    }

    # =========================================================
    # CATEGORY 7: WSL & DOCKER VIRTUAL HARD DISKS (.vhdx)
    # =========================================================
    & $ProgressCallback "Scanning WSL & Docker Virtual Disks..." 88
    $lxssKeys = Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss" -ErrorAction SilentlyContinue
    foreach ($k in $lxssKeys) {
        $distro = (Get-ItemProperty $k.PSPath).DistributionName
        $basePath = (Get-ItemProperty $k.PSPath).BasePath
        if ($basePath) {
            $vhdx = Join-Path $basePath "ext4.vhdx"
            $vhdxDrive = ([System.IO.Path]::GetPathRoot($vhdx)).Substring(0,1).ToUpper()
            if ($selectedDriveLetters -contains $vhdxDrive -and (Test-Path -LiteralPath $vhdx)) {
                $fi = Get-Item -LiteralPath $vhdx -ErrorAction SilentlyContinue
                if ($fi) {
                    & $addItem "WSL & Virtual Disks" ("WSL Distro: {0}" -f $distro) $vhdx $false "WSL2 Virtual Hard Disk containing Linux OS & Docker data" $fi.Length
                }
            }
        }
    }
    # PC Manager WSL
    if ($selectedDriveLetters -contains "C") {
        $pcmVhdx = "C:\ProgramData\PCManager\WslClaw\ext4.vhdx"
        if (Test-Path -LiteralPath $pcmVhdx) {
            $fi = Get-Item -LiteralPath $pcmVhdx -ErrorAction SilentlyContinue
            if ($fi) {
                & $addItem "WSL & Virtual Disks" "PC Manager WSL Disk" $pcmVhdx $true "Virtual disk used by PC Manager background process" $fi.Length
            }
        }
    }
    # Docker Desktop Data VHDX
    foreach ($uPath in $userProfiles) {
        $dockerVhdx = "$uPath\AppData\Local\Docker\wsl\data\ext4.vhdx"
        if (Test-Path -LiteralPath $dockerVhdx) {
            $fi = Get-Item -LiteralPath $dockerVhdx -ErrorAction SilentlyContinue
            if ($fi) {
                & $addItem "WSL & Virtual Disks" "Docker Desktop Data VHDX" $dockerVhdx $false "Docker Desktop containers & image storage layer" $fi.Length
            }
        }
    }

    # =========================================================
    # CATEGORY 8: LARGE STALE ARCHIVES, INSTALLERS & FILES (>100MB)
    # =========================================================
    & $ProgressCallback "Scanning File System Tree for Large Forgotten Files (> 100 MB)..." 95
    $deepScanFolders = @()
    foreach ($dr in $drives) {
        $deepScanFolders += $dr.RootDirectory.FullName
    }
    foreach ($uPath in $userProfiles) {
        $deepScanFolders += (Join-Path $uPath "Downloads")
        $deepScanFolders += (Join-Path $uPath "Videos")
        $deepScanFolders += (Join-Path $uPath "Documents")
        $deepScanFolders += (Join-Path $uPath "Desktop")
    }

    $staleExtensions = @(".zip", ".rar", ".7z", ".iso", ".tar", ".gz", ".exe", ".msi", ".vhdx", ".vmdk", ".dmg", ".mkv", ".mp4")

    foreach ($folder in $deepScanFolders) {
        if (Test-Path -LiteralPath $folder) {
            try {
                $files = Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Length -gt 100MB }
                foreach ($f in $files) {
                    $ext = $f.Extension.ToLower()
                    if ($staleExtensions -contains $ext -or $f.Length -gt 500MB) {
                        # Protect Windows system page/hibernation files
                        if ($f.Name -in @("pagefile.sys", "swapfile.sys", "hiberfil.sys", "dumpstack.log")) {
                            continue
                        }
                        & $addItem "Large Stale Archives & Files" $f.Name $f.FullName $false ("Large file ({0:N2} GB) stored in {1}" -f ($f.Length/1GB), $f.DirectoryName) $f.Length
                    }
                }
            } catch {}
        }
    }

    & $ProgressCallback "Scan completed successfully!" 100
    return $itemsFound
}

# -------------------------------------------------------------
# 5. 10-SECOND SAFETY COUNTDOWN DIALOG
# -------------------------------------------------------------
function Show-SafetyCountdownDialog {
    param(
        [int]$ItemCount,
        [double]$TotalBytes,
        [System.Collections.Generic.List[PSCustomObject]]$SelectedItems
    )

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Safety Confirmation: Permanent Deletion"
    $dlg.Size = New-Object System.Drawing.Size(640, 510)
    $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

    # Top Warning Header
    $pnlHeader = New-Object System.Windows.Forms.Panel
    $pnlHeader.Dock = [System.Windows.Forms.DockStyle]::Top
    $pnlHeader.Height = 82
    $pnlHeader.BackColor = [System.Drawing.Color]::FromArgb(220, 38, 38)
    $pnlHeader.Padding = New-Object System.Windows.Forms.Padding(18, 12, 18, 12)
    $dlg.Controls.Add($pnlHeader)

    $lblWarnTitle = New-Object System.Windows.Forms.Label
    $lblWarnTitle.Text = "PERMANENT DELETION SCHEDULED"
    $lblWarnTitle.ForeColor = [System.Drawing.Color]::White
    $lblWarnTitle.Font = New-Object System.Drawing.Font("Segoe UI Bold", 13, [System.Drawing.FontStyle]::Bold)
    $lblWarnTitle.AutoSize = $true
    $lblWarnTitle.UseMnemonic = $false
    $lblWarnTitle.Location = New-Object System.Drawing.Point(18, 12)
    $pnlHeader.Controls.Add($lblWarnTitle)

    $lblWarnSub = New-Object System.Windows.Forms.Label
    $lblWarnSub.Text = "Selected files will be forcefully unlocked and permanently wiped without sending to Recycle Bin."
    $lblWarnSub.ForeColor = [System.Drawing.Color]::FromArgb(254, 226, 226)
    $lblWarnSub.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblWarnSub.AutoSize = $true
    $lblWarnSub.UseMnemonic = $false
    $lblWarnSub.Location = New-Object System.Drawing.Point(19, 44)
    $pnlHeader.Controls.Add($lblWarnSub)

    # Central Summary & Preview
    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Text = ("Items Selected: {0}   |   Total Disk Space to Reclaim: {1}" -f $ItemCount, (Format-FileSize $TotalBytes))
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10.5, [System.Drawing.FontStyle]::Bold)
    $lblSummary.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $lblSummary.Location = New-Object System.Drawing.Point(20, 96)
    $lblSummary.AutoSize = $true
    $lblSummary.UseMnemonic = $false
    $dlg.Controls.Add($lblSummary)

    $lstPreview = New-Object System.Windows.Forms.ListBox
    $lstPreview.Location = New-Object System.Drawing.Point(20, 125)
    $lstPreview.Size = New-Object System.Drawing.Size(585, 145)
    $lstPreview.Font = New-Object System.Drawing.Font("Consolas", 8.8)
    $lstPreview.BackColor = [System.Drawing.Color]::White
    $lstPreview.ForeColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
    foreach ($item in $SelectedItems) {
        $lstPreview.Items.Add(("{0,-20} | {1,-9} | {2}" -f $item.Category, $item.Size, $item.Name)) | Out-Null
    }
    $dlg.Controls.Add($lstPreview)

    # Countdown Display & Progress
    $lblCountdown = New-Object System.Windows.Forms.Label
    $lblCountdown.Text = "Permanent deletion starting automatically in 10 seconds..."
    $lblCountdown.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11, [System.Drawing.FontStyle]::Bold)
    $lblCountdown.ForeColor = [System.Drawing.Color]::FromArgb(185, 28, 28)
    $lblCountdown.Location = New-Object System.Drawing.Point(20, 282)
    $lblCountdown.AutoSize = $true
    $lblCountdown.UseMnemonic = $false
    $dlg.Controls.Add($lblCountdown)

    $pBarTimer = New-Object System.Windows.Forms.ProgressBar
    $pBarTimer.Location = New-Object System.Drawing.Point(20, 312)
    $pBarTimer.Size = New-Object System.Drawing.Size(585, 14)
    $pBarTimer.Maximum = 100
    $pBarTimer.Value = 100
    $pBarTimer.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $dlg.Controls.Add($pBarTimer)

    # Action Buttons
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "STOP & CANCEL (I want to review)"
    $btnCancel.Size = New-Object System.Drawing.Size(330, 46)
    $btnCancel.Location = New-Object System.Drawing.Point(20, 350)
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
    $btnCancel.ForeColor = [System.Drawing.Color]::White
    $btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCancel.FlatAppearance.BorderSize = 0
    $btnCancel.Font = New-Object System.Drawing.Font("Segoe UI Bold", 10.5, [System.Drawing.FontStyle]::Bold)
    $btnCancel.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnCancel.UseMnemonic = $false
    $dlg.Controls.Add($btnCancel)

    $btnProceed = New-Object System.Windows.Forms.Button
    $btnProceed.Text = "Delete Now (Skip Timer)"
    $btnProceed.Size = New-Object System.Drawing.Size(245, 46)
    $btnProceed.Location = New-Object System.Drawing.Point(360, 350)
    $btnProceed.BackColor = [System.Drawing.Color]::FromArgb(220, 38, 38)
    $btnProceed.ForeColor = [System.Drawing.Color]::White
    $btnProceed.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnProceed.FlatAppearance.BorderSize = 0
    $btnProceed.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5, [System.Drawing.FontStyle]::Bold)
    $btnProceed.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnProceed.UseMnemonic = $false
    $dlg.Controls.Add($btnProceed)

    $script:remainingSeconds = 10.0
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 100

    $timer.Add_Tick({
        $script:remainingSeconds -= 0.1
        if ($script:remainingSeconds -le 0) {
            $timer.Stop()
            $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dlg.Close()
        } else {
            $secsLeft = [math]::Ceiling($script:remainingSeconds)
            $lblCountdown.Text = ("Permanent deletion starting automatically in {0} seconds..." -f $secsLeft)
            $pct = [int](($script:remainingSeconds / 10.0) * 100)
            $pBarTimer.Value = [math]::Max(0, [math]::Min(100, $pct))
        }
    })

    $btnCancel.Add_Click({
        $timer.Stop()
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dlg.Close()
    })

    $btnProceed.Add_Click({
        $timer.Stop()
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dlg.Close()
    })

    $dlg.Add_Shown({ $timer.Start() })
    $dlg.Add_FormClosing({ $timer.Stop() })

    return $dlg.ShowDialog()
}

# -------------------------------------------------------------
# 6. MODERN WINDOWS FORMS USER INTERFACE
# -------------------------------------------------------------
function Show-CleanerGUI {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Universal System Disk Cleaner & Deep Storage Analyzer"
    $form.Size = New-Object System.Drawing.Size(1240, 840)
    $form.MinimumSize = New-Object System.Drawing.Size(1040, 700)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

    $script:allScanResults = New-Object System.Collections.Generic.List[PSCustomObject]

    # =========================================================
    # MASTER TOP CONTAINER (Height = 192px, Dock = Top)
    # Holds Row 1 (Header), Row 2 (Drives), Row 3 (Toolbar)
    # =========================================================
    $masterTopContainer = New-Object System.Windows.Forms.Panel
    $masterTopContainer.Dock = [System.Windows.Forms.DockStyle]::Top
    $masterTopContainer.Height = 192
    $masterTopContainer.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
    $form.Controls.Add($masterTopContainer)

    # --- ROW 1: DARK NAVY HEADER (Y=0, H=68) ---
    $rowHeader = New-Object System.Windows.Forms.Panel
    $rowHeader.Location = New-Object System.Drawing.Point(0, 0)
    $rowHeader.Size = New-Object System.Drawing.Size(1240, 68)
    $rowHeader.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $rowHeader.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
    $masterTopContainer.Controls.Add($rowHeader)

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "Universal Multi-Drive Storage Cleaner & Process Unlocker"
    $titleLabel.ForeColor = [System.Drawing.Color]::White
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 13.5, [System.Drawing.FontStyle]::Bold)
    $titleLabel.AutoSize = $true
    $titleLabel.UseMnemonic = $false
    $titleLabel.Location = New-Object System.Drawing.Point(18, 9)
    $rowHeader.Controls.Add($titleLabel)

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(20, 42)
    $progressBar.Size = New-Object System.Drawing.Size(520, 16)
    $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $progressBar.Value = 0
    $rowHeader.Controls.Add($progressBar)

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = "Ready. Select target drives below, then click 'Deep Scan Selected Drives'."
    $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
    $statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $statusLabel.AutoSize = $true
    $statusLabel.UseMnemonic = $false
    $statusLabel.Location = New-Object System.Drawing.Point(555, 41)
    $rowHeader.Controls.Add($statusLabel)

    # --- ROW 2: DEDICATED DRIVE SELECTION PANEL (Y=68, H=68) ---
    $rowDrives = New-Object System.Windows.Forms.Panel
    $rowDrives.Location = New-Object System.Drawing.Point(0, 68)
    $rowDrives.Size = New-Object System.Drawing.Size(1240, 68)
    $rowDrives.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $rowDrives.BackColor = [System.Drawing.Color]::FromArgb(255, 255, 255)
    $masterTopContainer.Controls.Add($rowDrives)

    $lblDriveHeader = New-Object System.Windows.Forms.Label
    $lblDriveHeader.Text = "TARGET DRIVES FOR DEEP STRUCTURAL SCAN:"
    $lblDriveHeader.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9, [System.Drawing.FontStyle]::Bold)
    $lblDriveHeader.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
    $lblDriveHeader.Location = New-Object System.Drawing.Point(18, 8)
    $lblDriveHeader.AutoSize = $true
    $lblDriveHeader.UseMnemonic = $false
    $rowDrives.Controls.Add($lblDriveHeader)

    $flowDrives = New-Object System.Windows.Forms.FlowLayoutPanel
    $flowDrives.Location = New-Object System.Drawing.Point(18, 28)
    $flowDrives.Size = New-Object System.Drawing.Size(690, 36)
    $flowDrives.AutoScroll = $false
    $flowDrives.WrapContents = $false
    $rowDrives.Controls.Add($flowDrives)

    $detectedFixedDrives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -eq [System.IO.DriveType]::Fixed }
    foreach ($d in $detectedFixedDrives) {
        $chkDrive = New-Object System.Windows.Forms.CheckBox
        $free = [math]::Round($d.TotalFreeSpace / 1GB, 1)
        $tot = [math]::Round($d.TotalSize / 1GB, 1)
        $vLabel = if ($d.VolumeLabel) { $d.VolumeLabel } else { if ($d.Name -like "C:*") { "System" } else { "Data Disk" } }
        $chkDrive.Text = ("[{0}] {1}  ({2} GB Free / {3} GB)" -f $d.Name.TrimEnd('\'), $vLabel, $free, $tot)
        $chkDrive.Tag = $d.Name
        $chkDrive.Checked = $true
        $chkDrive.AutoSize = $true
        $chkDrive.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5, [System.Drawing.FontStyle]::Bold)
        $chkDrive.ForeColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
        $chkDrive.Padding = New-Object System.Windows.Forms.Padding(0, 2, 16, 2)
        $chkDrive.Cursor = [System.Windows.Forms.Cursors]::Hand
        $chkDrive.UseMnemonic = $false
        $flowDrives.Controls.Add($chkDrive)
    }

    # Dedicated panel for Drive Buttons to prevent any overlap
    $panelDriveButtons = New-Object System.Windows.Forms.Panel
    $panelDriveButtons.Location = New-Object System.Drawing.Point(720, 14)
    $panelDriveButtons.Size = New-Object System.Drawing.Size(500, 42)
    $panelDriveButtons.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $rowDrives.Controls.Add($panelDriveButtons)

    $btnScanDrives = New-Object System.Windows.Forms.Button
    $btnScanDrives.Text = "Deep Scan Selected Drives"
    $btnScanDrives.Size = New-Object System.Drawing.Size(225, 36)
    $btnScanDrives.Location = New-Object System.Drawing.Point(10, 2)
    $btnScanDrives.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
    $btnScanDrives.ForeColor = [System.Drawing.Color]::White
    $btnScanDrives.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnScanDrives.FlatAppearance.BorderSize = 0
    $btnScanDrives.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9.5, [System.Drawing.FontStyle]::Bold)
    $btnScanDrives.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnScanDrives.UseMnemonic = $false
    $panelDriveButtons.Controls.Add($btnScanDrives)

    $btnAllDrives = New-Object System.Windows.Forms.Button
    $btnAllDrives.Text = "Check All"
    $btnAllDrives.Size = New-Object System.Drawing.Size(88, 36)
    $btnAllDrives.Location = New-Object System.Drawing.Point(245, 2)
    $btnAllDrives.BackColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
    $btnAllDrives.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnAllDrives.FlatAppearance.BorderSize = 0
    $btnAllDrives.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnAllDrives.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnAllDrives.UseMnemonic = $false
    $panelDriveButtons.Controls.Add($btnAllDrives)

    $btnNoDrives = New-Object System.Windows.Forms.Button
    $btnNoDrives.Text = "Clear"
    $btnNoDrives.Size = New-Object System.Drawing.Size(70, 36)
    $btnNoDrives.Location = New-Object System.Drawing.Point(342, 2)
    $btnNoDrives.BackColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
    $btnNoDrives.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnNoDrives.FlatAppearance.BorderSize = 0
    $btnNoDrives.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnNoDrives.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnNoDrives.UseMnemonic = $false
    $panelDriveButtons.Controls.Add($btnNoDrives)

    # --- ROW 3: ACTION PRESETS & SEARCH TOOLBAR (Y=136, H=56) ---
    $rowToolbar = New-Object System.Windows.Forms.Panel
    $rowToolbar.Location = New-Object System.Drawing.Point(0, 136)
    $rowToolbar.Size = New-Object System.Drawing.Size(1240, 56)
    $rowToolbar.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $rowToolbar.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
    $masterTopContainer.Controls.Add($rowToolbar)

    # Left Preset Buttons
    $btnSelectSafe = New-Object System.Windows.Forms.Button
    $btnSelectSafe.Text = "Select Safe Junk (Temp/Caches)"
    $btnSelectSafe.Size = New-Object System.Drawing.Size(230, 34)
    $btnSelectSafe.Location = New-Object System.Drawing.Point(18, 10)
    $btnSelectSafe.BackColor = [System.Drawing.Color]::FromArgb(22, 163, 74)
    $btnSelectSafe.ForeColor = [System.Drawing.Color]::White
    $btnSelectSafe.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSelectSafe.FlatAppearance.BorderSize = 0
    $btnSelectSafe.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
    $btnSelectSafe.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnSelectSafe.UseMnemonic = $false
    $rowToolbar.Controls.Add($btnSelectSafe)

    $btnSelectAll = New-Object System.Windows.Forms.Button
    $btnSelectAll.Text = "Select All"
    $btnSelectAll.Size = New-Object System.Drawing.Size(100, 34)
    $btnSelectAll.Location = New-Object System.Drawing.Point(256, 10)
    $btnSelectAll.BackColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
    $btnSelectAll.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSelectAll.FlatAppearance.BorderSize = 0
    $btnSelectAll.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnSelectAll.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnSelectAll.UseMnemonic = $false
    $rowToolbar.Controls.Add($btnSelectAll)

    $btnDeselectAll = New-Object System.Windows.Forms.Button
    $btnDeselectAll.Text = "Deselect All"
    $btnDeselectAll.Size = New-Object System.Drawing.Size(105, 34)
    $btnDeselectAll.Location = New-Object System.Drawing.Point(364, 10)
    $btnDeselectAll.BackColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
    $btnDeselectAll.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnDeselectAll.FlatAppearance.BorderSize = 0
    $btnDeselectAll.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnDeselectAll.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnDeselectAll.UseMnemonic = $false
    $rowToolbar.Controls.Add($btnDeselectAll)

    # Right-anchored Search Panel (Immune to Overlapping)
    $panelFilter = New-Object System.Windows.Forms.Panel
    $panelFilter.Location = New-Object System.Drawing.Point(780, 8)
    $panelFilter.Size = New-Object System.Drawing.Size(440, 38)
    $panelFilter.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $rowToolbar.Controls.Add($panelFilter)

    $filterLabel = New-Object System.Windows.Forms.Label
    $filterLabel.Text = "Filter Search:"
    $filterLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
    $filterLabel.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
    $filterLabel.AutoSize = $true
    $filterLabel.UseMnemonic = $false
    $filterLabel.Location = New-Object System.Drawing.Point(10, 10)
    $panelFilter.Controls.Add($filterLabel)

    $txtFilter = New-Object System.Windows.Forms.TextBox
    $txtFilter.Size = New-Object System.Drawing.Size(310, 26)
    $txtFilter.Location = New-Object System.Drawing.Point(115, 6)
    $txtFilter.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $panelFilter.Controls.Add($txtFilter)

    # --- BOTTOM PANEL: SUMMARY, ACTION BUTTON & LIVE CONSOLE ---
    $bottomPanel = New-Object System.Windows.Forms.Panel
    $bottomPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $bottomPanel.Height = 185
    $bottomPanel.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
    $bottomPanel.Padding = New-Object System.Windows.Forms.Padding(18, 10, 18, 10)
    $form.Controls.Add($bottomPanel)

    $selectionSummaryLabel = New-Object System.Windows.Forms.Label
    $selectionSummaryLabel.Text = "Selected: 0 items   |   Total Disk Space to Reclaim: 0.00 GB"
    $selectionSummaryLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11, [System.Drawing.FontStyle]::Bold)
    $selectionSummaryLabel.ForeColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
    $selectionSummaryLabel.AutoSize = $true
    $selectionSummaryLabel.UseMnemonic = $false
    $selectionSummaryLabel.Location = New-Object System.Drawing.Point(18, 14)
    $bottomPanel.Controls.Add($selectionSummaryLabel)

    $btnDelete = New-Object System.Windows.Forms.Button
    $btnDelete.Text = "Force-Stop Locking Processes & Delete Selected"
    $btnDelete.Size = New-Object System.Drawing.Size(450, 40)
    $btnDelete.Location = New-Object System.Drawing.Point(750, 8)
    $btnDelete.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnDelete.BackColor = [System.Drawing.Color]::FromArgb(220, 38, 38)
    $btnDelete.ForeColor = [System.Drawing.Color]::White
    $btnDelete.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnDelete.FlatAppearance.BorderSize = 0
    $btnDelete.Font = New-Object System.Drawing.Font("Segoe UI Bold", 10, [System.Drawing.FontStyle]::Bold)
    $btnDelete.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnDelete.UseMnemonic = $false
    $bottomPanel.Controls.Add($btnDelete)

    $txtLog = New-Object System.Windows.Forms.TextBox
    $txtLog.Multiline = $true
    $txtLog.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $txtLog.ReadOnly = $true
    $txtLog.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
    $txtLog.ForeColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
    $txtLog.Font = New-Object System.Drawing.Font("Consolas", 8.8)
    $txtLog.Location = New-Object System.Drawing.Point(18, 56)
    $txtLog.Size = New-Object System.Drawing.Size(1185, 115)
    $txtLog.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $bottomPanel.Controls.Add($txtLog)

    # --- CENTER GRID VIEW: STRUCTURE TREE & CLEANUP ITEMS ---
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = [System.Windows.Forms.DockStyle]::Fill
    $grid.BackgroundColor = [System.Drawing.Color]::White
    $grid.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $grid.RowHeadersVisible = $false
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $grid.MultiSelect = $true
    $grid.AutoSizeRowsMode = [System.Windows.Forms.DataGridViewAutoSizeRowsMode]::AllCells
    $grid.ColumnHeadersHeight = 36
    $grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
    $grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5, [System.Drawing.FontStyle]::Bold)
    $grid.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)
    $grid.EnableHeadersVisualStyles = $false

    # Double buffer to eliminate flicker
    $type = $grid.GetType()
    $prop = $type.GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic)
    if ($prop) { $prop.SetValue($grid, $true, $null) }

    # Columns
    $colCheck = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $colCheck.HeaderText = "Select"
    $colCheck.Width = 55
    $grid.Columns.Add($colCheck) | Out-Null

    $colCat = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colCat.HeaderText = "Category"
    $colCat.Width = 190
    $colCat.ReadOnly = $true
    $grid.Columns.Add($colCat) | Out-Null

    $colName = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colName.HeaderText = "Item / Component Name"
    $colName.Width = 240
    $colName.ReadOnly = $true
    $grid.Columns.Add($colName) | Out-Null

    $colSize = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colSize.HeaderText = "Size"
    $colSize.Width = 105
    $colSize.ReadOnly = $true
    $grid.Columns.Add($colSize) | Out-Null

    $colDesc = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colDesc.HeaderText = "Description & Purpose"
    $colDesc.Width = 280
    $colDesc.ReadOnly = $true
    $grid.Columns.Add($colDesc) | Out-Null

    $colPath = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colPath.HeaderText = "Full File System Path"
    $colPath.Width = 360
    $colPath.ReadOnly = $true
    $grid.Columns.Add($colPath) | Out-Null

    $form.Controls.Add($grid)
    $grid.BringToFront()

    # --- UI EVENT HELPERS ---
    $AppendLog = {
        param([string]$Message)
        $timestamp = (Get-Date).ToString("HH:mm:ss")
        $txtLog.AppendText(("[" + $timestamp + "] " + $Message + "`r`n"))
        $txtLog.SelectionStart = $txtLog.TextLength
        $txtLog.ScrollToCaret()
        try { [System.Windows.Forms.Application]::DoEvents() } catch {}
    }

    $UpdateSummary = {
        $count = 0
        $totalBytes = 0
        foreach ($row in $grid.Rows) {
            if ($row.Cells[0].Value -eq $true) {
                $count++
                $tag = $row.Tag
                if ($tag -and $tag.SizeBytes) {
                    $totalBytes += $tag.SizeBytes
                }
            }
        }
        $selectionSummaryLabel.Text = ("Selected: " + $count + " items   |   Total Disk Space to Reclaim: " + (Format-FileSize $totalBytes))
    }

    $RefreshGridWithFilter = {
        $filter = $txtFilter.Text.Trim().ToLower()
        $grid.Rows.Clear()
        foreach ($item in $script:allScanResults) {
            if ($filter -ne "") {
                $match = ($item.Name.ToLower().Contains($filter)) -or
                         ($item.Category.ToLower().Contains($filter)) -or
                         ($item.Path.ToLower().Contains($filter))
                if (-not $match) { continue }
            }
            $rowIndex = $grid.Rows.Add($item.Selected, $item.Category, $item.Name, $item.Size, $item.Description, $item.Path)
            $grid.Rows[$rowIndex].Tag = $item
        }
        & $UpdateSummary
    }

    $grid.Add_CellContentClick({
        param($sender, $e)
        if ($e.ColumnIndex -eq 0 -and $e.RowIndex -ge 0) {
            $grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
            & $UpdateSummary
        }
    })

    $txtFilter.Add_TextChanged({
        & $RefreshGridWithFilter
    })

    $btnSelectAll.Add_Click({
        foreach ($row in $grid.Rows) { $row.Cells[0].Value = $true }
        & $UpdateSummary
    })

    $btnDeselectAll.Add_Click({
        foreach ($row in $grid.Rows) { $row.Cells[0].Value = $false }
        & $UpdateSummary
    })

    $btnSelectSafe.Add_Click({
        $safeCategories = @("System & Windows Junk", "GPU & Shader Caches", "Browser & App Caches", "Logs & Crash Reports", "Uninstalled Software Residuals")
        foreach ($row in $grid.Rows) {
            $tag = $row.Tag
            if ($tag -and ($safeCategories -contains $tag.Category)) {
                $row.Cells[0].Value = $true
            } else {
                $row.Cells[0].Value = $false
            }
        }
        & $UpdateSummary
    })

    # --- DRIVE SELECTION BUTTON ACTIONS ---
    $btnAllDrives.Add_Click({
        foreach ($ctrl in $flowDrives.Controls) {
            if ($ctrl -is [System.Windows.Forms.CheckBox]) { $ctrl.Checked = $true }
        }
    })

    $btnNoDrives.Add_Click({
        foreach ($ctrl in $flowDrives.Controls) {
            if ($ctrl -is [System.Windows.Forms.CheckBox]) { $ctrl.Checked = $false }
        }
    })

    # --- SCAN BUTTON ACTION ---
    $btnScanDrives.Add_Click({
        $selectedDrives = @()
        foreach ($ctrl in $flowDrives.Controls) {
            if ($ctrl -is [System.Windows.Forms.CheckBox] -and $ctrl.Checked) {
                $selectedDrives += $ctrl.Tag
            }
        }

        if ($selectedDrives.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "Please check at least one drive in the 'TARGET DRIVES' section before scanning.",
                "No Drive Selected",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            return
        }

        $btnScanDrives.Enabled = $false
        $btnDelete.Enabled = $false
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        $progressBar.Value = 0
        & $AppendLog ("Initiating deep structural tree scan on target drives: " + ($selectedDrives -join ", "))

        $progCallback = {
            param([string]$status, [int]$pct)
            $statusLabel.Text = $status
            $progressBar.Value = [math]::Min(100, [math]::Max(0, $pct))
            & $AppendLog $status
        }

        $results = Start-SystemDeepScan -SelectedDrives $selectedDrives -ProgressCallback $progCallback
        $script:allScanResults = $results

        & $RefreshGridWithFilter
        $btnScanDrives.Enabled = $true
        $btnDelete.Enabled = $true
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        $statusLabel.Text = ("Scan Complete! Found " + $results.Count + " cleanable items on " + ($selectedDrives -join ", ") + ".")
        & $AppendLog ("Deep structural tree scan finished. " + $results.Count + " items analyzed across selected drives.")
    })

    # --- PERMANENT DELETION WITH 10-SECOND SAFETY COUNTDOWN ---
    $btnDelete.Add_Click({
        $selectedRows = @()
        $selectedItemsList = [System.Collections.Generic.List[PSCustomObject]]::new()
        $totalBytes = 0

        foreach ($row in $grid.Rows) {
            if ($row.Cells[0].Value -eq $true) {
                $selectedRows += $row
                $tag = $row.Tag
                if ($tag) {
                    $selectedItemsList.Add($tag)
                    if ($tag.SizeBytes) { $totalBytes += $tag.SizeBytes }
                }
            }
        }

        if ($selectedRows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "No items are selected for deletion. Please check the items in the table you wish to permanently remove.",
                "Nothing Selected",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            return
        }

        # Launch 10-second safety window
        $safetyChoice = Show-SafetyCountdownDialog -ItemCount $selectedRows.Count -TotalBytes $totalBytes -SelectedItems $selectedItemsList

        if ($safetyChoice -ne [System.Windows.Forms.DialogResult]::OK) {
            & $AppendLog "Permanent deletion CANCELLED by user in safety window. No files were touched."
            return
        }

        $btnScanDrives.Enabled = $false
        $btnDelete.Enabled = $false
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        & $AppendLog "================ STARTING ZERO-TRACE CLEANUP ================"

        $successCount = 0
        $reclaimedBytes = 0

        for ($i = 0; $i -lt $selectedRows.Count; $i++) {
            $row = $selectedRows[$i]
            $item = $row.Tag
            $path = $item.Path
            $cat = $item.Category

            $pct = [int](($i / $selectedRows.Count) * 100)
            $progressBar.Value = $pct
            $statusLabel.Text = ("Deleting [" + ($i+1) + "/" + $selectedRows.Count + "]: " + $item.Name + "...")

            try { [System.Windows.Forms.Application]::DoEvents() } catch {}

            & $AppendLog ("Unlocking & stopping processes for: " + $item.Name)
            Stop-LockingProcessesForPath -TargetCategory $cat -TargetPath $path -LogCallback $AppendLog

            & $AppendLog ("Permanently removing: " + $path)
            $deleted = Remove-ItemCompletely -Path $path -LogCallback $AppendLog

            try { [System.Windows.Forms.Application]::DoEvents() } catch {}

            if ($deleted) {
                $successCount++
                $reclaimedBytes += $item.SizeBytes
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(220, 252, 231) # soft green
                $row.Cells[0].Value = $false
            } else {
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(254, 226, 226) # soft red
            }
        }

        $progressBar.Value = 100
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        $statusLabel.Text = ("Finished! Cleaned " + $successCount + " items. Reclaimed " + (Format-FileSize $reclaimedBytes) + ".")
        & $AppendLog "================ CLEANUP FINISHED ================"
        & $AppendLog ("Successfully wiped " + $successCount + " of " + $selectedRows.Count + " items.")
        & $AppendLog ("Total storage reclaimed: " + (Format-FileSize $reclaimedBytes) + ".")

        [System.Windows.Forms.MessageBox]::Show(
            ("Cleanup complete!`r`n`r`nSuccessfully removed: " + $successCount + " items`r`nTotal disk space reclaimed: " + (Format-FileSize $reclaimedBytes)),
            "Cleanup Finished",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )

        $btnScanDrives.Enabled = $true
        $btnDelete.Enabled = $true
        & $UpdateSummary
    })

    # Auto-trigger scan on startup with all checked drives
    $form.Add_Shown({
        $btnScanDrives.PerformClick()
    })

    [void]$form.ShowDialog()
}

# -------------------------------------------------------------
# 7. CLI FALLBACK MODE
# -------------------------------------------------------------
function Start-CliMode {
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "   Universal Multi-Drive Storage Cleaner (CLI Mode)       " -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan

    $allDrives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -eq [System.IO.DriveType]::Fixed }
    $driveNames = $allDrives | ForEach-Object { $_.Name.TrimEnd('\') }
    Write-Host ("Detected Fixed Drives: " + ($driveNames -join ", ")) -ForegroundColor White
    Write-Host "Enter drives to scan (e.g. C, D) or press Enter to scan all drives:" -ForegroundColor Cyan
    $chosenDrives = Read-Host "Drives"
    $drivesToScan = @()
    if (-not [string]::IsNullOrWhiteSpace($chosenDrives)) {
        $drivesToScan = $chosenDrives.Split(",") | ForEach-Object { $_.Trim().ToUpper() + ":\" }
    }

    $prog = { param($s, $p) Write-Host ("[" + $p + "%] " + $s) -ForegroundColor DarkGray }
    $items = Start-SystemDeepScan -SelectedDrives $drivesToScan -ProgressCallback $prog

    if ($items.Count -eq 0) {
        Write-Host "No unnecessary files or caches found." -ForegroundColor Green
        return
    }

    Write-Host ("`nScan Complete. Found " + $items.Count + " cleanable items:") -ForegroundColor Yellow
    $index = 1
    foreach ($it in $items) {
        $line = "[{0,2}] {1,-26} | {2,-10} | {3}" -f $index, $it.Category, $it.Size, $it.Name
        Write-Host $line -ForegroundColor White
        Write-Host ("     Path: " + $it.Path) -ForegroundColor DarkGray
        $index++
    }

    Write-Host "`nEnter item numbers to permanently delete (e.g. 1,3,5), 'all' for all, or 'q' to quit:" -ForegroundColor Cyan
    $choice = Read-Host "Selection"
    if ($choice -ieq 'q' -or [string]::IsNullOrWhiteSpace($choice)) { return }

    $toDelete = @()
    if ($choice -ieq 'all') {
        $toDelete = $items
    } else {
        $indices = $choice.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
        foreach ($idx in $indices) {
            if ($idx -ge 1 -and $idx -le $items.Count) {
                $toDelete += $items[$idx - 1]
            }
        }
    }

    if ($toDelete.Count -eq 0) {
        Write-Host "No valid items selected." -ForegroundColor Yellow
        return
    }

    Write-Host "`n10-Second Safety Countdown started. Press Ctrl+C to abort..." -ForegroundColor Yellow
    for ($sec = 10; $sec -gt 0; $sec--) {
        Write-Host ("Deleting in {0} seconds..." -f $sec) -ForegroundColor Red
        Start-Sleep -Seconds 1
    }

    Write-Host ("`nPermanently removing " + $toDelete.Count + " items...") -ForegroundColor Red
    $logCb = { param($m) Write-Host $m -ForegroundColor Gray }
    foreach ($it in $toDelete) {
        Stop-LockingProcessesForPath -TargetCategory $it.Category -TargetPath $it.Path -LogCallback $logCb
        Remove-ItemCompletely -Path $it.Path -LogCallback $logCb
    }
    Write-Host "Finished CLI cleanup." -ForegroundColor Green
}

# -------------------------------------------------------------
# 8. SCRIPT ENTRY POINT
# -------------------------------------------------------------
if ($ExportFunctionsOnly) {
    return
} elseif ($NoGui) {
    Start-CliMode
} else {
    Show-CleanerGUI
}
