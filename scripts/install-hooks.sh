#!/bin/bash
# install-hooks.sh [hook-script-path]
# Merges the SessionHawk Claude Code hooks into ~/.claude/settings.json.
# Idempotent (skips events that already have a sessionhawk hook) and makes a
# timestamped backup before touching anything.

set -euo pipefail

HOOK="${1:-/Applications/SessionHawk.app/Contents/Resources/scripts/sessionhawk-claude-hook.sh}"
SETTINGS="$HOME/.claude/settings.json"

if ! command -v jq >/dev/null 2>&1; then
    echo "❌ jq is required (brew install jq)" >&2
    exit 1
fi
if [ ! -f "$HOOK" ]; then
    echo "❌ hook script not found: $HOOK" >&2
    exit 1
fi

mkdir -p "$HOME/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# Refuse to touch a malformed settings file
if ! jq empty "$SETTINGS" 2>/dev/null; then
    echo "❌ $SETTINGS is not valid JSON — fix it first, nothing was changed" >&2
    exit 1
fi

backup="$SETTINGS.backup-sessionhawk-$(date +%Y%m%d%H%M%S)"
cp "$SETTINGS" "$backup"

tmp=$(mktemp)
jq --arg hook "$HOOK" '
  def entry(state): {type: "command", command: ($hook + " " + state), timeout: 10, async: true};
  def ensure(ev; m; state):
    .hooks[ev] = ((.hooks[ev] // [])
      | if (map(.hooks[]?.command // "") | any(test("sessionhawk-claude-hook"))) then .
        else . + [ (if m == null then {hooks: [entry(state)]}
                    else {matcher: m, hooks: [entry(state)]} end) ]
        end);
  .hooks //= {}
  | ensure("UserPromptSubmit"; null; "working")
  | ensure("Stop"; null; "waitingForInput")
  | ensure("Notification"; null; "waitingForInput")
  | ensure("SessionEnd"; null; "idle")
  | ensure("PostToolUse"; "*"; "working")
' "$SETTINGS" > "$tmp"
mv "$tmp" "$SETTINGS"

echo "✅ SessionHawk hooks installed into $SETTINGS"
echo "   (backup: $backup)"
echo "   Already-running Claude sessions pick them up after /hooks or a restart."
