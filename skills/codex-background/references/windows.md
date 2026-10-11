# Windows workflow

These commands run from the skill directory (`skills/codex-background` in the repository or the installed skill folder). They use Windows PowerShell 5.1+ and do not need administrator privileges on a normally configured personal machine. Managed computers may restrict Task Scheduler.

## 1. Locate or obtain CodeFace

Prefer an existing trusted CodeFace executable. Do not silently replace it. If absent, inspect `scripts/Get-CodeFace.ps1` and `assets/runtime.json`, then run:

```powershell
$codeFace = & .\scripts\Get-CodeFace.ps1
& $codeFace --print-data-root
```

The download script uses the fixed `v1.0.0` release of this repository, verifies archive and executable SHA-256, extracts only four named files, and does not run the executable. See the included CODEFACE-LICENSE.txt and PROVENANCE.md. CodeFace's original repository returned 404 on 2026-10-11; this is the archived v1.6.1 Windows x64 binary, not a new upstream build. Its preserved source is linked in `assets/runtime.json`. If downloads are unavailable, finish the theme files and report the missing runtime instead of claiming application succeeded.

## 2. Generate and inspect the theme

```powershell
python -m pip install Pillow
python .\scripts\create_theme.py --image "D:\Pictures\wallpaper.jpg" --id my-background --name "我的背景" --preset warm --output "D:\Themes\my-background"
```

Omit `--image` for an original gradient, or select `--preset forest` / `--preset night`. Inspect the image and edit the generated palette/CSS as needed. Preview with CodeFace before live use; the helper's Install action only stages a theme, so its manager can be opened against that staging root for preview. Run the manager with a **child-only** LOCALAPPDATA override to `config.json`'s RuntimeBase. Do not run Apply or change a live user's route just for a screenshot.

## 3. Install, then apply

```powershell
.\scripts\ThemeRuntime.ps1 -Action Install -ThemePath "D:\Themes\my-background" -CodeFaceExe $codeFace
.\scripts\ThemeRuntime.ps1 -Action Diagnose
.\scripts\ThemeRuntime.ps1 -Action Apply
```

For a non-Microsoft-Store desktop installation, supply the desktop GUI executable with `-CodexExe` during Install. Do not point it at the CLI `codex.exe`. The helper recognizes the current official Store package and resolves its location again on launch, so Store updates do not freeze an obsolete path.

The helper installs into `%LOCALAPPDATA%\Programs\CodexBackgroundSkill` by default. `-InstallRoot` selects another ordinary, user-owned directory; use that same parameter for subsequent actions. The helper asks CodeFace `--print-data-root` with a child-scoped LOCALAPPDATA pointing to its own runtime folder. This is an explicit, dedicated **CodeFace runtime**, not a second custom injector. Do not mix it with another watcher using a different data root.

Files copied into that runtime are written as bytes; the helper fails if EFS encryption is still inherited. Never change OS-wide encryption. CodeFace's CLI validates the staged theme during import. The previous active theme, if present, is backed up before replacement; a failed health gate attempts to restore it. For the first theme there is no earlier helper theme to roll back; pause and use Restore if it is unsuitable.

Live application uses the actual Codex main process's declared CDP port, checks listener ownership and loopback binding, injects via CodeFace, and requires a successful complete health report. There is no forced restart.

If no endpoint is available, save work and close Codex when convenient, then use the generated `Codex with background.lnk`, or:

```powershell
.\scripts\ThemeRuntime.ps1 -Action Launch
```

Launch waits up to 45 seconds. It refuses an occupied port and leaves already-running instances alone. The default **new launch** port is 9341; a running instance may use 9229 or another port, which is detected automatically. Never expose the debugging endpoint to the network.

## 4. Optional login persistence

Only after the user requests it:

```powershell
# Monitor after login, but do not open the app automatically:
.\scripts\ThemeRuntime.ps1 -Action EnableStartup

# OR open the app once after login as well:
.\scripts\ThemeRuntime.ps1 -Action EnableStartup -LaunchAtLogin
```

One per-user scheduled task, `CodexBackgroundSkill`, runs an installed script from Windows Task Scheduler. It remains independent of Codex's tool process. Closing Codex later leaves it closed. No service, duplicate Run key or hidden restart loop is installed. If task registration fails, report it rather than claim startup works or install undisclosed fallbacks.

After configuration, inspect `watcher.log`, run Diagnose and verify a live health report. A scheduled task's Running status is not enough. Do not claim a Windows reboot test unless one occurred. The watcher stops after three repeated application errors; missing endpoints are logged and awaited without closing apps. Use Apply after fixing the issue to unpause, or enable startup again.

If migrating an older personal watcher, first identify its exact task/process/script. Do not disable every PowerShell process or all startup items. This helper never migrates other managers implicitly.

## 5. Disable / restore

```powershell
# Stop the helper but keep the current visible theme:
.\scripts\ThemeRuntime.ps1 -Action DisableStartup

# Stop the helper and request the native appearance:
.\scripts\ThemeRuntime.ps1 -Action Restore
```

Restore pauses and waits for any in-flight injection, unregisters only this helper's task, runs CodeFace `--restore` in the matching runtime, and checks its actual port. v1.6.1 may need `--start-control <port>` to establish state before restoring a nondefault port; the helper handles that through CodeFace. If no app is open, no injection remains in that closed process and the next normal launch uses native appearance. Keep theme files as a backup. Do not launch the themed shortcut again if you want to stay native.

All mutating actions support `-WhatIf`. Installing the **Skill** is separate from installing the **theme helper**. Neither installation alone enables login startup.
