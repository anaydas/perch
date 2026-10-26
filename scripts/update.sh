#!/bin/bash
# Updates Perch: pulls the latest main from GitHub and reinstalls it. Your shelf and settings are kept.
#
#   ./scripts/update.sh            pull main and reinstall (skips the rebuild if nothing changed)
#   ./scripts/update.sh --force    reinstall even if there's nothing new
#   ./scripts/update.sh --branch   update whatever branch you're on instead of requiring main
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
cd "$REPO_DIR"

force=false
any_branch=false
for arg in "$@"; do
    case "$arg" in
        --force) force=true ;;
        --branch) any_branch=true ;;
        -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg (try --help)"; exit 1 ;;
    esac
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Not a git repository: $REPO_DIR"; exit 1; }

branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$branch" != "main" ] && ! $any_branch; then
    echo "You're on branch '$branch', not main."
    echo "Switch first (git switch main), or update this branch with:  ./scripts/update.sh --branch"
    exit 1
fi

# Never overwrite your own changes.
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "You have uncommitted changes:"
    git status --short
    echo
    echo "Commit or stash them first (git stash), then run this again."
    exit 1
fi

echo "→ Fetching the latest ${branch}…"
git fetch --quiet origin "$branch"
before=$(git rev-parse HEAD)
remote=$(git rev-parse "origin/$branch")

if [ "$before" = "$remote" ]; then
    echo "✓ Already up to date ($(git log -1 --format='%h %s'))"
    if ! $force; then
        echo "Nothing to install. Run with --force to reinstall anyway."
        exit 0
    fi
else
    if ! git merge-base --is-ancestor "$before" "$remote"; then
        echo "Your local $branch has commits that aren't on GitHub, so it can't simply move forward."
        echo "Push them (git push) or sort it out with git, then run this again."
        exit 1
    fi
    echo "New changes:"
    git log --format='  • %s' "$before..$remote"
    git merge --ff-only --quiet "origin/$branch"
    echo "✓ Updated to $(git log -1 --format='%h')"
fi

# Keep the Claude usage meters up to date if they were set up before.
install_args=()
[ -f "$CLAUDE_DIR/perch/statusline.sh" ] && install_args+=(--with-claude-usage)

echo
"$REPO_DIR/scripts/install.sh" "${install_args[@]+"${install_args[@]}"}"
