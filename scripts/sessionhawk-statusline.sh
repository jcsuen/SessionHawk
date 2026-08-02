#!/bin/bash
# sessionhawk-statusline.sh
# Claude Code statusline: model · dir · context % · usage-limit gauges.
#
# Wire into ~/.claude/settings.json:
#   "statusLine": {"type": "command", "command": "<path to this script>"}
#
# Limit data comes from the same endpoint the CLI's /usage screen calls,
# authenticated with the Claude Code OAuth token from the macOS Keychain.
# Fetches are cached in ~/.sessionhawk/limits.json for CACHE_TTL seconds and
# refreshed in the background so the statusline itself never blocks.
#
#   ./sessionhawk-statusline.sh --refresh   # force a cache refresh (used
#                                           # internally and by the feeder)

CACHE="$HOME/.sessionhawk/limits.json"
CACHE_TTL=300

refresh_cache() {
    local tok resp
    tok=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
        | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    [ -n "$tok" ] || return 1
    resp=$(curl -sf -m 5 https://api.anthropic.com/api/oauth/usage \
        -H "Authorization: Bearer $tok" \
        -H "anthropic-beta: oauth-2025-04-20") || return 1
    mkdir -p "$(dirname "$CACHE")"
    # Normalize the limits[] array; resets_at ISO → epoch (strip fraction/offset)
    jq --argjson ts "$(date +%s)" '{
        ts: $ts,
        limits: [ (.limits // [])[] | {
            kind, percent, severity,
            reset: ((.resets_at // "") | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z")
                    | try fromdateiso8601 catch null)
        } ]
    }' <<<"$resp" > "$CACHE.tmp" 2>/dev/null && mv "$CACHE.tmp" "$CACHE"
}

if [ "${1:-}" = "--refresh" ]; then
    refresh_cache
    exit $?
fi

input=$(cat)

model=$(jq -r '.model.display_name // .model.id // "Claude"' <<<"$input")
dir=$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$input")
transcript=$(jq -r '.transcript_path // empty' <<<"$input")

# Context %: last main-chain usage entry in the transcript (same parse as the
# SessionHawk hook), against the same limit detection.
ctx=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    used=$(tail -n 400 "$transcript" 2>/dev/null | jq -Rr '
        fromjson? | select(.isSidechain != true) | .message.usage? // empty
        | select(.input_tokens != null)
        | "\(.input_tokens + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))"' \
        2>/dev/null | tail -n 1)
    if [ -n "$used" ]; then
        if [ -n "$SH_CONTEXT_LIMIT" ]; then
            limit=$SH_CONTEXT_LIMIT
        elif jq -r '.model // ""' "$HOME/.claude/settings.json" 2>/dev/null | grep -q '\[1m\]'; then
            limit=1000000
        else
            limit=200000
        fi
        ctx=$((used * 100 / limit))
    fi
fi

# Stale or missing cache → refresh in the background, render with what we have.
now=$(date +%s)
cache_ts=$(jq -r '.ts // 0' "$CACHE" 2>/dev/null || echo 0)
if [ $((now - cache_ts)) -ge "$CACHE_TTL" ]; then
    ("$0" --refresh >/dev/null 2>&1 &)
fi

# Color a percentage by how close it is to the limit.
pct_colored() {
    local p=${1%.*}
    if [ "$p" -ge 85 ] 2>/dev/null; then printf '\033[31m%s%%\033[0m' "$1"      # red
    elif [ "$p" -ge 60 ] 2>/dev/null; then printf '\033[33m%s%%\033[0m' "$1"    # yellow
    else printf '%s%%' "$1"
    fi
}

# "2h10m" until an epoch, empty if past/unknown
until_epoch() {
    local target="$1" mins
    [ -n "$target" ] && [ "$target" != "null" ] || return
    mins=$(( (target - now) / 60 ))
    [ "$mins" -gt 0 ] || return
    if [ "$mins" -ge 1440 ]; then echo "$((mins / 1440))d"
    elif [ "$mins" -ge 60 ]; then echo "$((mins / 60))h$((mins % 60))m"
    else echo "${mins}m"
    fi
}

line="🦅 $model"
[ -n "$dir" ] && line="$line \033[2m·\033[0m $(basename "$dir")"
[ -n "$ctx" ] && line="$line \033[2m·\033[0m ctx $(pct_colored "$ctx")"

if [ -f "$CACHE" ]; then
    session=$(jq -r '[.limits[] | select(.kind == "session")][0] // empty | "\(.percent) \(.reset)"' "$CACHE" 2>/dev/null)
    weekly=$(jq -r '[.limits[] | select(.kind == "weekly_all")][0] // empty | "\(.percent) \(.reset)"' "$CACHE" 2>/dev/null)
    scoped=$(jq -r '[.limits[] | select(.kind == "weekly_scoped")][0].percent // empty' "$CACHE" 2>/dev/null)
    if [ -n "$session" ]; then
        rst=$(until_epoch "${session##* }")
        line="$line \033[2m·\033[0m 5h $(pct_colored "${session%% *}")${rst:+ \033[2m(↻$rst)\033[0m}"
    fi
    if [ -n "$weekly" ]; then
        wk_pct=${weekly%% *}
        line="$line \033[2m·\033[0m wk $(pct_colored "$wk_pct")"
        # Model-scoped weekly limit, shown when it's the tighter constraint
        if [ -n "$scoped" ] && [ "${scoped%.*}" -gt "${wk_pct%.*}" ] 2>/dev/null; then
            line="$line \033[2m(model $(pct_colored "$scoped"))\033[0m"
        fi
    fi
fi

printf '%b\n' "$line"
