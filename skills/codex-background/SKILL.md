---
name: codex-background
description: Create personalized image backgrounds for the Codex desktop app with CodeFace; adjust readability and responsive layout, diagnose missing backgrounds, and optionally configure Windows login startup or restore the native appearance. Use for Codex wallpaper/background customization, not OS wallpapers or unrelated app themes.
---

# Codex background

Turn the user's picture or visual brief into a usable desktop theme. Speak in the user's language. “Default background” means automatically reapplied by an external theme manager; do not claim to change an official built-in default or guarantee compatibility with future app updates.

## 1. Establish the result

Use the image, style and preferences already supplied. Ask only for consequential missing input. If an image is attached, inspect it. Keep its subject away from the reading area. When no image exists, use available image generation for artwork; if unavailable, offer the included procedural gradient or ask for a local picture. Do not claim the skill itself supplies an image model.

Infer sensible typography and surfaces from the artwork: normal body weight (400), stronger headings, readable composer and message cards. Explain transparency through the visible result: more visible artwork versus more opaque reading surfaces. Do not make all text bold or apply opacity to containers containing text.

## 2. Discover and prepare

Read [design.md](references/design.md) for the manifest, generator and visual checks. Read [windows.md](references/windows.md) for Windows installation, activation, startup or restoration. For a missing background, read [troubleshooting.md](references/troubleshooting.md).

Use CodeFace as the only theme injector. Locate an installed binary, check its version/provenance and run `--print-data-root` in the **same environment** that will apply it. Never edit app.asar, installation files, credentials or API settings. The bundled helpers target Windows PowerShell 5.1+; on macOS use CodeFace's own workflow and clearly state that these startup helpers are Windows-only.

If CodeFace is missing, use the verified download instructions in windows.md. Inspect downloads and hashes before execution; no piped remote script execution. The dependency may be unavailable upstream; report that honestly and use the documented archived release when appropriate.

Create a unique theme directory with `scripts/create_theme.py`; the output is a starting point, not proof of a good live design. The generator accepts a local image or makes an original gradient. Adapt the generated CSS and palette to the actual image. Preserve existing themes; do not overwrite without a backup. The full theme consists of theme.json, codeface.css and background.png.

## 3. Preview and apply

Preview the theme in CodeFace before applying. Apply only when requested by the user (including requests to change their background). Reuse the port declared by the actual Codex process; never assume 9341 or connect to a random browser port. Keep CDP on loopback.

The runtime helper never kills or restarts an open app. If Codex lacks a working endpoint, finish creating the theme first, then explain that the user needs to close Codex and reopen it through the installed launcher. A port timeout is not evidence that the app should be restarted. Do not start a competing watcher if an existing background manager is already active; diagnose and migrate it only within the user's request.

Run CodeFace `--health-check <theme-id> <actual-port>` after activation and require **both** a successful exit code and top-level `healthy: true`, the expected ID, at least one page and healthy page results. Nested `healthy: true` or an injection success message is insufficient. On failure, restore the previous theme from the helper's backup and report the failure.

Inspect the live home, conversation, settings and composer at narrow and wide sizes and at representative zoom levels (80%, 100%, 125%, 150%). Check for horizontal overflow, overlapping controls and text contrast. Do not replace a live user's route or discard unsent text just to get a screenshot. Use a separate preview/test window when needed, and distinguish a test fixture from real app validation.

## 4. Persist only if requested

“Keep this after reopening” authorizes persistence. “Open it when I log in” also authorizes launching Codex at login. Installing this skill alone authorizes neither. Use the single scheduled task provided by `ThemeRuntime.ps1`; use its optional `-LaunchAtLogin` only for the latter request. It detects dynamic ports, has bounded subprocess timeouts and stops after repeated failures. It never repeatedly restarts Codex.

Run the installed task from Windows Task Scheduler to test the real background environment, then inspect the log and health result. A task marked Running is insufficient. Report login configuration separately from an actual Windows reboot test; do not claim to have reboot-tested without doing so. The background may appear shortly after the app window opens.

## 5. Hand off or restore

Provide the theme name, verified outcome, launcher/restore paths and any untested views. Preserve the user's existing background when merely authoring or publishing this skill.

For restoration, disable this helper's startup and stop its watcher **before** calling CodeFace `--restore` in the same data environment. Check the active port afterward. A still-running watcher can otherwise reapply the background. Use the installed Restore action and explain any other manager that remains active.
