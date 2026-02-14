# Mouse Manager Public Preview Playbook (macOS 26+)

## Positioning

1. Product stage: `Public Preview`.
2. Audience: global macOS users on `macOS 26.0+`.
3. Pricing: free.
4. Distribution source: GitHub Releases only.

## Distribution Rules

1. Release file name format: `MouseManager-preview-vX.Y.Z-macOS26.zip`.
2. ZIP must contain only `MouseManager.app` at top level.
3. Publish SHA256 checksum for every ZIP.
4. Do not use raw `.app` bundle upload as the official release artifact.

## Release Notes Required Sections

1. Supported OS (`macOS 26.0+`).
2. Accessibility requirement.
3. Install instructions.
4. Known limitations.
5. Manual update instructions.

## Installation Flow (User-Facing)

1. Download ZIP from GitHub Releases.
2. Unzip.
3. Move `MouseManager.app` to `/Applications`.
4. First launch with right-click `Open`.
5. If blocked, go to `Privacy & Security` and click `Open Anyway`.

## Update Policy

1. Manual updates only.
2. User replaces app with the latest release ZIP contents.
3. Every release includes changelog and checksum.

## X (Twitter) Rollout

1. T+0:
   - Post demo video (20-30s).
   - Include one-line value proposition.
   - Add GitHub Release link.
2. T+0 thread reply:
   - State `Public Preview`.
   - State `macOS 26+`.
   - Add unsigned build install guidance.
3. T+24h:
   - Share feedback plan.
   - Re-share support channel (`deferare@icloud.com`).
4. T+72h:
   - Share patch notes summary.
   - Re-share latest download link.

## Support Operations

1. Support channel: `deferare@icloud.com`.
2. Email subject prefix: `[MouseManager Preview]`.
3. Triage tags:
   - install
   - accessibility
   - bug
   - feature-request
4. SLA: first response within 48 business hours.

## Verification Checklist

1. Clean macOS 26.x machine can install and launch from ZIP.
2. Accessibility allow/deny states match in-app guidance.
3. SHA256 checksum verification passes.
4. Manual replacement update works without regressions.
5. X links resolve to the correct release artifact.
