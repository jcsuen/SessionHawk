#!/bin/bash
# SessionHawk installer — one command, everything wired up:
#   curl -fsSL https://raw.githubusercontent.com/jcsuen/SessionHawk/main/install.sh | bash
#
# Installs the app to /Applications (pre-built release, or builds from source
# when run inside a clone), merges the Claude Code hooks into
# ~/.claude/settings.json, and sets up start-at-login for app + feeder.

set -euo pipefail

REPO="jcsuen/SessionHawk"
APP="/Applications/SessionHawk.app"
RES="$APP/Contents/Resources"

echo "🦅 SessionHawk installer"

[ "$(uname -s)" = "Darwin" ] || { echo "❌ macOS only"; exit 1; }
if [ "$(uname -m)" != "arm64" ]; then
    echo "⚠️  Pre-built release is Apple Silicon only — will try building from source."
fi

if ! command -v jq >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        echo "▸ Installing jq (needed for context tracking)..."
        brew install jq
    else
        echo "❌ jq is required: install Homebrew (https://brew.sh) then 'brew install jq'"
        exit 1
    fi
fi

# Inside a clone (Package.swift present next to this script) → build from
# source; otherwise download the latest pre-built release.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo /)"
if [ -f "$SCRIPT_DIR/Package.swift" ]; then
    echo "▸ Building from source..."
    (cd "$SCRIPT_DIR" && ./scripts/make-app-bundle.sh)
else
    echo "▸ Downloading latest release..."
    url=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | jq -r '[.assets[] | select(.name | endswith(".zip"))][0].browser_download_url // empty')
    [ -n "$url" ] || { echo "❌ no release asset found — clone the repo and run ./install.sh"; exit 1; }
    tmp=$(mktemp -d)
    curl -fsSL "$url" -o "$tmp/SessionHawk.zip"
    pkill -x SessionHawk 2>/dev/null || true
    rm -rf "$APP"
    ditto -xk "$tmp/SessionHawk.zip" /Applications
    xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
    rm -rf "$tmp"
fi

echo "▸ Installing Claude Code hooks (instant states + notifications)..."
"$RES/scripts/install-hooks.sh" "$RES/scripts/sessionhawk-claude-hook.sh"

echo "▸ Setting up start-at-login..."
mkdir -p "$HOME/Library/LaunchAgents"
cp "$RES/launchd/com.sessionhawk.app.plist" "$HOME/Library/LaunchAgents/"
sed "s|/path/to/SessionHawk/scripts/feed-live-sessions.sh|$RES/scripts/feed-live-sessions.sh|" \
    "$RES/launchd/com.sessionhawk.feeder.plist" > "$HOME/Library/LaunchAgents/com.sessionhawk.feeder.plist"
for agent in com.sessionhawk.app com.sessionhawk.feeder; do
    launchctl unload "$HOME/Library/LaunchAgents/$agent.plist" 2>/dev/null || true
    launchctl load "$HOME/Library/LaunchAgents/$agent.plist"
done

echo ""
echo "✅ SessionHawk installed — look for the hawk in your menu bar."
echo "   • Grant the notification permission when macOS asks."
echo "   • Already-running Claude sessions: open /hooks once (or restart them)."
echo "   • Uninstall anytime: $RES/scripts/uninstall.sh"
