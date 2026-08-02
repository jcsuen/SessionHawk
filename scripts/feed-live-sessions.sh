#!/bin/bash
# feed-live-sessions.sh
# Discovers running AI agent CLI processes (Claude Code, Gemini, Codex) and
# sends heartbeats to SessionHawk every POLL_INTERVAL seconds.
#
# Heartbeats carry NO state — precise state (working / waitingForInput) comes
# from the Claude Code hooks (sessionhawk-claude-hook.sh). The heartbeat's job
# is discovery, keep-alive, and context-usage refresh. Claude, Gemini, and
# Codex sessions get context tokens + mtime-reconciled state from their
# transcripts; cursor-agent is presence-only.
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

# Gemini CLI models are 1M-context; override with SH_GEMINI_CONTEXT_LIMIT.
GEMINI_CONTEXT_LIMIT=${SH_GEMINI_CONTEXT_LIMIT:-1000000}

# Leaderboard (opt-in): create ~/.sessionhawk/leaderboard containing a nickname
# to appear on https://paulobuilds.com/sessionhawk/leaderboard. Only the
# nickname, daily output-token/turn tallies, and live agent count are sent,
# keyed by a random install id. Delete the file to leave the board.
STATE_DIR="$HOME/.sessionhawk"
mkdir -p "$STATE_DIR"
[ -s "$STATE_DIR/id" ] || uuidgen | tr '[:upper:]' '[:lower:]' > "$STATE_DIR/id" 2>/dev/null
DEVICE_ID=$(cat "$STATE_DIR/id" 2>/dev/null)
BOARD_NAME=""
[ -s "$STATE_DIR/leaderboard" ] && BOARD_NAME=$(head -c 64 "$STATE_DIR/leaderboard" | tr -cd 'A-Za-z0-9_ .-' | cut -c1-24)

