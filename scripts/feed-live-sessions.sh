#!/bin/bash
# feed-live-sessions.sh
# Discovers running AI agent CLI processes (Claude Code, Gemini, Codex) and
# sends heartbeats to SessionHawk every POLL_INTERVAL seconds.
#
# Heartbeats carry NO state — precise state (working / waitingForInput) comes
# from the Claude Code hooks (sessionhawk-claude-hook.sh). The heartbeat's job
# is discovery, keep-alive, and context-usage refresh for claude sessions.
#
# Usage:
#   ./scripts/feed-live-sessions.sh          # run in foreground
#   ./scripts/feed-live-sessions.sh --once   # single pass, then exit

SH_URL="http://localhost:9422/v1/event"
POLL_INTERVAL=30

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

escape_json() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    echo "$value"
}

# Newest Claude Code transcript for a working directory:
# ~/.claude/projects/<encoded-cwd>/*.jsonl
claude_transcript() {
    local cwd="$1"
    local encoded="${cwd//\//-}"
    encoded="${encoded//./-}"
    ls -t "$HOME/.claude/projects/$encoded"/*.jsonl 2>/dev/null | head -n 1
}

# Context usage: last main-chain usage entry in the transcript.
claude_tokens() {
    local transcript="$1"
    tail -n 400 "$transcript" 2>/dev/null | jq -Rr '
        fromjson? | select(.isSidechain != true) | .message.usage? // empty
        | select(.input_tokens != null)
        | "\(.input_tokens + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)) \(.output_tokens // 0)"' \
        2>/dev/null | tail -n 1
}

# State from transcript activity, aware of the state the app currently shows
# (fetched from GET /v1/sessions each scan). Rules:
#   fresh mtime (<20s)                  -> working (streaming)
#   shown "working" but quiet >=30s     -> idle (not generating; stale state)
#   quiet >=180s                        -> idle
#   otherwise                           -> no state; preserves hook-set states.
# Only hooks may claim waitingForInput: a quiet transcript can also mean the
# session waits on background monitors/tasks and needs nothing from the user.
claude_state() {
    local transcript="$1" current="$2"
    local mtime now age
    mtime=$(stat -f %m "$transcript" 2>/dev/null) || return
    now=$(date +%s)
    age=$((now - mtime))
    if [ "$age" -lt 20 ]; then
        echo "working"
    elif [ "$current" = "working" ] && [ "$age" -ge 30 ]; then
        echo "idle"
    elif [ "$age" -ge 180 ]; then
        echo "idle"
    fi
}

report_pid() {
    local pid="$1" provider="$2"

    local cwd
    cwd=$(lsof -a -d cwd -p "$pid" 2>/dev/null | awk 'NR==2 {print $NF}')
    # Skip daemons with no meaningful working directory (e.g. IDE extension helpers at /)
    [ -z "$cwd" ] || [ "$cwd" = "/" ] && return

    local cmd
    cmd=$(ps -o command= -p "$pid" 2>/dev/null | head -c 200)

    local tokens_json="" state_json="" usage="" state=""
    if [ "$provider" = "claude" ]; then
        local transcript
        transcript=$(claude_transcript "$cwd")
        if [ -n "$transcript" ]; then
            usage=$(claude_tokens "$transcript")
            if [ -n "$usage" ]; then
                tokens_json=", \"inputTokens\": ${usage%% *}, \"outputTokens\": ${usage##* }, \"totalLimit\": $CONTEXT_LIMIT"
            fi
            local current
            current=$(printf '%s\n' "$CURRENT_STATES" | awk -v p="$pid" '$1 == p {print $2}')
            state=$(claude_state "$transcript" "$current")
            [ -n "$state" ] && state_json=", \"state\": \"$state\""
        fi
    fi

    local title
    title=$(basename "$cwd")

    curl -s -m 2 -X POST "$SH_URL" -H "Content-Type: application/json" -d "{
        \"pid\": $pid,
        \"provider\": \"$provider\",
        \"terminalTitle\": \"$(escape_json "$title")\",
        \"workingDirectory\": \"$(escape_json "$cwd")\",
        \"commandLine\": \"$(escape_json "$cmd")\"$tokens_json$state_json
    }" >/dev/null 2>&1 && echo "heartbeat pid $pid ($provider${state:+, $state}) — $cwd ${usage:+[ctx ${usage%% *}/$CONTEXT_LIMIT]}"
}

scan() {
    # Snapshot of the states the app currently shows, "pid state" per line
    CURRENT_STATES=$(curl -s -m 2 "http://localhost:9422/v1/sessions" 2>/dev/null \
        | jq -r '.[] | "\(.pid) \(.state)"' 2>/dev/null)

    # ps comm matching instead of pgrep: some claude processes have an
    # accounting name pgrep -x misses (e.g. sessions launched via the
    # versioned binary rather than `claude --resume`).
    for pid in $(ps -axo pid=,comm= | awk '$2 == "claude" {print $1}'); do
        report_pid "$pid" "claude"
    done
    # Node-based CLIs (gemini, codex, cursor-agent) run as `node <path>/bin/<name>`,
    # so match the command line. Report only the top process of each tree —
    # these CLIs spawn worker children whose command line also matches.
    discover_by_cmd "bin/gemini" "gemini"
    discover_by_cmd "bin/codex" "codex"
    discover_by_cmd "bin/cursor-agent" "cursor"
}

discover_by_cmd() {
    local pattern="$1" provider="$2"
    local pids ppid
    pids=$(pgrep -f "$pattern" 2>/dev/null)
    [ -n "$pids" ] || return
    for pid in $pids; do
        ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        # Skip workers whose parent is also a match
        if printf '%s\n' "$pids" | grep -qx "$ppid"; then continue; fi
        report_pid "$pid" "$provider"
    done
}

if [ "$1" = "--once" ]; then
    scan
    exit 0
fi

echo "🦅 SessionHawk feeder started (every ${POLL_INTERVAL}s, Ctrl-C to stop)"
while true; do
    scan
    sleep "$POLL_INTERVAL"
done
