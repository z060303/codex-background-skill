# Compatibility and test scope

Release validation date: **2026-10-11**.

## Automated checks

- Python unit tests: three complete gradient themes; UTF-8 manifest; transparent image conversion and size limit; existing-output preservation; invalid IDs and opacity rejection.
- Windows PowerShell 5.1 runtime tests: complete health JSON validation; nested false-positive rejection; empty/wrong-theme/nonzero-exit rejection; dynamic CDP port parsing; child-only environment override; native argument quoting; subprocess timeout.
- Parse every PowerShell file with the Windows PowerShell 5.1 parser.
- Validate the skill with Codex skill-creator's `quick_validate.py` (use `python -X utf8` on Windows locales that default to another encoding).
- Install the skill into an isolated destination. Stage/import a real theme using the archived CodeFace 1.6.1 executable in a separate ordinary directory; repeat installation and confirm a previous-theme backup exists.
- Use `tools/verify_codeface.cjs` with CodeFace 1.6.1 in a **new headless Chromium test fixture**: injection, health JSON, painted background, readable surface, normal body weight, no horizontal overflow at 760/1100/1440 CSS pixels and CSS zoom 0.8/1/1.25/1.5, then renderer cleanup. This verifies integration mechanics and the starter CSS; it is not the real desktop app.

GitHub Actions repeats the Python/runtime unit tests and PowerShell parsing. It does not download or run the archived binary, access a user's desktop or configure login startup.

## What still requires validation on each user's machine

- Actual current Codex home/conversation/settings DOM, menus and code views.
- Native application zoom and operating-system display scaling. Fixture CSS zoom is only a regression check, not an equivalent test of every real app layout.
- The user's specific background image and resulting contrast.
- Launching the app, executing a user-scoped scheduled task in their Windows session, and restarting/signing into Windows.
- Restore on that app version, especially when another manager is active or a nondefault port requires CodeFace control-state discovery.
- macOS/Linux startup: not implemented by the included scripts.

This release is a reusable workflow and tested helper, not a promise that every future Codex release keeps the same DOM/CDP behavior. During authoring we deliberately did not replace the author's live theme, restart their Codex, or register a second watcher. An agent using this skill must carry out the live acceptance steps before reporting that a user's setup is finished.

## Optional integration test

From a developer checkout, install Playwright in a disposable environment and stage a test theme into a separate helper installation. Then run:

```powershell
node tools/verify_codeface.cjs "D:\Tools\CodeFace.exe" "D:\TestRuntime\runtime"
```

`PLAYWRIGHT_PATH` may point to an existing Playwright module installation. The script launches and closes its own Chromium; it does not connect to an existing Codex/browser. Never substitute the user's active data root for the disposable test runtime.
