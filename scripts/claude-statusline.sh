#!/bin/bash
# Claude Code status line for Perch.
# Claude Code pipes session info (JSON) to stdin after each update. This saves the
# plan usage (rate_limits) for Perch to show, and prints a short status line.
# Installed to ~/.claude/perch/statusline.sh and set as "statusLine" in ~/.claude/settings.json.

input=$(cat)
dir="$HOME/.claude/perch"
mkdir -p "$dir"

limits=$(printf '%s' "$input" | /usr/bin/jq -c '.rate_limits // empty | {five_hour, seven_day} | with_entries(select(.value != null))' 2>/dev/null)
if [ -n "$limits" ] && [ "$limits" != "{}" ]; then
    now=$(( $(date +%s) * 1000 ))
    tmp="$dir/usage.json.tmp.$$"
    printf '%s' "$limits" | /usr/bin/jq -c --argjson t "$now" '{updatedAt: $t} + .' > "$tmp" && mv -f "$tmp" "$dir/usage.json"
fi

printf '%s' "$input" | /usr/bin/jq -r '
    [ .model.display_name,
      (.rate_limits.five_hour.used_percentage | if . != null then "5h \(round)%" else empty end),
      (.rate_limits.seven_day.used_percentage | if . != null then "week \(round)%" else empty end)
    ] | map(select(. != null)) | join(" · ")' 2>/dev/null
