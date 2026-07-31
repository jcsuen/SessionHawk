<p align="center">
  <img src="assets/AppIcon.iconset/icon_256x256.png" width="128" alt="SessionHawk icon">
</p>

<h1 align="center">SessionHawk 🦅</h1>

<p align="center">
  <b>A native macOS menu bar app that watches all your AI coding agents at once.</b><br>
  Know instantly which session needs your input, which is working, and how much context each one has burned.
</p>

<p align="center">
  <a href="https://buymeacoffee.com/jcsuen"><img src="https://img.shields.io/badge/☕-Buy%20me%20a%20coffee-ffdd00?style=flat-square" alt="Buy Me a Coffee"></a>
  <img src="https://img.shields.io/badge/macOS-14+-black?style=flat-square&logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="MIT License">
</p>

<p align="center">
  <img src="docs/screenshots/sessions.png" width="380" alt="SessionHawk session list">
</p>

---

Running four Claude Code sessions, a Gemini CLI, and a Codex agent across a dozen terminal tabs? SessionHawk keeps a hawk in your menu bar so you stop cmd-tabbing through terminals to check "is it done? is it stuck? is it waiting on me?"

## Features

- **⚡ Instant "Input Needed" alerts** — native macOS notifications the moment an agent finishes a turn or hits a permission prompt. Powered by real Claude Code hooks, not polling guesswork.
- **🎯 Click to jump to the exact terminal tab** — resolves the session's TTY and focuses the right iTerm2 session or Terminal.app tab, not just the app.
- **📊 Live context usage** — real token consumption parsed from session transcripts, with 200k/1M context windows auto-detected. Watch the bar turn red before compaction sneaks up on you.
- **🔍 Auto-discovery** — finds running `claude`, `gemini`, `codex`, and `cursor-agent` processes automatically. No per-session setup.
- **🧠 Self-correcting states** — Working / Input Needed / Idle reconciled from transcript activity every 30 seconds, so a missed event never leaves a stale badge. Sessions waiting on background tasks aren't falsely flagged as needing you.
- **🪶 Native and lightweight** — pure SwiftUI + Network framework. No Electron, no dependencies, ~500 KB binary.

## How it works

```
┌────────────────┐  Claude Code hooks (Stop / Notification /   ┌─────────────────┐
│  your agent    │  UserPromptSubmit / PostToolUse)            │   SessionHawk    │
│  CLI sessions  │ ───────────────────────────────────────────▶│   menu bar app   │
└────────────────┘         POST localhost:9422/v1/event        └─────────────────┘
        ▲                                                               ▲
        │        ┌──────────────────────────────┐                       │
        └────────│  feeder (30s reconciler):    │───────────────────────┘
                 │  process discovery, context  │
                 │  tokens, state self-healing  │
                 └──────────────────────────────┘
```

- **Hooks** give precise, instant state transitions (and fire the notifications).
- **The feeder** discovers sessions, parses context usage from transcripts, and reconciles state from transcript activity — only hooks may claim "Input Needed", so background monitors never cause false alarms.
- Anything can report a session: `POST http://localhost:9422/v1/event` with `{pid, provider, state, inputTokens, ...}` — trivial to integrate custom agents.

## Install

```bash
git clone https://github.com/jcsuen/SessionHawk.git
cd SessionHawk
./scripts/make-app-bundle.sh     # builds and installs /Applications/SessionHawk.app
open /Applications/SessionHawk.app
```

Wire up the Claude Code hooks (precise states + notifications) by adding to `~/.claude/settings.json`:

```jsonc
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "/path/to/SessionHawk/scripts/sessionhawk-claude-hook.sh working", "timeout": 10, "async": true }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "/path/to/SessionHawk/scripts/sessionhawk-claude-hook.sh waitingForInput", "timeout": 10, "async": true }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "/path/to/SessionHawk/scripts/sessionhawk-claude-hook.sh waitingForInput", "timeout": 10, "async": true }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "/path/to/SessionHawk/scripts/sessionhawk-claude-hook.sh idle", "timeout": 10, "async": true }] }],
    "PostToolUse":      [{ "matcher": "*", "hooks": [{ "type": "command", "command": "/path/to/SessionHawk/scripts/sessionhawk-claude-hook.sh working", "timeout": 10, "async": true }] }]
  }
}
```

Start the feeder (discovery + context tracking):

```bash
./scripts/feed-live-sessions.sh          # foreground
```

### Start everything at login

```bash
cp launchd/com.sessionhawk.app.plist launchd/com.sessionhawk.feeder.plist ~/Library/LaunchAgents/
# edit the feeder plist so the script path matches your clone location, then:
launchctl load ~/Library/LaunchAgents/com.sessionhawk.app.plist
launchctl load ~/Library/LaunchAgents/com.sessionhawk.feeder.plist
```

Requires `jq` (`brew install jq`) for transcript parsing.

## HTTP API

| Endpoint | Method | Purpose |
|---|---|---|
| `/v1/event` | POST | Report a session: `{"pid": 123, "provider": "claude", "state": "working", "inputTokens": 50000, "outputTokens": 200, "totalLimit": 1000000, "workingDirectory": "/path", "timestamp": 1753960000000}` — omit `state` for a heartbeat that refreshes liveness/tokens without touching state |
| `/v1/sessions` | GET | Current sessions as JSON |

States: `working`, `waitingForInput`, `idle`, `error`. Providers: `claude`, `gemini`, `codex`, `cursor`, `custom`.

## Support

If SessionHawk saves you from one more "oh no, it's been waiting for me for 20 minutes" — consider fueling development:

<a href="https://buymeacoffee.com/jcsuen"><img src="https://img.shields.io/badge/☕-Buy%20me%20a%20coffee-ffdd00?style=for-the-badge" alt="Buy Me a Coffee"></a>

## License

[MIT](LICENSE)
