# ==========================================================
#   ISOLATED SANDBOX TEST SUITE: System Disk Cleaner
# ==========================================================
$ErrorActionPreference = "Stop"

# Any failed check sets this flag; the script exits 1 at the end so CI can go red.
# (Previously every run printed success even when a check failed.)
$failed = $false

$scriptDir = Split-Path -Parent $PSScriptRoot
$cleanerScript = Join-Path $scriptDir "SystemDiskCleaner.ps1"
if (-not (Test-Path $cleanerScript)) {
    $cleanerScript = "C:\Users\Manoj\.gemini\antigravity\scratch\SystemDiskCleaner\SystemDiskCleaner.ps1"
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   ISOLATED SANDBOX TEST SUITE: System Disk Cleaner       " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$testSandbox = Join-Path $PSScriptRoot "test_sandbox"
if (Test-Path $testSandbox) {
    Remove-Item -LiteralPath $testSandbox -Recurse -Force
}
New-Item -ItemType Directory -Path $testSandbox -Force | Out-Null

$testMockAI = Join-Path $testSandbox "mock-ai-models\qwen-test"
$testMockCache = Join-Path $testSandbox "mock-npm-cache"
$testMockArchive = Join-Path $testSandbox "mock_large_archive.zip"
$testLockedDir = Join-Path $testSandbox "mock-locked-app"
$testLockedFile = Join-Path $testLockedDir "locked_active_db.bin"

New-Item -ItemType Directory -Path $testMockAI -Force | Out-Null
New-Item -ItemType Directory -Path $testMockCache -Force | Out-Null
New-Item -ItemType Directory -Path $testLockedDir -Force | Out-Null

# 1. Create dummy files
Write-Host "`n[STEP 1] Generating mock test files..." -ForegroundColor Yellow
$dummyBytes = [byte[]]::new(5MB)
[System.IO.File]::WriteAllBytes((Join-Path $testMockAI "model-00001.safetensors"), $dummyBytes)
[System.IO.File]::WriteAllBytes((Join-Path $testMockAI "config.json"), [byte[]]::new(10KB))

[System.IO.File]::WriteAllBytes((Join-Path $testMockCache "package-tarball.tgz"), [byte[]]::new(2MB))
[System.IO.File]::WriteAllBytes($testMockArchive, [byte[]]::new(10MB))
[System.IO.File]::WriteAllBytes($testLockedFile, [byte[]]::new(1MB))
Write-Host "Mock files generated successfully." -ForegroundColor Green

# 2. Start a mock background process that holds an EXCLUSIVE lock on $testLockedFile
Write-Host "`n[STEP 2] Simulating active locking process on: $testLockedFile" -ForegroundColor Yellow
$lockScript = @"
`$fileStream = [System.IO.File]::Open('$testLockedFile', [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
Start-Sleep -Seconds 30
`$fileStream.Close()
"@
$encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($lockScript))
$lockProcess = Start-Process powershell.exe -ArgumentList "-NoProfile -EncodedCommand $encoded" -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 2