# Today's totals from all Claude transcripts; feeds the app header and (if
# opted in) the leaderboard. Heavier than a heartbeat, so throttled by caller.
publish_daily() {
    local today out_turns out turns
    today=$(date +%Y-%m-%d)
    out_turns=$(find "$HOME/.claude/projects" -name '*.jsonl' -mtime -2 -exec cat {} + 2>/dev/null \
        | jq -Rrs --arg today "$today" '
            [ split("\n")[] | fromjson? | select((.timestamp // "") | startswith($today)) | .message.usage // empty ]
            | "\(map(.output_tokens // 0) | add // 0) \(length)"' 2>/dev/null)
    out=${out_turns%% *}
    turns=${out_turns##* }
    [ -n "$out" ] && [ "$out" -ge 0 ] 2>/dev/null || return
    curl -s -m 2 -X POST http://localhost:9422/v1/daily -H "Content-Type: application/json" \
        -d "{\"outputTokens\": $out, \"turns\": $turns}" >/dev/null 2>&1
    if [ -n "$BOARD_NAME" ] && [ -n "$DEVICE_ID" ]; then
        curl -s -m 5 -X POST "https://paulobuilds.com/sessionhawk/leaderboard" \
            -H "Content-Type: application/json" \
            -d "{\"id\":\"$DEVICE_ID\",\"name\":\"$BOARD_NAME\",\"day\":\"$today\",\"out\":$out,\"turns\":$turns,\"agents\":$AGENT_COUNT}" \
            >/dev/null 2>&1
    fi
    echo "daily: ${out} output tokens, ${turns} turns${BOARD_NAME:+ (→ leaderboard as $BOARD_NAME)}"
}

# Account usage limits → POST /v1/limits, one payload per provider.
# Claude: the statusline script maintains ~/.sessionhawk/limits.json from the
# OAuth usage endpoint — refresh it here too so the app works without the
# statusline. Codex: rollouts self-report rate_limits in token_count events.
STATUSLINE_SCRIPT="$(cd "$(dirname "$0")" && pwd)/sessionhawk-statusline.sh"
publish_limits() {
    "$STATUSLINE_SCRIPT" --refresh >/dev/null 2>&1
    if [ -f "$STATE_DIR/limits.json" ]; then
        jq -c '{provider: "claude",
                limits: [ .limits[] | {kind, percent, resetsAtEpoch: .reset} ]}' \
            "$STATE_DIR/limits.json" 2>/dev/null \
        | curl -s -m 2 -X POST http://localhost:9422/v1/limits \
            -H "Content-Type: application/json" -d @- >/dev/null 2>&1
    fi

    local rollout
    rollout=$(find "$HOME/.codex/sessions" -name 'rollout-*.jsonl' -mtime -2 2>/dev/null \
              | xargs ls -t 2>/dev/null | head -n 1)
    if [ -n "$rollout" ]; then
        tail -n 400 "$rollout" 2>/dev/null | jq -Rrs '
            [ split("\n")[] | fromjson? | select(.payload.type? == "token_count")
              | .payload.rate_limits // empty ] | last // empty
            | {provider: "codex", limits: [
                (.primary // empty),
                (.secondary // empty)
              ] | map({
                  kind: (if .window_minutes <= 360 then "session"
                         elif .window_minutes <= 10080 then "weekly_all"
                         else "monthly" end),
                  percent: .used_percent,
                  resetsAtEpoch: .resets_at
              })}
            | select(.limits | length > 0)' 2>/dev/null \
        | curl -s -m 2 -X POST http://localhost:9422/v1/limits \
            -H "Content-Type: application/json" -d @- >/dev/null 2>&1
    fi
}

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

# Newest Gemini CLI chat transcript for a working directory. The project dir
# under ~/.gemini/tmp/ is sha256(cwd) on current Gemini versions, or the
# lowercased basename of the cwd on older ones — try both.
gemini_transcript() {
    local cwd="$1" dir
    for dir in "$(printf '%s' "$cwd" | shasum -a 256 | cut -d' ' -f1)" \
               "$(basename "$cwd" | tr '[:upper:]' '[:lower:]')"; do
        if [ -d "$HOME/.gemini/tmp/$dir/chats" ]; then
            ls -t "$HOME/.gemini/tmp/$dir/chats"/*.jsonl 2>/dev/null | head -n 1
            return
        fi
    done
}

# Last per-turn token record in a Gemini chat: "tokens":{input,output,...,total}.
# total = context used on the last turn (input already includes cached).
gemini_tokens() {
    local transcript="$1"
    tail -n 200 "$transcript" 2>/dev/null | jq -Rr '
        fromjson? | .tokens? // empty | select(.total != null)
        | "\(.total) \(.output // 0)"' 2>/dev/null | tail -n 1
}

# Newest Codex rollout whose session_meta cwd matches; only files touched in
# the last 2 days are considered (first line holds the cwd).
codex_transcript() {
    local cwd="$1" f meta_cwd
    for f in $(find "$HOME/.codex/sessions" -name 'rollout-*.jsonl' -mtime -2 2>/dev/null \
               | xargs ls -t 2>/dev/null); do
        meta_cwd=$(head -n 1 "$f" 2>/dev/null | jq -r '.payload.cwd // empty' 2>/dev/null)
        if [ "$meta_cwd" = "$cwd" ]; then
            echo "$f"
            return
        fi
    done
}

# Last token_count event in a Codex rollout: "used output window".
# last_token_usage.total_tokens = context used; model_context_window = limit.
codex_tokens() {
    local transcript="$1"
    tail -n 400 "$transcript" 2>/dev/null | jq -Rr '
        fromjson? | select(.payload.type? == "token_count") | .payload.info // empty
        | "\(.last_token_usage.total_tokens // 0) \(.last_token_usage.output_tokens // 0) \(.model_context_window // 0)"' \
        2>/dev/null | tail -n 1
}

# Cumulative session totals ("output turns") for the mini-stats row in the
# app's detail popover. Whole-file parses, but transcripts are a few MB max.
claude_session_totals() {
    jq -Rrs '[ split("\n")[] | fromjson? | select(.isSidechain != true)
               | .message.usage // empty | select(.input_tokens != null) ]
             | "\(map(.output_tokens // 0) | add // 0) \(length)"' "$1" 2>/dev/null
}

gemini_session_totals() {
    jq -Rrs '[ split("\n")[] | fromjson? | .tokens? // empty | select(.total != null) ]
             | "\(map(.output // 0) | add // 0) \(length)"' "$1" 2>/dev/null
}

# Codex reports cumulative output itself (total_token_usage in the last
# token_count event); turns = number of token_count events.
codex_session_totals() {
    jq -Rrs '[ split("\n")[] | fromjson? | select(.payload.type? == "token_count") | .payload.info ]
             | "\(last.total_token_usage.output_tokens // 0) \(length)"' "$1" 2>/dev/null
}

# State from transcript activity, aware of the state the app currently shows
# (fetched from GET /v1/sessions each scan). Rules:
#   fresh mtime (<20s)                  -> working (streaming)
#   shown "working" but quiet >=30s     -> idle (not generating; stale state)
#   quiet >=180s                        -> idle
#   otherwise                           -> no state; preserves hook-set states.
# Only hooks may claim waitingForInput: a quiet transcript can also mean the
# session waits on background monitors/tasks and needs nothing from the user.
transcript_state() {
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

    local tokens_json="" state_json="" usage="" state="" transcript="" limit=""
    case "$provider" in
        claude)
            transcript=$(claude_transcript "$cwd")
            limit=$CONTEXT_LIMIT
            [ -n "$transcript" ] && usage=$(claude_tokens "$transcript")
            ;;
        gemini)
            transcript=$(gemini_transcript "$cwd")
            limit=$GEMINI_CONTEXT_LIMIT
            [ -n "$transcript" ] && usage=$(gemini_tokens "$transcript")
            ;;
        codex)
            transcript=$(codex_transcript "$cwd")
            if [ -n "$transcript" ]; then
                usage=$(codex_tokens "$transcript")
                limit=${usage##* }          # third field: model_context_window
                usage=${usage% *}           # keep "used output"
                [ "$limit" -gt 0 ] 2>/dev/null || { usage=""; limit=""; }
            fi
            ;;
    esac
    if [ -n "$usage" ] && [ -n "$limit" ]; then
        tokens_json=", \"inputTokens\": ${usage%% *}, \"outputTokens\": ${usage##* }, \"totalLimit\": $limit"
        local totals
        totals=$("${provider}_session_totals" "$transcript")
        if [ -n "$totals" ]; then
            tokens_json="$tokens_json, \"sessionOutputTokens\": ${totals%% *}, \"sessionTurns\": ${totals##* }"
        fi
    fi
    if [ -n "$transcript" ]; then
        local current
        current=$(printf '%s\n' "$CURRENT_STATES" | awk -v p="$pid" '$1 == p {print $2}')
        state=$(transcript_state "$transcript" "$current")
        [ -n "$state" ] && state_json=", \"state\": \"$state\""
    fi

    local title
    title=$(basename "$cwd")

    curl -s -m 2 -X POST "$SH_URL" -H "Content-Type: application/json" -d "{
        \"pid\": $pid,
        \"provider\": \"$provider\",
        \"terminalTitle\": \"$(escape_json "$title")\",
        \"workingDirectory\": \"$(escape_json "$cwd")\",
        \"commandLine\": \"$(escape_json "$cmd")\"$tokens_json$state_json
    }" >/dev/null 2>&1 && echo "heartbeat pid $pid ($provider${state:+, $state}) — $cwd ${usage:+[ctx ${usage%% *}/$limit]}"
    AGENT_COUNT=$((AGENT_COUNT + 1))
}

scan() {
    # Snapshot of the states the app currently shows, "pid state" per line
    CURRENT_STATES=$(curl -s -m 2 "http://localhost:9422/v1/sessions" 2>/dev/null \
        | jq -r '.[] | "\(.pid) \(.state)"' 2>/dev/null)

    AGENT_COUNT=0

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

if [ "${1:-}" = "--once" ]; then
    scan
    publish_daily
    publish_limits
    exit 0
fi

echo "🦅 SessionHawk feeder started (every ${POLL_INTERVAL}s, Ctrl-C to stop)"
TICK=0
while true; do
    scan
    # Daily totals are a full-transcript parse — refresh every 10th pass (~5 min)
    if [ $((TICK % 10)) -eq 0 ]; then
        publish_daily
        publish_limits
    fi
    TICK=$((TICK + 1))
    sleep "$POLL_INTERVAL"
done
