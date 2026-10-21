#!/bin/bash
# Removes Perch from this Mac: login item, app, shelf data and settings, the Claude Code
# status line it added, and its privacy permissions.
#
#   ./scripts/uninstall.sh              asks before removing anything
#   ./scripts/uninstall.sh --yes        no questions
#   ./scripts/uninstall.sh --keep-data  keep shelf items and settings (for a reinstall)
set -uo pipefail

BUNDLE_ID="com.anaydas.Perch"
OLD_BUNDLE_ID="com.anaydas.NotchShelf"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="$HOME/Library/Application Support/Perch"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CLAUDE_SETTINGS="$CLAUDE_DIR/settings.json"
STATUSLINE_DIR="$CLAUDE_DIR/perch"

assume_yes=false
keep_data=false
for arg in "$@"; do
    case "$arg" in
        --yes|-y) assume_yes=true ;;
        --keep-data) keep_data=true ;;
        -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg (try --help)"; exit 1 ;;
    esac
done

apps=()
for candidate in "/Applications/Perch.app" "$HOME/Applications/Perch.app" "$REPO_DIR/build/Perch.app"; do
    [ -d "$candidate" ] && apps+=("$candidate")
done

echo "This will remove Perch from this Mac:"
echo "  1. Its Launch at login item"
echo "  2. The running app"
if [ ${#apps[@]} -gt 0 ]; then
    for app in "${apps[@]}"; do echo "  3. $app"; done
else
    echo "  3. (no Perch.app found)"
fi
if $keep_data; then
    echo "  4. Shelf items and settings: kept (--keep-data)"
else
    echo "  4. Shelf items and settings: $DATA_DIR and the app's preferences"
fi
echo "  5. The Claude Code status line Perch added, and $STATUSLINE_DIR"
echo "  6. Its privacy permissions (folder access, Terminal/iTerm2 control)"
echo

if ! $assume_yes; then
    read -r -p "Continue? [y/N] " answer
    case "$answer" in [yY]|[yY][eE][sS]) ;; *) echo "Nothing removed."; exit 0 ;; esac
fi

# 1. Login item: ask the app to unregister itself (before it's deleted).
for app in "${apps[@]}"; do
    "$app/Contents/MacOS/Perch" --unregister-login-item >/dev/null 2>&1 && break
done
echo "✓ Launch at login turned off"

# 2. Quit.
if pgrep -x Perch >/dev/null; then
    pkill -x Perch
    for _ in 1 2 3 4 5; do pgrep -x Perch >/dev/null || break; sleep 0.5; done
    pgrep -x Perch >/dev/null && pkill -9 -x Perch
fi
echo "✓ Perch quit"

# 3. App bundles.
for app in "${apps[@]}"; do rm -rf "$app"; done
echo "✓ App removed"

# 4. Data and preferences.
if $keep_data; then
    echo "• Shelf items and settings kept"
else
    rm -rf "$DATA_DIR"
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1
    defaults delete "$OLD_BUNDLE_ID" >/dev/null 2>&1
    echo "✓ Shelf items and settings deleted"
fi

# 5. Claude Code status line: only remove it if it's Perch's.
if [ -f "$CLAUDE_SETTINGS" ] && command -v jq >/dev/null; then
    command=$(jq -r '.statusLine.command // empty' "$CLAUDE_SETTINGS" 2>/dev/null)
    if [[ "$command" == *"/perch/statusline.sh"* || "$command" == *"/notchshelf/statusline.sh"* ]]; then
        backup="$CLAUDE_SETTINGS.before-perch-uninstall"
        cp "$CLAUDE_SETTINGS" "$backup"
        if jq 'del(.statusLine)' "$backup" > "$CLAUDE_SETTINGS.tmp"; then
            mv "$CLAUDE_SETTINGS.tmp" "$CLAUDE_SETTINGS"
            echo "✓ Claude Code status line removed (previous settings saved to $backup)"
        else
            rm -f "$CLAUDE_SETTINGS.tmp"
            echo "! Couldn't edit $CLAUDE_SETTINGS; remove its \"statusLine\" entry by hand"
        fi
    elif [ -n "$command" ]; then
        echo "• Claude Code status line isn't Perch's; left as is"
    fi
elif [ -f "$CLAUDE_SETTINGS" ]; then
    echo "! jq not found: remove the \"statusLine\" entry from $CLAUDE_SETTINGS by hand"
fi
rm -rf "$STATUSLINE_DIR" "$CLAUDE_DIR/notchshelf"
echo "✓ Status line script removed"

# 6. Privacy permissions.
tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1
tccutil reset All "$OLD_BUNDLE_ID" >/dev/null 2>&1
echo "✓ Privacy permissions reset"

echo
echo "Perch is uninstalled. The source code in $REPO_DIR is untouched."
