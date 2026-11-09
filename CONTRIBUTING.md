# Contributing to SystemDiskCleaner

Thanks for helping improve SystemDiskCleaner. This guide covers the setup,
the sandbox test suite, and the ground rules that keep a tool with
permanent, zero-trace deletion safe to change. Everything here is grounded
in `README.md`, `SystemDiskCleaner.ps1`, `launch.bat`, and
`tests/test_cleaner_sandbox.ps1`.

## Setup

- **Windows 10, Windows 11, or Windows Server** with **PowerShell 5.1 or
  PowerShell 7+**. There is no Linux/macOS support: the app uses WinForms,
  Win32 calls, and Windows-only file locking.
- Clone the repository. No build step and no package restore — the whole
  app is one script plus a launcher.

## Layout

- `SystemDiskCleaner.ps1` (1,518 lines) — the entire app: WinForms GUI
  (`Show-CleanerGUI`), the embedded C# high-speed sizing engine, the
  deep-scan engine (`Start-SystemDeepScan`), the 10-second safety
  countdown (`Show-SafetyCountdownDialog`), the CLI mode
  (`Start-CliMode`), and the delete/unlock helpers
  (`Remove-ItemCompletely`, `Clean-FolderContentsSafe`,
  `Stop-LockingProcessesForPath`, `Get-FolderSizeFast` /
  `Format-FileSize`). `Get-FolderSizeSafe` is an alias for
  `Get-FolderSizeFast`.
- `launch.bat` — double-click launcher; runs PowerShell as Administrator
  with `ExecutionPolicy Bypass`.
- `tests/test_cleaner_sandbox.ps1` — the isolated sandbox test suite (see
  below).

## Running the app

```powershell
# Option A: double-click launch.bat (recommended, auto-elevates to Administrator)
# Option B: PowerShell directly
powershell -ExecutionPolicy Bypass -File .\SystemDiskCleaner.ps1
# Option C: headless CLI mode (same 10-second countdown, Ctrl+C aborts)
powershell -ExecutionPolicy Bypass -File .\SystemDiskCleaner.ps1 -NoGui
```

Script switches: `-NoElevate` (skip auto-elevation),
`-NoGui` (headless CLI mode), `-ExportFunctionsOnly` (load the helper
functions without launching anything — this is how the test suite sources
the script), `-CustomDrives` (scan specific drives).

## Tests

There is **no CI workflow on this repo** — the tests are Windows-only, so
run them by hand on a Windows machine before opening a PR:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\test_cleaner_sandbox.ps1
```

The suite builds an isolated sandbox under `tests/test_sandbox/`
(gitignored) and runs six steps:

1. Creates mock files: a 5 MB AI-model file, a 2 MB package cache, a
   10 MB archive, and a file held under an exclusive lock by a background
   PowerShell process.
2. Verifies the lock is real, then sources the cleaner with
   `-NoElevate -ExportFunctionsOnly`.
3. Checks size calculations (`Get-FolderSizeSafe` / `Format-FileSize`)
   against the known mock sizes.
4. Checks that normal deletion fails on the locked file, then that the
   cleaner's unlock-and-delete path removes the locked folder completely.
5. Checks the mock AI model and archive are deleted with zero traces.
6. Checks the safety guard: `Remove-ItemCompletely -Path "C:\"` must
   refuse.

**Do not run the tests (or the app) against anything but throwaway data.**
Deletion here is permanent — files are removed with zero traces, not sent
to the Recycle Bin, and there is no recovery.

## Ground rules

- **Never weaken the safety guards.** Drive roots (`C:\`, `D:\`),
  critical system paths (`C:\Windows`, `System32`, `C:\Users`), and
  protected files (`pagefile.sys`, `swapfile.sys`, `hiberfil.sys`) must
  stay undeletable. The 10-second safety countdown exists so a mistaken
  selection can still be aborted — do not remove or shorten it.
- **Test only on throwaway folders.** Never point a test run at a real
  user profile, a real drive root, or a machine you care about.
- **Never commit secrets.** No credentials, tokens, or machine-specific
  paths.
- **Keep it one file.** New scan categories belong in the existing
  category table in `SystemDiskCleaner.ps1`; do not split the script
  without a reason stated in the PR.
- **Report vulnerabilities privately**, not in a public issue — this tool
  deletes files by design, so a guard bypass is a safety issue.
- Use [Conventional Commits](https://www.conventionalcommits.org/)
  (`docs(systemdiskcleaner): …`, `fix(systemdiskcleaner): …`).
