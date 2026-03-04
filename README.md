# CodeRabbit macOS Review App (MVP)

A native macOS SwiftUI app that runs CodeRabbit CLI reviews on any selected project folder.

## What it does

- Pick a project folder.
- Run CodeRabbit reviews with selectable output mode:
  - Full detailed review (`review --plain`)
  - Token-efficient prompts only (`review --prompt-only`)
- Resolve `coderabbit` executable portably by trying:
  - Optional executable override from UI
  - `which coderabbit`
  - Common install paths (`/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`)
- Stream CLI stdout/stderr live into the app.
- Parse output into structured findings with CodeRabbit type labels, comments, proposed diff fixes, and AI prompts.
- Show review progress by phase (Starting, Connecting, Setting up, Analyzing, Reviewing, Complete).
- Keep a local review history sidebar where each completed review is stored as one post for 30 days.

## Requirements

- macOS with Xcode 15+ (or equivalent SwiftUI/macOS toolchain)
- CodeRabbit CLI installed (`coderabbit`)

## Run

Open `CodeRabbit.xcodeproj` in Xcode and run the app target.

If auto-discovery fails on a specific machine, paste the full binary path into the "CodeRabbit executable path override" field.

## Build Signed + Notarized DMG

1. Ensure your app is signed and notarized (`CodeRabbit.app`).
2. Store notarization credentials once:
   ```bash
   xcrun notarytool store-credentials AC_NOTARY \
     --apple-id "<apple-id>" \
     --team-id "<team-id>" \
     --password "<app-specific-password>"
   ```
3. Run:
   ```bash
   DEVELOPER_ID_APP_CERT="Developer ID Application: <Your Name> (<TEAMID>)" \
   NOTARY_PROFILE="AC_NOTARY" \
   ./scripts/create_signed_notarized_dmg.sh
   ```

Output DMG is written to `dist/`.

If your `.app` is already notarized and you want to skip local preflight verification:

```bash
SKIP_APP_VERIFY=1 \
DEVELOPER_ID_APP_CERT="Developer ID Application: <Your Name> (<TEAMID>)" \
NOTARY_PROFILE="AC_NOTARY" \
./scripts/create_signed_notarized_dmg.sh
```

To include a custom DMG background image (PNG):

```bash
BACKGROUND_IMAGE="/absolute/path/to/dmg-background.png" \
DEVELOPER_ID_APP_CERT="Developer ID Application: <Your Name> (<TEAMID>)" \
NOTARY_PROFILE="AC_NOTARY" \
./scripts/create_signed_notarized_dmg.sh
```

The script will:
- add `.background/background.png` inside the DMG
- place your app and `/Applications` link in a Finder window
- set the Finder background image before signing/notarizing

## Notes

- The parser currently supports common patterns like:
  - `path/file.swift:42: warning: message`
  - `[WARNING] path/file.swift:42 message`
  - Plain-text review sections including:
    - `Comment:`
    - `Proposed fix` diffs
    - `Prompt for AI Agent:`
- The review command is selected from New Review output mode (full vs prompt-only).
- Use Settings to clear stored review history at any time.
