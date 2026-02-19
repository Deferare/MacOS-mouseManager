# Mouse Manager

Mouse Manager is an open-source macOS utility for mouse button actions, middle-button drag scrolling, and smooth wheel behavior.

## Project Status

1. Distribution channel: **GitHub Releases**.
2. Release artifact: **ZIP containing `MouseManager.app`**.
3. Public Preview binaries currently target **macOS 26.0+**.
4. This project is not distributed through the Mac App Store right now.

## Install (Public Preview)

1. Download the latest `MouseManager-preview-vX.Y.Z-macOS26.zip` from [Releases](https://github.com/Deferare/MacOS-mouseManager/releases).
2. Unzip and move `MouseManager.app` to `/Applications`.
3. First launch: right-click `MouseManager.app`, then click `Open`.
4. If blocked by Gatekeeper, go to `System Settings > Privacy & Security` and click `Open Anyway`.
5. Grant Accessibility permission in `System Settings > Privacy & Security > Accessibility`.

## Update

1. Updates are manual.
2. Download the next release ZIP and replace `MouseManager.app` in `/Applications`.
3. Verify release notes and SHA256 checksum before replacing.

## Build From Source

```bash
mkdir -p /tmp/clang-module-cache /tmp/swiftpm-cache
CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_CACHE_DIR=/tmp/swiftpm-cache swift build -c debug
CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_CACHE_DIR=/tmp/swiftpm-cache swift run MouseManager
```

## Support

1. Email: `deferare@icloud.com` (subject prefix: `[MouseManager Preview]`).
2. Bug reports and feature requests: [GitHub Issues](https://github.com/Deferare/MacOS-mouseManager/issues).

## Sponsor

If Mouse Manager helps your workflow, you can sponsor ongoing development on [GitHub Sponsors](https://github.com/sponsors/Deferare).

## Maintainer Notes

1. Package a release with:

```bash
scripts/package_preview_release.sh 1.0.0
```

2. Output files:
   - `dist/MouseManager-preview-v1.0.0-macOS26.zip`
   - `dist/MouseManager-preview-v1.0.0-macOS26.zip.sha256`
3. For detailed release/validation procedures, see `docs/PUBLIC_PREVIEW_PLAYBOOK.md`.
