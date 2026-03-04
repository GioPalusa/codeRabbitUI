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