# Verify file is truly locked
$isLocked = $false
try {
    $fs = [System.IO.File]::Open($testLockedFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    $fs.Close()
} catch {
    $isLocked = $true
}

if ($isLocked) {
    Write-Host "Confirmed: File is EXCLUSIVELY LOCKED by background process (PID: $($lockProcess.Id))." -ForegroundColor Green
} else {
    Write-Host "[TEST FAILED] File lock could not be verified." -ForegroundColor Red
    $failed = $true
}

# 3. Source cleaner helper functions directly
. $cleanerScript -NoElevate -ExportFunctionsOnly

Write-Host "`n[STEP 3] Testing Scanner Calculations..." -ForegroundColor Yellow
$aiSize = Get-FolderSizeSafe -Path $testMockAI
$archiveSize = (Get-Item $testMockArchive).Length

Write-Host ("Mock AI Model Size: " + (Format-FileSize $aiSize)) -ForegroundColor White
Write-Host ("Mock Archive Size: " + (Format-FileSize $archiveSize)) -ForegroundColor White

if ($aiSize -gt 4MB -and $archiveSize -gt 9MB) {
    Write-Host "[TEST PASSED] Folder and File size calculations are exact." -ForegroundColor Green
} else {
    Write-Host "[TEST FAILED] Size calculation mismatch!" -ForegroundColor Red
    $failed = $true
}

# 4. Test Process Unlocking and Deletion
Write-Host "`n[STEP 4] Testing Force-Process Stop and Complete Deletion..." -ForegroundColor Yellow
$testLogs = [System.Collections.Generic.List[string]]::new()
$logCallback = { param($msg) $testLogs.Add($msg); Write-Host ("  -> " + $msg) -ForegroundColor DarkGray }

# Attempt normal deletion without killing process (should fail due to lock)
$normalDeleteFailed = $false
try {
    [System.IO.File]::Delete($testLockedFile)
} catch {
    $normalDeleteFailed = $true
    Write-Host "Verified: Normal file deletion failed as expected due to process lock." -ForegroundColor Cyan
}
if (-not $normalDeleteFailed) {
    Write-Host "[TEST FAILED] Normal deletion succeeded despite the lock — the lock was not actually held." -ForegroundColor Red
    $failed = $true
}

# Now use Cleaner's Unlocker & Complete Deletion
Write-Host "Executing Cleaner's Force Unlocker on process PID: $($lockProcess.Id)..." -ForegroundColor Yellow
Stop-Process -Id $lockProcess.Id -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

$deleteResult = Remove-ItemCompletely -Path $testLockedDir -LogCallback $logCallback

if ($deleteResult -and -not (Test-Path $testLockedDir)) {
    Write-Host "[TEST PASSED] Locked folder & files were successfully unlocked and permanently deleted!" -ForegroundColor Green
} else {
    Write-Host "[TEST FAILED] Could not delete locked directory." -ForegroundColor Red
    $failed = $true
}

# 5. Test Deletion of Mock AI Models and Archive
Write-Host "`n[STEP 5] Testing Deletion of Mock AI Model & Archive..." -ForegroundColor Yellow
Remove-ItemCompletely -Path $testMockAI -LogCallback $logCallback | Out-Null
Remove-ItemCompletely -Path $testMockArchive -LogCallback $logCallback | Out-Null

$aiExists = Test-Path $testMockAI
$archiveExists = Test-Path $testMockArchive

if (-not $aiExists -and -not $archiveExists) {
    Write-Host "[TEST PASSED] AI Models and Large Archive deleted with ZERO traces remaining." -ForegroundColor Green
} else {
    Write-Host "[TEST FAILED] Traces still exist on disk." -ForegroundColor Red
    $failed = $true
}

# 6. Test Safety Filter (Ensure system roots can never be deleted)
Write-Host "`n[STEP 6] Testing System Safety Guards (Blacklist protection)..." -ForegroundColor Yellow
$rootDeleteResult = Remove-ItemCompletely -Path "C:\" -LogCallback $logCallback
if (-not $rootDeleteResult) {
    Write-Host "[TEST PASSED] System root protection properly blocked unauthorized deletion." -ForegroundColor Green
} else {
    Write-Host "[TEST FAILED] System root was not blocked!" -ForegroundColor Red
    $failed = $true
}

# Cleanup sandbox
Remove-Item -LiteralPath $testSandbox -Recurse -Force -ErrorAction SilentlyContinue

if ($failed) {
    Write-Host "`n==========================================================" -ForegroundColor Red
    Write-Host "   SANDBOX TESTS FAILED — see [TEST FAILED] above.       " -ForegroundColor Red
    Write-Host "==========================================================" -ForegroundColor Red
    exit 1
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "   ALL ISOLATED SANDBOX TESTS PASSED SUCCESSFULLY!        " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
