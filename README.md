# CodeRabbit for macOS

[![Latest Release](https://img.shields.io/github/v/release/GioPalusa/codeRabbitUI)](https://github.com/GioPalusa/codeRabbitUI/releases)
[![Open Issues](https://img.shields.io/github/issues/GioPalusa/codeRabbitUI)](https://github.com/GioPalusa/codeRabbitUI/issues)
[![Platform](https://img.shields.io/badge/platform-macOS-black)](https://www.apple.com/macos/)

Run CodeRabbit reviews from a fast native macOS app instead of juggling terminal commands.

![Screenshot](https://github.com/GioPalusa/codeRabbitUI/blob/main/coderabbitUI-start.png)

CodeRabbit for macOS is built for developers who want:

- A clean review workflow with less setup friction
- Live progress and readable findings in one place
- Quick handoff prompts for AI coding agents
- Release updates directly from GitHub

## Why Use It

- Native macOS UX for CodeRabbit CLI workflows
- Real-time run phases: `Starting -> Connecting -> Setting up -> Analyzing -> Reviewing`
- Structured output: findings, comments, proposed fixes, and AI prompts
- Fast mode switching:
  - Full detailed review (`review --plain`)
  - AI-agent-only output (`review --prompt-only`)
- Local review history (30-day retention)
- In-app checks for app and CLI updates

## Get Started (2 Minutes)

1. Download the latest app from [GitHub Releases](https://github.com/GioPalusa/codeRabbitUI/releases).
2. Move `CodeRabbit.app` into `/Applications`.
3. Install CodeRabbit CLI (if not already installed):

```bash
curl -fsSL https://cli.coderabbit.ai/install.sh | sh
```

4. Open the app and select a project folder.
5. Click `Start Review`.

## First Review Workflow

1. Pick your project folder.
2. Choose:
   - `Review Type`: all, committed, or uncommitted
   - `Review Output`: full or prompt-only
3. Start review and follow progress live.
4. Inspect findings and copy AI prompts for your coding agent.

## Requirements

- macOS
- `coderabbit` CLI installed
- A git repository to review

## Need Help or Want a Feature?

- Report a bug: [Create bug ticket](https://github.com/GioPalusa/codeRabbitUI/issues/new?template=bug_report.md)
- Request a feature: [Create feature ticket](https://github.com/GioPalusa/codeRabbitUI/issues/new?template=feature_request.md)
- Track current work: [Issues board](https://github.com/GioPalusa/codeRabbitUI/issues)

Please include app version, macOS version, and reproduction steps in tickets.

## Build from Source (Optional)

Open `CodeRabbit.xcodeproj` in Xcode and run target `CodeRabbit`.

## Disclaimer

This app is an independent client for the CodeRabbit CLI.
It is not affiliated with, endorsed by, or maintained by CodeRabbit, Inc. or CodeRabbit AI.
