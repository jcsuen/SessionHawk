#!/bin/bash
# sessionhawk-heh.sh — human-equivalent hours (HEH) estimator.
#
# Estimates how many hours a competent human developer would need to produce
# the code you shipped (committed) in a day. The honest output metric behind
# "real leverage" = HEH / focused hours.
#
# Two layers:
#   1. Deterministic band from filtered diff size (auditable floor/ceiling).
#   2. One `claude -p` call judging all commits against a fixed rubric with
#      calibration anchors; each estimate is clamped into its layer-1 band.
#
# Per-commit results are written to ~/.sessionhawk/heh/<day>.json so the
# headline number is always auditable. Only {id, day, humanHours} leaves the
# machine (POST to the paulobuilds workday endpoint).
#
# Usage:
#   sessionhawk-heh.sh                # yesterday's-complete day = today (run at 23:45)
#   sessionhawk-heh.sh --day 2026-07-28   # backfill a specific day

set -uo pipefail

STATE_DIR="$HOME/.sessionhawk"
AUDIT_DIR="$STATE_DIR/heh"
ENDPOINT="https://paulobuilds.com/sessionhawk/workday"
MAX_COMMIT_LINES=20000     # bigger than this = generated, skipped
EXCERPT_LINES=300          # max diff lines per commit sent to the judge
TOTAL_EXCERPT_LINES=3000   # max diff lines across all commits

DAY=$(date +%Y-%m-%d)
[ "${1:-}" = "--day" ] && [ -n "${2:-}" ] && DAY="$2"

DEVICE_ID=$(cat "$STATE_DIR/id" 2>/dev/null)
GIT_EMAIL=$(git config --global user.email 2>/dev/null)
mkdir -p "$AUDIT_DIR"

# Repos touched that day: unique cwd fields in that day's transcript entries.
repos() {
    cat "$HOME/.claude/projects"/*/*.jsonl 2>/dev/null | jq -Rr --arg t "$DAY" \
        'fromjson? | select((.timestamp // "") | startswith($t)) | .cwd // empty' 2>/dev/null \
    | sort -u | while read -r d; do
        [ -d "$d/.git" ] && echo "$d"
    done
}

# Filter noise from numstat: lockfiles, generated, vendored, build output.
NOISE='lock|dist/|\.build/|node_modules/|vendor/|\.min\.|generated|\.icns|\.png|\.jpg|\.zip|pnpm-lock|package-lock'

commits_json="[]"
total_excerpt=0
seen_patch_ids=""

for repo in $(repos); do
    for sha in $(git -C "$repo" log --pretty=%H --since="$DAY 00:00" --until="$DAY 23:59:59" \
                     --author="$GIT_EMAIL" 2>/dev/null); do
        pid=$(git -C "$repo" show "$sha" 2>/dev/null | git patch-id --stable 2>/dev/null | cut -d' ' -f1)
        case "$seen_patch_ids" in *"$pid"*) continue ;; esac
        seen_patch_ids="$seen_patch_ids $pid"

        # Meaningful lines: adds+dels excluding noise paths and binary files
        lines=$(git -C "$repo" show --numstat --format= "$sha" 2>/dev/null \
            | grep -Ev "$NOISE" | awk '$1 != "-" {s += $1 + $2} END {print s + 0}')
        [ "$lines" -gt 0 ] 2>/dev/null || continue
        [ "$lines" -le "$MAX_COMMIT_LINES" ] || continue

        msg=$(git -C "$repo" log -1 --pretty=%s "$sha" 2>/dev/null)

        excerpt=""
        if [ "$total_excerpt" -lt "$TOTAL_EXCERPT_LINES" ]; then
            excerpt=$(git -C "$repo" show --format= "$sha" -- . \
                        $(printf '%s\n' ':(exclude)*lock*' ':(exclude)dist' ':(exclude)node_modules') 2>/dev/null \
                      | head -n "$EXCERPT_LINES")
            total_excerpt=$((total_excerpt + $(printf '%s\n' "$excerpt" | wc -l)))
        fi

        # Layer-1 band: 30–300 final meaningful lines per human hour,
        # minimum ceiling 15 min for any real commit.
        commits_json=$(jq -n --argjson acc "$commits_json" \
            --arg sha "${sha:0:10}" --arg repo "$(basename "$repo")" \
            --arg msg "$msg" --argjson lines "$lines" --arg excerpt "$excerpt" '
            $acc + [{
                sha: $sha, repo: $repo, msg: $msg, lines: $lines,
                band: [($lines / 300 * 100 | floor) / 100,
                       ([($lines / 30), 0.25] | max * 100 | ceil) / 100],
                excerpt: $excerpt
            }]')
    done
done

n=$(jq 'length' <<<"$commits_json")
if [ "$n" -eq 0 ]; then
    echo "heh $DAY: no commits — nothing shipped, nothing estimated"
    exit 0
fi

prompt="You are estimating how long a competent MID-LEVEL human developer would take to produce each git commit below, starting from the same codebase state. Include thinking, reading existing code, testing, and debugging — not just typing. Deleted or refactored code counts as work. Judge the CHANGE itself, never who or what wrote it.

Calibration anchors:
- config tweak or one-line fix: 0.25h
- small function + wiring it in: 1h
- new endpoint/feature with error handling, touching several files: 3h
- substantial subsystem (new module + integration + edge cases): 6-10h

Commits (JSON; 'excerpt' is a truncated diff, 'lines' is meaningful lines changed):
$(jq '[.[] | {sha, repo, msg, lines, excerpt}]' <<<"$commits_json")

Reply with ONLY a JSON array, no prose, no code fences:
[{\"sha\": \"...\", \"hours\": 1.5, \"basis\": \"one short sentence\"}]"

estimates=$(claude -p "$prompt" 2>/dev/null | sed 's/^```json//; s/^```//; /^$/d')
echo "$estimates" | jq -e 'type == "array"' >/dev/null 2>&1 || {
    echo "heh $DAY: judge returned unparseable output; audit skipped" >&2
    exit 1
}

# Clamp each estimate into its layer-1 band; sum.
audit=$(jq -n --argjson commits "$commits_json" --argjson est "$estimates" '
    ($est | map({key: .sha, value: .}) | from_entries) as $by
    | ($commits | map(
        . as $c | ($by[$c.sha] // {hours: $c.band[0], basis: "no estimate — floor used"}) as $e
        | {sha: $c.sha, repo: $c.repo, msg: $c.msg, lines: $c.lines, band: $c.band,
           llm: $e.hours, basis: $e.basis,
           hours: ([([$e.hours, $c.band[0]] | max), $c.band[1]] | min)}
      )) as $rows
    | {day: null, commits: $rows, totalHours: (($rows | map(.hours) | add) * 10 | round / 10)}
    ' | jq --arg day "$DAY" '.day = $day')

echo "$audit" > "$AUDIT_DIR/$DAY.json"
heh=$(jq -r '.totalHours' <<<"$audit")

if [ -n "$DEVICE_ID" ]; then
    nc=$(jq -r '.commits | length' <<<"$audit")
    curl -s -m 5 -X POST "$ENDPOINT" -H "Content-Type: application/json" \
        -d "{\"id\":\"$DEVICE_ID\",\"day\":\"$DAY\",\"humanHours\":$heh,\"commits\":$nc}" >/dev/null 2>&1
fi
echo "heh $DAY: $n commits ≈ ${heh}h human-equivalent (audit: $AUDIT_DIR/$DAY.json)"
