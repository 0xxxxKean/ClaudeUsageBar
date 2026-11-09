# ClaudeUsageBar

A native macOS menu bar app that shows your [Claude Code](https://claude.com/claude-code) usage at a glance — no terminal command needed.

## Features

- **Live usage in the menu bar**: session (5-hour) usage percent next to the Claude icon, colored by severity.
- **Popover detail**: session and weekly usage, plus Opus/Sonnet weekly usage when available, each with its reset time.
- **Multi-account history**: if you've switched accounts via `claude auth login`, previously-seen accounts' last-known usage stays visible (clearly marked as non-live), with per-account delete.
- **Account + IP info**: masked login email and current IP/location, shown in the popover footer.
- **Auto-refresh** every 5 minutes, plus a manual refresh button.

## Requirements

- macOS 13 (Ventura) or later
- [Claude Code](https://claude.com/claude-code) CLI installed and logged in (`claude auth login`) — ClaudeUsageBar reads its Keychain credential to call the usage API

## Install

### Download

[Download the latest .dmg](https://github.com/0xxxxKean/ClaudeUsageBar/releases/latest) — signed with a Developer ID certificate and notarized by Apple, so it opens normally.

### Build from source

```bash
git clone https://github.com/0xxxxKean/ClaudeUsageBar.git
cd ClaudeUsageBar
./Scripts/create_signing_identity.sh   # one-time: local self-signed identity, so macOS
                                        # remembers "Always Allow" Keychain access
./Scripts/build_app.sh                 # builds dist/ClaudeUsageBar.app
cp -R dist/ClaudeUsageBar.app /Applications/
open /Applications/ClaudeUsageBar.app
```

### Build a .dmg instead

```bash
./Scripts/build_dmg.sh   # builds dist/ClaudeUsageBar.dmg
```

If a Developer ID Application identity is installed, `build_dmg.sh` also submits the .dmg for notarization and staples the ticket automatically. Without one, it builds a self-signed .dmg that Gatekeeper will flag as from an unidentified developer on other machines.

On first launch, macOS will prompt once for Keychain access (to read the Claude Code login credential) — allow it.

## Quitting

The app has no Dock icon or app menu (it's a menu-bar-only app). Click the menu bar icon and use the power button in the popover header to quit.

## Development

```bash
swift build
swift test
```
