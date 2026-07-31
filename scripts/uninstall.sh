#!/bin/bash
# uninstall.sh — removes SessionHawk: launchd agents, Claude Code hooks,
# and the app itself. Settings backups are left in place.

set -uo pipefail

echo "🦅 Uninstalling SessionHawk..."

for agent in com.sessionhawk.app com.sessionhawk.feeder; do
    plist="$HOME/Library/LaunchAgents/$agent.plist"
    if [ -f "$plist" ]; then
        launchctl unload "$plist" 2>/dev/null
        rm -f "$plist"
        echo "  removed $agent"
    fi
done

pkill -f feed-live-sessions.sh 2>/dev/null
pkill -x SessionHawk 2>/dev/null

SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
    tmp=$(mktemp)
    jq '
      .hooks |= (to_entries | map(
        .value |= (map(.hooks |= map(select((.command // "") | test("sessionhawk-claude-hook") | not))
                      | select(.hooks | length > 0)))
      ) | map(select(.value | length > 0)) | from_entries)
    ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    echo "  removed Claude Code hooks from $SETTINGS"
fi

rm -rf /Applications/SessionHawk.app
echo "✅ Done. (settings backups from install were kept)"
