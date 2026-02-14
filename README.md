# Mouse Manager (Public Preview)

Mouse Manager is a lightweight macOS utility for mouse button actions, middle-button drag scrolling, and smooth wheel behavior.

## Public Preview Policy

1. Release channel: **GitHub Releases only**.
2. Distribution format: **ZIP containing `MouseManager.app`**.
3. Do not share a raw `.app` bundle as the primary release artifact.
4. This preview is currently distributed without Developer ID signing/notarization.

## Supported OS

1. **macOS 26.0 or later** for Public Preview releases.
2. The app target deployment setting remains `MACOSX_DEPLOYMENT_TARGET = 26.0` in `/Users/deferare/Main/MacOS-mouseManager/MouseManager.xcodeproj/project.pbxproj`.

## Install Flow (Public Preview)

1. Download the latest `MouseManager-preview-vX.Y.Z-macOS26.zip` from GitHub Releases.
2. Unzip the file.
3. Move `MouseManager.app` to `/Applications`.
4. First launch: right-click `MouseManager.app`, then click `Open`.
5. If blocked by Gatekeeper, go to `System Settings > Privacy & Security` and click `Open Anyway`.

## Update Policy

1. Update mode is **manual update**.
2. Download the next release ZIP and replace the old `MouseManager.app` in `/Applications`.
3. Keep release notes with each version so users can verify changes before replacing the app.

## Release Artifact Specification

1. File naming rule: `MouseManager-preview-vX.Y.Z-macOS26.zip`.
2. ZIP content rule: single app bundle `MouseManager.app` at top level.
3. Provide SHA256 checksum with each release.
4. Release notes must include:
   - Supported OS
   - Accessibility permission requirement
   - Install steps
   - Known limitations
   - Manual update instructions

## Release Packaging Script

Use:

```bash
scripts/package_preview_release.sh 1.0.0
```

Output:

1. `dist/MouseManager-preview-v1.0.0-macOS26.zip`
2. `dist/MouseManager-preview-v1.0.0-macOS26.zip.sha256`

## Accessibility Permission

Mouse/scroll event interception requires Accessibility permission.

1. In the app: `General > Permissions > Request…`
2. Or in macOS: `System Settings > Privacy & Security > Accessibility`

## Support Operations

1. Support channel: `deferare@icloud.com`.
2. Required subject prefix: `[MouseManager Preview]`.
3. Triage categories:
   - Installation issue
   - Accessibility permission issue
   - Functional bug
   - Feature request
4. Response target SLA: first response within 48 business hours.

## X (Twitter) Launch Plan

1. First post: 20-30 second demo video + one-line value proposition + release link.
2. Follow-up in the same thread: clearly state `Public Preview`, `macOS 26+`, and unsigned install steps.
3. 24-hour post: feedback incorporation plan + support email reminder (`deferare@icloud.com`).
4. 72-hour post: patch notes summary + refreshed download link.

## Validation Checklist

1. Fresh macOS 26.x machine can install and launch from ZIP.
2. Accessibility allow/deny flows match app guidance.
3. SHA256 checksum verifies downloaded ZIP.
4. Manual replacement update preserves expected behavior.
5. X post link path to release asset is not broken.

## Local Build (Development)

```bash
mkdir -p /tmp/clang-module-cache /tmp/swiftpm-cache
CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_CACHE_DIR=/tmp/swiftpm-cache swift build -c debug
CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_CACHE_DIR=/tmp/swiftpm-cache swift run MouseManager
```
