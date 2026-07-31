#!/bin/bash
# sessionhawk-claude-hook.sh <state>
# Claude Code hook: reads the hook JSON from stdin and reports precise session
# state + real context usage (parsed from the session transcript) to SessionHawk.
#
# Wire in ~/.claude/settings.json:
#   UserPromptSubmit -> working      Stop -> waitingForInput
#   Notification     -> waitingForInput   SessionEnd -> idle
#   PostToolUse      -> working  (keep-alive + fresh token counts during long turns)

SH_URL="http://localhost:9422/v1/event"
STATE="${1:-}"

# Context limit: SH_CONTEXT_LIMIT env wins; otherwise detect the 1M marker
# ("[1m]") in the configured model in ~/.claude/settings.json; else 200k.
detect_context_limit() {
    if [ -n "$SH_CONTEXT_LIMIT" ]; then
        echo "$SH_CONTEXT_LIMIT"
    elif jq -r '.model // ""' "$HOME/.claude/settings.json" 2>/dev/null | grep -q '\[1m\]'; then
        echo 1000000
    else
        echo 200000
    fi
}
CONTEXT_LIMIT=$(detect_context_limit)

# Capture the event time FIRST — hooks run async, so by the time the POST
# happens a newer event may already be in flight; the app orders by this.
TS=$(perl -MTime::HiRes=time -e 'printf("%.0f", time()*1000)')

INPUT=$(cat)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

# Walk up the process tree to find the claude CLI process this hook belongs to
pid=$$
CLAUDE_PID=""
for _ in 1 2 3 4 5 6 7 8; do
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -z "$pid" ] || [ "$pid" -le 1 ] && break
    if [ "$(ps -o comm= -p "$pid" 2>/dev/null)" = "claude" ]; then
        CLAUDE_PID=$pid
        break
    fi
done
[ -z "$CLAUDE_PID" ] && exit 0

# Context usage: last main-chain assistant usage entry in the transcript.
# Context consumed = input + cache_read + cache_creation tokens.
INPUT_TOKENS=""
OUTPUT_TOKENS=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    usage=$(tail -n 400 "$TRANSCRIPT" 2>/dev/null | jq -Rr '
        fromjson? | select(.isSidechain != true) | .message.usage? // empty
        | select(.input_tokens != null)
        | "\(.input_tokens + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)) \(.output_tokens // 0)"' \
        2>/dev/null | tail -n 1)
    if [ -n "$usage" ]; then
        INPUT_TOKENS=${usage%% *}
        OUTPUT_TOKENS=${usage##* }
    fi
fi

json="{\"pid\": $CLAUDE_PID, \"provider\": \"claude\", \"timestamp\": $TS"
[ -n "$STATE" ] && json="$json, \"state\": \"$STATE\""
if [ -n "$CWD" ]; then
    esc_cwd=$(printf '%s' "$CWD" | jq -Rr '@json')
    json="$json, \"workingDirectory\": $esc_cwd, \"terminalTitle\": $(basename "$CWD" | jq -Rr '@json')"
fi
if [ -n "$INPUT_TOKENS" ]; then
    json="$json, \"inputTokens\": $INPUT_TOKENS, \"outputTokens\": $OUTPUT_TOKENS, \"totalLimit\": $CONTEXT_LIMIT"
fi
json="$json}"

curl -s -m 2 -X POST "$SH_URL" -H "Content-Type: application/json" -d "$json" >/dev/null 2>&1
exit 0
