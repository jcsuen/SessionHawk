#!/bin/bash
# install-hooks.sh [hook-script-path]
# Merges the SessionHawk Claude Code hooks into ~/.claude/settings.json.
# Idempotent (skips events that already have a sessionhawk hook) and makes a
# timestamped backup before touching anything.

set -euo pipefail

HOOK="${1:-/Applications/SessionHawk.app/Contents/Resources/scripts/sessionhawk-claude-hook.sh}"
SETTINGS="$HOME/.claude/settings.json"

if [ ! -f "$HOOK" ]; then
    echo "❌ hook script not found: $HOOK" >&2
    exit 1
fi

# JSON tooling: jq preferred, python3 fallback (ships with the Xcode CLT that
# every Mac running dev CLIs already has). Neither → bail before touching anything.
if command -v jq >/dev/null 2>&1; then
    MERGER=jq
elif command -v python3 >/dev/null 2>&1; then
    MERGER=python3
else
    echo "❌ need jq or python3 to merge hooks into $SETTINGS" >&2
    exit 1
fi

mkdir -p "$HOME/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# Refuse to touch a malformed settings file
if [ "$MERGER" = jq ]; then
    jq empty "$SETTINGS" 2>/dev/null || {
        echo "❌ $SETTINGS is not valid JSON — fix it first, nothing was changed" >&2; exit 1; }
else
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$SETTINGS" 2>/dev/null || {
        echo "❌ $SETTINGS is not valid JSON — fix it first, nothing was changed" >&2; exit 1; }
fi

backup="$SETTINGS.backup-sessionhawk-$(date +%Y%m%d%H%M%S)"
cp "$SETTINGS" "$backup"

tmp=$(mktemp)
if [ "$MERGER" = python3 ]; then
    python3 - "$HOOK" "$SETTINGS" > "$tmp" <<'PYEOF'
import json, sys

hook, path = sys.argv[1], sys.argv[2]
settings = json.load(open(path))
hooks = settings.setdefault("hooks", {})

def entry(state):
    return {"type": "command", "command": f"{hook} {state}", "timeout": 10, "async": True}

def ensure(event, matcher, state):
    groups = hooks.setdefault(event, [])
    for g in groups:
        for h in g.get("hooks", []):
            if "sessionhawk-claude-hook" in h.get("command", ""):
                return
    group = {"hooks": [entry(state)]}
    if matcher is not None:
        group["matcher"] = matcher
    groups.append(group)

ensure("UserPromptSubmit", None, "working")
ensure("Stop", None, "waitingForInput")
ensure("Notification", None, "waitingForInput")
ensure("SessionEnd", None, "idle")
ensure("PostToolUse", "*", "working")
json.dump(settings, sys.stdout, indent=2)
PYEOF
    mv "$tmp" "$SETTINGS"
    echo "✅ SessionHawk hooks installed into $SETTINGS (via python3)"
    echo "   (backup: $backup)"
    echo "   Already-running Claude sessions pick them up after /hooks or a restart."
    exit 0
fi

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
