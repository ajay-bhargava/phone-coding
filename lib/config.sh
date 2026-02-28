#!/usr/bin/env bash
# Shared configuration for phone-coding

# Paths
REPOS_DIR="$HOME/repos"
SKILLS_DIR="$HOME/.config/agents/skills"
AMP_CONFIG_DIR="$HOME/.config/amp"
SESSIONS_DB="$HOME/.local/state/phone-coding/sessions.json"
LAUNCH_LOG="$HOME/.local/state/phone-coding/launch.log"

# Defaults
DEFAULT_AMP_MODE="smart"
DEFAULT_GH_LIMIT=50
TMUX_SESSION_PREFIX="amp"

# GH_CLASSIC_TOKEN is used only for org membership listing (read:org scope)
# gh CLI auth should use the fine-grained PAT for repo access
GH_CLASSIC_TOKEN="${GH_CLASSIC_TOKEN:-}"

# Ensure state directory exists
mkdir -p "$(dirname "$SESSIONS_DB")"

log() {
  echo "[$(date '+%H:%M:%S')] $*" >> "$LAUNCH_LOG"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required but not installed"
}
