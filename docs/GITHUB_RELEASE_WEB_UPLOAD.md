# GitHub Release Upload (Web UI) for v1.0.0

Use this when `gh` CLI is unavailable.

## Files to Upload

1. `dist/MouseManager-preview-v1.0.0-macOS26.zip`
2. `dist/MouseManager-preview-v1.0.0-macOS26.zip.sha256`
3. Release notes source: `docs/releases/v1.0.0.md`

## Steps

1. Open `https://github.com/Deferare/MacOS-mouseManager/releases/new`.
2. Tag: `v1.0.0`.
3. Title: `MouseManager v1.0.0 (Public Preview)`.
4. Paste contents from `docs/releases/v1.0.0.md` into release notes.
5. Upload both files from `dist/`.
6. Publish release.

## Post-Publish Checks

1. Confirm release page opens:
   - `https://github.com/Deferare/MacOS-mouseManager/releases/tag/v1.0.0`
2. Confirm asset download works.
3. Confirm SHA file is visible and downloadable.
