#!/bin/bash
# Builds Perch, installs it to /Applications and opens it.
#
#   ./scripts/install.sh                      build, install, open
#   ./scripts/install.sh --with-claude-usage  also set up the Claude plan usage meters
#
# Claude Code session cards work without any setup. The usage meters (5-hour and weekly limits)
# need a Claude Code status line that saves the numbers for Perch; --with-claude-usage installs it.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
with_usage=false
for arg in "$@"; do
    case "$arg" in
        --with-claude-usage) with_usage=true ;;
        -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg (try --help)"; exit 1 ;;
    esac
done

if ! command -v swift >/dev/null; then
    echo "Swift isn't installed. Install the Command Line Tools first:  xcode-select --install"
    exit 1
fi

echo "→ Building Perch…"
"$REPO_DIR/scripts/build-app.sh" >/dev/null
echo "✓ Built"

echo "→ Installing to /Applications…"
pkill -x Perch 2>/dev/null && sleep 1 || true
rm -rf /Applications/Perch.app
cp -R "$REPO_DIR/build/Perch.app" /Applications/
# Register it so "Add to Perch" shows up in the Services menu.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Perch.app 2>/dev/null || true
/System/Library/CoreServices/pbs -update 2>/dev/null || true
echo "✓ Installed /Applications/Perch.app"

if $with_usage; then
    echo "→ Setting up Claude usage meters…"
    # Claude is off by default in Perch; this setup is for people who use it, so switch it on.
    defaults write com.anaydas.Perch showClaude -bool true
    if ! command -v jq >/dev/null; then
        echo "! jq not found (it ships with macOS 15; on older macOS: brew install jq). Skipping usage setup."
    else
        mkdir -p "$CLAUDE_DIR/perch"
        cp "$REPO_DIR/scripts/claude-statusline.sh" "$CLAUDE_DIR/perch/statusline.sh"
        chmod +x "$CLAUDE_DIR/perch/statusline.sh"
        settings="$CLAUDE_DIR/settings.json"
        [ -f "$settings" ] || echo '{}' > "$settings"
        current=$(jq -r '.statusLine.command // empty' "$settings")
        if [ -n "$current" ] && [[ "$current" != *"/perch/statusline.sh" ]]; then
            echo "! You already have a Claude Code status line ($current); left it as is."
            echo "  To use Perch's instead, set statusLine.command in $settings to $CLAUDE_DIR/perch/statusline.sh"
        else
            cp "$settings" "$CLAUDE_DIR/perch/settings.backup.json"
            jq --arg cmd "$CLAUDE_DIR/perch/statusline.sh" '. + {statusLine: {type: "command", command: $cmd}}' \
                "$CLAUDE_DIR/perch/settings.backup.json" > "$settings"
            echo "✓ Claude Code status line set (previous settings saved to $CLAUDE_DIR/perch/settings.backup.json)"
            echo "  Usage appears after your next message in a new Claude Code session."
        fi
    fi
fi

open /Applications/Perch.app
echo
echo "Perch is running: look for the bird in the menu bar and the island at the top of the screen."
echo "Allow access to your Documents/Desktop folder when macOS asks (that's where screenshots are saved)."
