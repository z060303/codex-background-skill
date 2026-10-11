# Diagnose the observed failure

Run `ThemeRuntime.ps1 -Action Diagnose` first. Read its configured data root and `watcher.log`; never assume a saved CSS file or a Running task means a visible background.

| Symptom | Evidence to check | Fix |
|---|---|---|
| Reopen loses the picture | Actual main-process arguments and listener owner | Use its declared CDP port. If none, close the app when convenient and use the generated launcher. |
| Background task sees missing files | Run the scheduled task, inspect readable theme files and its discovered data root | Stage ordinary byte-written files in this helper's own Programs directory; verify readability there. Do not decrypt entire AppData trees. |
| Injection works only from the agent | Compare process environment and data roots | Override LOCALAPPDATA only in the CodeFace child. Never pass that override to Codex itself. |
| App repeatedly closes/reopens | Existing scripts/tasks that kill ChatGPT/Codex | Stop the identified conflicting watcher within scope. This package never kills Codex. |
| Only title/sidebar has wallpaper | Main conversation target and live semantic selectors | Verify every renderer and adapt CSS to the live conversation DOM. |
| Blurry/doubled text | CSS stroke, shadows, opacity on text parents | Remove outlines/glows; use weight 400 and a more opaque surface. |
| Zoom breaks layout | Fixed sizes, transforms, positional selectors | Preserve native geometry and inspect narrow/wide/zoom states. |
| Health falsely reports success | Top-level JSON and all pages | Parse JSON; never grep for any occurrence of `healthy: true`. |
| Restore works briefly, then theme returns | All active background watchers | Disable startup, wait for the helper lock to release, then restore in its data root and verify the actual port. |
| Port unavailable after an update | Listener owner, process arguments, endpoint response | Wait within a bounded timeout; stop and report unsupported behavior. Do not restart repeatedly or bind on all interfaces. |

The earlier EFS/encryption observation is one local failure mode, not a diagnosis for every machine. Do not alter OS-wide encryption or create a Windows service to fix a theme.

The helper pauses itself after three consecutive application failures. Inspect the log, fix the cause, then run Apply or enable/start the task again. A deliberate disabled state in this CodeFace runtime also pauses monitoring. It does not automatically undo a user's switch to native appearance.
