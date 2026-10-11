# Theme design and validation

## Generate a starting theme

Python 3.10+ and Pillow are required (`python -m pip install Pillow`). Run from the skill directory:

```powershell
python scripts/create_theme.py --image "D:\Pictures\my-wallpaper.jpg" --id my-background --name "My background" --preset warm --output "D:\Themes\my-background"
```

Without `--image`, the tool generates an original gradient. Presets: `warm`, `forest`, `night`. Optional `--surface-opacity 0.90` controls reading-card opacity (higher means easier reading and less visible background); it never changes text opacity. Do not promise that one number controls all host-app surfaces.

The destination must be new or empty. Edit a copy for revisions. Images are normalized to PNG with orientation corrected and constrained to 3840 pixels on the long edge; no user images leave the device. Maximum input/output size is 16 MiB. The generated theme is for CodeFace schema version 2 / v1.6.1 and needs live compatibility verification on newer app versions.

## Composition

- Use one viewport-owned background. Sidebar material should blend with it, not duplicate a differently cropped image.
- Body text starts at 400 weight; headings/strong text may be 600. Avoid text strokes and heavy glows.
- Keep composer, popovers, code blocks and settings readable. Strong artwork benefits from more opaque reading surfaces.
- Use `cover` and choose `backgroundPosition` for the artwork; do not stretch the picture. Let the app retain layout widths, sidebar collapse and native zoom.
- Theme selectors should use CodeFace semantic markers. Inspect their current existence before extending CSS. Avoid positional `nth-child` chains tied to one app build.
- Style `.codeface-project-bar`, `.codeface-project-section` and `.codeface-composer-stack` as materials only. Do not give them negative margins, transforms or fixed heights.
- Decoration must be non-interactive. Do not hide buttons, project links, native suggestions or permission controls. Do not add external URLs, scripts, remote fonts or `@import`.

## Theme contract

Files: `theme.json`, `codeface.css`, `background.png`. Text is UTF-8. Keep CSS below 256 KiB. Manifest needs a unique lowercase kebab-case `id`, `name`, `image` and hex colors for `background`, `panel`, `accent`, `text`, `muted`. Generator also fills optional palette roles.

This package's minimal CSS is original and intentionally leaves host geometry alone. The upstream CodeFace manager contributes its own base skin. Future DOM changes can still require a selector update.

## Acceptance evidence

1. Import with CodeFace; inspect the manager's preview.
2. Apply to the detected live endpoint and obtain a healthy report for every returned renderer.
3. Inspect image crop, body text, code text, input and menus on live routes. Automated health checks do not prove the whole design.
4. Check narrow (about 760 CSS px) and wide (about 1440 CSS px) windows; check 80–150% zoom. At very small sizes follow the app's supported native minimum rather than forcing desktop panels into fixed widths.
5. If persistence is requested, test task execution in the user's Windows session and a subsequent app launch. Record exactly what was tested.
