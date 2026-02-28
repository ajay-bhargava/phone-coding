# Sprite Remote Amp — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a phone-controllable remote Amp execution environment on Sprites, accessed via Echo + Tailscale SSH, with an interactive `launch` TUI for repo selection, task dispatch, and PR creation.

**Architecture:** One persistent "home" Sprite VM acts as a cloud dev machine. Tailscale provides SSH access from iPhone (Echo app). A `launch` CLI tool (bash + gum) handles repo selection, Amp session management, and status tracking. All execution happens inside tmux sessions that survive disconnects.

**Tech Stack:** Bash, gum (Charmbracelet), Sprites CLI/API, Tailscale, Amp CLI, gh CLI, tmux, jq

---

## File Map

```
phone-coding/
├── bootstrap.sh              # One-time Sprite provisioning (runs inside Sprite)
├── setup-local.sh            # Run from Mac to provision Sprite remotely
├── launch                    # Main TUI launcher (installed to ~/bin/launch on Sprite)
├── lib/
│   ├── config.sh             # Shared config (paths, defaults)
│   ├── repo.sh               # Repo management functions
│   ├── session.sh            # tmux session management + tracking
│   └── pr.sh                 # PR creation and status
├── templates/
│   ├── fire-and-forget.md    # Amp prompt template for fire & forget
│   └── ralph-mode.md         # Amp prompt template for Ralph Mode
├── docs/
│   └── plans/                # This plan
└── README.md
```

---

## Task 1: Shared Config and Constants

**Files:**
- Create: `lib/config.sh`

**Step 1: Create the config file**

```bash
#!/usr/bin/env bash
# Shared configuration for sprite-remote

# Paths
REPOS_DIR="$HOME/repos"
SKILLS_DIR="$HOME/.config/agents/skills"
AMP_CONFIG_DIR="$HOME/.config/amp"
SESSIONS_DB="$HOME/.local/state/sprite-remote/sessions.json"
LAUNCH_LOG="$HOME/.local/state/sprite-remote/launch.log"

# Defaults
DEFAULT_AMP_MODE="smart"
DEFAULT_GH_LIMIT=50
TMUX_SESSION_PREFIX="amp"

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
```

**Step 2: Verify it sources cleanly**

Run: `bash -c 'source lib/config.sh && echo $REPOS_DIR'`
Expected: Prints a path ending in `/repos`

**Step 3: Commit**

```bash
git add lib/config.sh
git commit -m "feat: add shared config for sprite-remote"
```

---

## Task 2: Repo Management Library

**Files:**
- Create: `lib/repo.sh`

**Step 1: Create repo management functions**

```bash
#!/usr/bin/env bash
# Repo listing, cloning, and management

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# List repos from GitHub via gh CLI
list_repos() {
  local limit="${1:-$DEFAULT_GH_LIMIT}"
  gh repo list --json nameWithOwner,url,description,updatedAt \
    --limit "$limit" \
    --order desc \
    --sort updated \
    -q '.[] | .nameWithOwner'
}

# List repos from a specific org
list_org_repos() {
  local org="$1"
  local limit="${2:-$DEFAULT_GH_LIMIT}"
  gh repo list "$org" --json nameWithOwner,url,description,updatedAt \
    --limit "$limit" \
    --order desc \
    --sort updated \
    -q '.[] | .nameWithOwner'
}

# Ensure repo is cloned and up to date. Prints local path.
ensure_repo() {
  local repo="$1"  # e.g., "batstoi/my-app"
  local name="${repo##*/}"
  local local_path="$REPOS_DIR/$name"

  if [ -d "$local_path/.git" ]; then
    log "Pulling latest for $repo"
    git -C "$local_path" pull --rebase --quiet 2>/dev/null || true
  else
    log "Cloning $repo"
    mkdir -p "$REPOS_DIR"
    gh repo clone "$repo" "$local_path" -- --quiet
  fi

  echo "$local_path"
}

# Get the default branch for a repo
get_default_branch() {
  local repo_path="$1"
  git -C "$repo_path" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
    | sed 's@^refs/remotes/origin/@@'
}
```

**Step 2: Verify syntax**

Run: `bash -n lib/repo.sh`
Expected: No output (no syntax errors)

**Step 3: Commit**

```bash
git add lib/repo.sh
git commit -m "feat: add repo management library"
```

---

## Task 3: Session Management Library

**Files:**
- Create: `lib/session.sh`

**Step 1: Create session tracking functions**

```bash
#!/usr/bin/env bash
# tmux session management and tracking

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

init_sessions_db() {
  [ -f "$SESSIONS_DB" ] || echo '[]' > "$SESSIONS_DB"
}

# Record a new session. Prints the tmux session name.
record_session() {
  init_sessions_db
  local repo="$1" mode="$2" path="$3" branch="$4"
  local session_name="${TMUX_SESSION_PREFIX}-${repo##*/}"

  local entry
  entry=$(jq -n \
    --arg repo "$repo" \
    --arg mode "$mode" \
    --arg path "$path" \
    --arg branch "$branch" \
    --arg session "$session_name" \
    --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{repo: $repo, mode: $mode, path: $path, branch: $branch,
      session: $session, started: $started, status: "running", pr: null}')

  jq --argjson entry "$entry" '. += [$entry]' "$SESSIONS_DB" > "${SESSIONS_DB}.tmp" \
    && mv "${SESSIONS_DB}.tmp" "$SESSIONS_DB"

  echo "$session_name"
}

update_session_status() {
  local session_name="$1" status="$2"
  jq --arg s "$session_name" --arg st "$status" \
    '(.[] | select(.session == $s)).status = $st' \
    "$SESSIONS_DB" > "${SESSIONS_DB}.tmp" \
    && mv "${SESSIONS_DB}.tmp" "$SESSIONS_DB"
}

update_session_pr() {
  local session_name="$1" pr_url="$2"
  jq --arg s "$session_name" --arg pr "$pr_url" \
    '(.[] | select(.session == $s)).pr = $pr' \
    "$SESSIONS_DB" > "${SESSIONS_DB}.tmp" \
    && mv "${SESSIONS_DB}.tmp" "$SESSIONS_DB"
}

is_session_alive() {
  tmux has-session -t "$1" 2>/dev/null
}

# Reconcile DB with live tmux state, then print all sessions as JSON
get_all_sessions() {
  init_sessions_db

  jq -c '.[]' "$SESSIONS_DB" | while read -r entry; do
    local sn
    sn=$(echo "$entry" | jq -r '.session')
    if ! is_session_alive "$sn"; then
      local cur
      cur=$(echo "$entry" | jq -r '.status')
      [ "$cur" = "running" ] && update_session_status "$sn" "finished"
    fi
  done

  cat "$SESSIONS_DB"
}

# Print a TSV table of sessions for gum table
format_sessions_table() {
  get_all_sessions | jq -r '
    ["REPO", "MODE", "STATUS", "BRANCH", "PR"],
    (.[] | [
      (.repo | split("/") | .[-1]),
      .mode,
      .status,
      (.branch // "—"),
      (.pr // "—")
    ]) | @tsv'
}

# Create a tmux session rooted at repo_path
create_amp_session() {
  local session_name="$1" repo_path="$2"
  tmux new-session -d -s "$session_name" -c "$repo_path"
  tmux set-option -t "$session_name" mouse on
}

launch_amp_interactive() {
  local session_name="$1"
  tmux send-keys -t "$session_name" "amp --dangerously-allow-all" C-m
}

launch_amp_fire_forget() {
  local session_name="$1" prompt_file="$2"
  tmux send-keys -t "$session_name" \
    "amp --dangerously-allow-all -x < '$prompt_file'" C-m
}

launch_amp_ralph() {
  local session_name="$1" prompt_file="$2"
  tmux send-keys -t "$session_name" \
    "amp --dangerously-allow-all < '$prompt_file'" C-m
}
```

**Step 2: Verify syntax**

Run: `bash -n lib/session.sh`
Expected: No errors

**Step 3: Commit**

```bash
git add lib/session.sh
git commit -m "feat: add session management library"
```

---

## Task 4: PR Management Library

**Files:**
- Create: `lib/pr.sh`

**Step 1: Create PR functions**

```bash
#!/usr/bin/env bash
# PR creation and status checking

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

create_pr() {
  local repo_path="$1" title="$2" body="${3:-""}"
  gh pr create \
    --repo "$(git -C "$repo_path" remote get-url origin)" \
    --head "$(git -C "$repo_path" branch --show-current)" \
    --title "$title" \
    --body "$body" \
    2>/dev/null
}

check_pr() {
  local repo_path="$1"
  local branch="${2:-$(git -C "$repo_path" branch --show-current)}"
  gh pr view "$branch" \
    --repo "$(git -C "$repo_path" remote get-url origin)" \
    --json url,state,title \
    2>/dev/null
}

list_prs() {
  local repo="$1" limit="${2:-5}"
  gh pr list --repo "$repo" --limit "$limit" \
    --json number,title,state,url,headRefName \
    -q '.[] | "#\(.number) [\(.state)] \(.title) (\(.headRefName))"'
}
```

**Step 2: Commit**

```bash
git add lib/pr.sh
git commit -m "feat: add PR management library"
```

---

## Task 5: Amp Prompt Templates

**Files:**
- Create: `templates/fire-and-forget.md`
- Create: `templates/ralph-mode.md`

**Step 1: Create fire-and-forget template**

```markdown
# Fire & Forget Task

## Task
{{TASK_DESCRIPTION}}

## Repo
{{REPO_NAME}} ({{REPO_PATH}})

## Constraints
- Work on branch: {{BRANCH_NAME}}
- Complete the task fully — no TODOs, no placeholders
- Run any available tests/typechecks before finishing
- When done:
  1. Commit all changes with a descriptive message
  2. Push the branch: `git push -u origin {{BRANCH_NAME}}`
  3. Create a PR: `gh pr create --title "{{PR_TITLE}}" --body "Automated by Amp (fire & forget)"`
  4. Write the PR URL to: /tmp/{{SESSION_NAME}}.pr

## Skills Available
Your skills are loaded at ~/.config/agents/skills/
Use the team-orchestration skill if parallel work would help.
```

**Step 2: Create Ralph Mode template**

```markdown
# Ralph Mode Launch

Execute Ralph Mode for this repository.

## Setup
1. Check if `docs/autonomous/` exists with a prd.json
   - If YES: continue execution from where it left off
   - If NO: enter Planning Mode (ask questions to create PRD)

2. Use the `ralph-mode` skill for all instructions.

## Repo
{{REPO_NAME}} at {{REPO_PATH}}
Branch: {{BRANCH_NAME}}

## On Completion
1. Push all changes: `git push -u origin {{BRANCH_NAME}}`
2. Create a PR: `gh pr create --title "{{PR_TITLE}}" --body "Automated by Amp (Ralph Mode)"`
3. Write the PR URL to: /tmp/{{SESSION_NAME}}.pr
```

**Step 3: Commit**

```bash
git add templates/
git commit -m "feat: add Amp prompt templates"
```

---

## Task 6: The `launch` CLI — Main Script

**Files:**
- Create: `launch`

This is the core of the project — the interactive TUI you type on your phone.

**Step 1: Create the launcher**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/repo.sh"
source "$SCRIPT_DIR/lib/session.sh"
source "$SCRIPT_DIR/lib/pr.sh"

for cmd in gum gh amp tmux jq git; do
  require_cmd "$cmd"
done

# ── Subcommands ──────────────────────────────

cmd_new() {
  # 1. Pick a repo
  gum style --bold --foreground 212 "Pick a repository"

  local source
  source=$(gum choose "My repos" "Org repos" "Enter URL manually")

  local repo
  case "$source" in
    "My repos")
      repo=$(list_repos | gum filter --placeholder "Search repos...")
      ;;
    "Org repos")
      local org
      org=$(gum input --placeholder "GitHub org name")
      repo=$(list_org_repos "$org" | gum filter --placeholder "Search repos...")
      ;;
    "Enter URL manually")
      repo=$(gum input --placeholder "owner/repo")
      repo="${repo#https://github.com/}"
      repo="${repo%.git}"
      ;;
  esac

  [ -z "$repo" ] && die "No repo selected"

  # 2. Clone/pull
  gum spin --spinner dot --title "Preparing ${repo##*/}..." -- \
    bash -c "source '$SCRIPT_DIR/lib/repo.sh' && ensure_repo '$repo' >/dev/null"

  local repo_path
  repo_path=$(ensure_repo "$repo")

  # 3. Pick mode
  gum style --bold --foreground 212 "How should Amp run?"

  local mode_choice
  mode_choice=$(gum choose \
    "🔧 Interactive  (attach to Amp live)" \
    "🚀 Fire & forget (describe task, detach)" \
    "📋 Ralph Mode   (PRD-driven autonomous)")

  local mode
  case "$mode_choice" in
    *Interactive*) mode="interactive" ;;
    *Fire*)        mode="fire-forget" ;;
    *Ralph*)       mode="ralph" ;;
  esac

  # 4. Branch
  local branch
  if [ "$mode" = "interactive" ]; then
    branch=$(gum input --placeholder "Branch name (empty = current)" --value "")
    [ -z "$branch" ] && branch=$(git -C "$repo_path" branch --show-current)
  else
    local default_branch="amp/${mode}/${repo##*/}-$(date +%m%d)"
    branch=$(gum input --placeholder "Branch name" --value "$default_branch")
  fi

  git -C "$repo_path" checkout -b "$branch" 2>/dev/null || \
    git -C "$repo_path" checkout "$branch" 2>/dev/null || true

  # 5. Record + create tmux session
  local session_name
  session_name=$(record_session "$repo" "$mode" "$repo_path" "$branch")
  create_amp_session "$session_name" "$repo_path"

  # 6. Launch per mode
  case "$mode" in
    interactive)
      launch_amp_interactive "$session_name"
      gum style --foreground 10 "✓ Amp running in: $session_name"
      gum style --foreground 244 "  Attaching... (Ctrl-B d to detach)"
      sleep 1
      tmux attach -t "$session_name"
      ;;

    fire-forget)
      gum style --bold --foreground 212 "What should Amp do?"
      local task
      task=$(gum write --placeholder "Describe the task..." --width 80 --height 6)
      [ -z "$task" ] && die "No task provided"

      local pr_title
      pr_title=$(gum input --placeholder "PR title" --value "$(echo "$task" | head -1)" --width 80)

      local prompt_file="/tmp/${session_name}-prompt.md"
      sed \
        -e "s|{{TASK_DESCRIPTION}}|$task|g" \
        -e "s|{{REPO_NAME}}|$repo|g" \
        -e "s|{{REPO_PATH}}|$repo_path|g" \
        -e "s|{{BRANCH_NAME}}|$branch|g" \
        -e "s|{{PR_TITLE}}|$pr_title|g" \
        -e "s|{{SESSION_NAME}}|$session_name|g" \
        "$SCRIPT_DIR/templates/fire-and-forget.md" > "$prompt_file"

      launch_amp_fire_forget "$session_name" "$prompt_file"

      gum style --foreground 10 "✓ Amp running in background"
      gum style --foreground 244 "  Session:  $session_name"
      gum style --foreground 244 "  Status:   launch status"
      gum style --foreground 244 "  Attach:   launch attach"
      ;;

    ralph)
      local pr_title="Ralph Mode: ${repo##*/}"

      local prompt_file="/tmp/${session_name}-prompt.md"
      sed \
        -e "s|{{REPO_NAME}}|$repo|g" \
        -e "s|{{REPO_PATH}}|$repo_path|g" \
        -e "s|{{BRANCH_NAME}}|$branch|g" \
        -e "s|{{PR_TITLE}}|$pr_title|g" \
        -e "s|{{SESSION_NAME}}|$session_name|g" \
        "$SCRIPT_DIR/templates/ralph-mode.md" > "$prompt_file"

      launch_amp_ralph "$session_name" "$prompt_file"

      gum style --foreground 10 "✓ Ralph Mode launched"
      gum style --foreground 244 "  Session: $session_name"

      local attach
      attach=$(gum choose "Attach now" "Leave running in background")
      [[ "$attach" == "Attach now" ]] && tmux attach -t "$session_name"
      ;;
  esac
}

cmd_status() {
  gum style --bold --foreground 212 "Active Sessions"

  local table
  table=$(format_sessions_table)

  if [ "$(echo "$table" | wc -l)" -le 1 ]; then
    gum style --foreground 244 "No sessions found."
    return
  fi

  echo "$table" | gum table --border rounded

  # Check for PRs on finished sessions
  jq -r '.[] | select(.status == "finished" and .pr == null) | .session' "$SESSIONS_DB" 2>/dev/null | \
    while read -r session; do
      local rp
      rp=$(jq -r --arg s "$session" '.[] | select(.session == $s) | .path' "$SESSIONS_DB")
      local pr_url
      pr_url=$(check_pr "$rp" 2>/dev/null | jq -r '.url // empty')
      if [ -n "$pr_url" ]; then
        update_session_pr "$session" "$pr_url"
        update_session_status "$session" "pr-created"
        gum style --foreground 10 "✓ PR found for $session: $pr_url"
      fi
    done
}

cmd_attach() {
  local sessions
  sessions=$(tmux list-sessions -F '#S' 2>/dev/null | grep "^${TMUX_SESSION_PREFIX}-" || true)

  if [ -z "$sessions" ]; then
    gum style --foreground 244 "No active Amp sessions."
    return
  fi

  local session
  session=$(echo "$sessions" | gum filter --placeholder "Pick session...")
  [ -n "$session" ] && tmux attach -t "$session"
}

cmd_kill() {
  local sessions
  sessions=$(tmux list-sessions -F '#S' 2>/dev/null | grep "^${TMUX_SESSION_PREFIX}-" || true)

  if [ -z "$sessions" ]; then
    gum style --foreground 244 "No active sessions."
    return
  fi

  local selected
  selected=$(echo "$sessions" | gum choose --no-limit --header "Select sessions to kill")
  [ -z "$selected" ] && return

  echo "$selected" | while read -r s; do
    tmux kill-session -t "$s" 2>/dev/null
    update_session_status "$s" "killed"
    gum style --foreground 9 "✗ Killed $s"
  done
}

cmd_clean() {
  init_sessions_db
  local before after
  before=$(jq length "$SESSIONS_DB")
  jq '[.[] | select(.status == "running")]' "$SESSIONS_DB" > "${SESSIONS_DB}.tmp" \
    && mv "${SESSIONS_DB}.tmp" "$SESSIONS_DB"
  after=$(jq length "$SESSIONS_DB")
  gum style --foreground 10 "Cleaned $((before - after)) finished sessions"
}

show_help() {
  gum style --bold --foreground 212 --border rounded --padding "1 2" \
    "launch — Remote Amp Execution Manager" \
    "" \
    "Commands:" \
    "  (default)  Pick a repo and start Amp" \
    "  status     Show all sessions" \
    "  attach     Attach to a running session" \
    "  kill       Kill running sessions" \
    "  clean      Remove finished sessions from DB" \
    "  help       Show this help"
}

# ── Dispatch ─────────────────────────────────

case "${1:-}" in
  status)         cmd_status ;;
  attach)         cmd_attach ;;
  kill)           cmd_kill ;;
  clean)          cmd_clean ;;
  help|-h|--help) show_help ;;
  ""|new)         cmd_new ;;
  *)              die "Unknown command: $1. Run 'launch help'." ;;
esac
```

**Step 2: Make executable and verify syntax**

Run: `chmod +x launch && bash -n launch`
Expected: No errors

**Step 3: Commit**

```bash
git add launch
git commit -m "feat: add main launch CLI with TUI"
```

---

## Task 7: Bootstrap Script (Runs Inside Sprite)

**Files:**
- Create: `bootstrap.sh`

**Step 1: Create the bootstrap script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# Sprite Bootstrap — run ONCE inside a fresh Sprite, then checkpoint.
#
# Required env vars:
#   TS_AUTHKEY     — Tailscale reusable auth key
#   AMP_API_KEY    — Amp API key
#   GITHUB_TOKEN   — GitHub personal access token
# ──────────────────────────────────────────────

echo "=== Sprite Bootstrap ==="

# ── 1. System packages ──
echo ">> System packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq tmux jq curl git unzip > /dev/null

# ── 2. Tailscale ──
echo ">> Tailscale..."
if ! command -v tailscale &>/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
if [ -n "${TS_AUTHKEY:-}" ]; then
  tailscale up --authkey="$TS_AUTHKEY" --ssh --hostname=amp-sprite
  echo "   Tailscale connected. SSH enabled."
else
  echo "   WARN: No TS_AUTHKEY. Run 'tailscale up --ssh' manually."
fi

# ── 3. Amp CLI ──
echo ">> Amp CLI..."
if ! command -v amp &>/dev/null; then
  curl -fsSL https://ampcode.com/install.sh | sh
fi
if [ -n "${AMP_API_KEY:-}" ]; then
  mkdir -p ~/.config/amp
  echo "export AMP_API_KEY='$AMP_API_KEY'" >> ~/.bashrc
fi
mkdir -p ~/.config/amp
cat > ~/.config/amp/settings.json << 'EOF'
{
  "amp.permissions": [
    { "tool": "*", "action": "allow" }
  ]
}
EOF

# ── 4. GitHub CLI ──
echo ">> GitHub CLI..."
if ! command -v gh &>/dev/null; then
  GH_VER=$(curl -s https://api.github.com/repos/cli/cli/releases/latest | jq -r '.tag_name' | sed 's/^v//')
  curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VER}/gh_${GH_VER}_linux_amd64.tar.gz" \
    | tar xz -C /tmp
  mv "/tmp/gh_${GH_VER}_linux_amd64/bin/gh" /usr/local/bin/gh
  rm -rf "/tmp/gh_${GH_VER}_linux_amd64"
fi
if [ -n "${GITHUB_TOKEN:-}" ]; then
  echo "$GITHUB_TOKEN" | gh auth login --with-token
  echo "   gh authenticated."
fi

# ── 5. Gum ──
echo ">> Gum..."
if ! command -v gum &>/dev/null; then
  GUM_VER=$(curl -s https://api.github.com/repos/charmbracelet/gum/releases/latest | jq -r '.tag_name' | sed 's/^v//')
  curl -fsSL "https://github.com/charmbracelet/gum/releases/download/v${GUM_VER}/gum_${GUM_VER}_Linux_x86_64.tar.gz" \
    | tar xz -C /tmp
  mv /tmp/gum /usr/local/bin/gum
fi

# ── 6. Skills (uploaded as /tmp/skills.tar.gz by setup-local.sh) ──
echo ">> Skills..."
mkdir -p ~/.config/agents/skills
if [ -f "/tmp/skills.tar.gz" ]; then
  tar xzf /tmp/skills.tar.gz -C ~/.config/agents/skills/
  rm /tmp/skills.tar.gz
  echo "   Skills installed."
fi

# ── 7. Launch CLI (uploaded as /tmp/launch.tar.gz by setup-local.sh) ──
echo ">> Launch CLI..."
mkdir -p ~/bin ~/sprite-remote
if [ -f "/tmp/launch.tar.gz" ]; then
  tar xzf /tmp/launch.tar.gz -C ~/sprite-remote/
  chmod +x ~/sprite-remote/launch
  ln -sf ~/sprite-remote/launch ~/bin/launch
  rm /tmp/launch.tar.gz
fi

# ── 8. Directories + shell config ──
mkdir -p ~/repos ~/.local/state/sprite-remote

cat >> ~/.bashrc << 'BASHRC'

# Sprite Remote Amp
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
alias l='launch'
alias lst='launch status'
alias la='launch attach'

# Auto-start tmux on SSH login
if [ -z "$TMUX" ] && [ -n "$SSH_CONNECTION" ]; then
  tmux attach -t main 2>/dev/null || tmux new -s main
fi
BASHRC

echo ""
echo "=== Bootstrap complete ==="
echo "Checkpoint now:  sprite checkpoint create --comment base-image"
echo "Then connect:    ssh amp-sprite (via Echo + Tailscale)"
```

**Step 2: Make executable, verify syntax**

Run: `chmod +x bootstrap.sh && bash -n bootstrap.sh`
Expected: No errors

**Step 3: Commit**

```bash
git add bootstrap.sh
git commit -m "feat: add Sprite bootstrap script"
```

---

## Task 8: Local Setup Script (Run from Mac)

**Files:**
- Create: `setup-local.sh`

This orchestrates everything from your Mac: creates the Sprite, uploads files
using `sprite exec -file local:remote` (native file upload), runs bootstrap,
and checkpoints.

Key Sprite CLI capabilities discovered:
- **`sprite exec -file source:dest`** — uploads files before executing (repeatable flag)
- **`sprite exec -env KEY=value`** — passes env vars into the execution
- **`sprite checkpoint create --comment "..."`** — named checkpoints

**Step 1: Create the setup script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# Run from your Mac to provision a Sprite.
#
# Prerequisites:
#   - sprite CLI installed + authenticated (org: ajay-bhargava)
#   - Env vars: TS_AUTHKEY, AMP_API_KEY, GITHUB_TOKEN
#
# Usage:
#   export TS_AUTHKEY="tskey-auth-..."
#   export AMP_API_KEY="..."
#   export GITHUB_TOKEN="ghp_..."
#   ./setup-local.sh [sprite-name]
# ──────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPRITE_NAME="${1:-amp-sprite}"
SKILLS_DIR="$HOME/.config/agents/skills"

echo "=== Setting up Sprite: $SPRITE_NAME ==="

for var in TS_AUTHKEY AMP_API_KEY GITHUB_TOKEN; do
  [ -z "${!var:-}" ] && { echo "ERROR: $var not set"; exit 1; }
done

# 1. Create sprite (or wake existing)
echo ">> Creating sprite..."
sprite create "$SPRITE_NAME" 2>/dev/null || echo "   (already exists)"
sprite use "$SPRITE_NAME"

# 2. Build a tarball of skills (easier than many -file flags)
echo ">> Packaging skills..."
SKILLS_TAR=$(mktemp /tmp/skills-XXXX.tar.gz)
tar czf "$SKILLS_TAR" -C "$SKILLS_DIR" \
  --exclude='.git' --exclude='.gitignore' .

# 3. Build a tarball of the launch CLI
echo ">> Packaging launch CLI..."
LAUNCH_TAR=$(mktemp /tmp/launch-XXXX.tar.gz)
tar czf "$LAUNCH_TAR" -C "$SCRIPT_DIR" \
  launch lib/ templates/

# 4. Upload tarballs + bootstrap, then run bootstrap
echo ">> Uploading and running bootstrap..."
sprite exec \
  -file "$SKILLS_TAR:/tmp/skills.tar.gz" \
  -file "$LAUNCH_TAR:/tmp/launch.tar.gz" \
  -file "$SCRIPT_DIR/bootstrap.sh:/tmp/bootstrap.sh" \
  -env "TS_AUTHKEY=$TS_AUTHKEY" \
  -env "AMP_API_KEY=$AMP_API_KEY" \
  -env "GITHUB_TOKEN=$GITHUB_TOKEN" \
  bash /tmp/bootstrap.sh

# 5. Cleanup local temp files
rm -f "$SKILLS_TAR" "$LAUNCH_TAR"

# 6. Checkpoint
echo ">> Checkpointing as base-image..."
sprite checkpoint create --comment "base-image"

echo ""
echo "=== Done! ==="
echo "Connect: ssh amp-sprite (via Echo + Tailscale)"
```

**Step 2: Make executable, verify syntax**

Run: `chmod +x setup-local.sh && bash -n setup-local.sh`
Expected: No errors

**Step 3: Commit**

```bash
git add setup-local.sh
git commit -m "feat: add local setup script for Mac-to-Sprite provisioning"
```

---

## Task 9: README

**Files:**
- Create: `README.md`

**Step 1: Write the README**

```markdown
# phone-coding

Control your GitHub repos from your phone. Run Amp agents remotely on
[Sprites](https://sprites.dev) VMs, connected via
[Tailscale](https://tailscale.com) SSH, accessed through
[Echo](https://replay.software/echo) on iOS.

## How It Works

```
iPhone (Echo) → Tailscale SSH → Sprite VM → tmux → Amp CLI → GitHub PR
```

One persistent Sprite acts as your cloud dev machine. SSH in from your phone,
pick a repo, tell Amp what to do, and walk away. Come back to a PR.

## Quick Start

### 1. Prerequisites

- [Sprite CLI](https://sprites.dev) installed + authenticated
- [Tailscale](https://tailscale.com) account + auth key
- [Amp](https://ampcode.com) API key
- [GitHub](https://github.com) personal access token
- [Echo](https://replay.software/echo) on your iPhone

### 2. Provision Your Sprite

```bash
export TS_AUTHKEY="tskey-auth-..."
export AMP_API_KEY="..."
export GITHUB_TOKEN="ghp_..."

./setup-local.sh
```

### 3. Connect from Phone

1. Open Echo on iPhone
2. Add host: `amp-sprite` (Tailscale will resolve it)
3. Tap to connect — you're in a tmux session

### 4. Use It

```bash
launch                # Pick repo + mode → start Amp
launch status         # Check running sessions
launch attach         # Reattach to a session
launch kill           # Stop sessions
launch clean          # Clear finished session records
```

## Execution Modes

| Mode | Description |
|------|-------------|
| **Interactive** | Full Amp session — you type prompts, see results live |
| **Fire & Forget** | Describe a task, Amp runs autonomously, creates PR |
| **Ralph Mode** | PRD-driven multi-iteration autonomous development |

## Aliases (on the Sprite)

- `l` → `launch`
- `lst` → `launch status`
- `la` → `launch attach`

## Cost

~$0.44 per 4-hour coding session on Sprites. $0 when idle.
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README"
```

---

## Task 10: Tailscale Connectivity Test

This is a manual verification step, not code.

**Step 1: Verify Sprite network egress allows Tailscale**

Run inside the Sprite after bootstrap:
```bash
# Check Tailscale status
tailscale status

# Check that it's reachable from your phone
# On phone: open Tailscale app, look for "amp-sprite" in device list
```

**Step 2: If Tailscale fails (network egress blocked)**

Fallback options:
1. Update Sprite network policy to allow `*.tailscale.com` and DERP relay IPs
2. If still blocked: install `ttyd` on port 8080 and access via Sprite URL in Safari
3. Or use `sprite console` for browser-based terminal (no Tailscale needed)

**Step 3: Test Echo → Sprite SSH**

From Echo on iPhone:
```
Host: amp-sprite
Port: 22
Auth: Tailscale (automatic)
```

Verify: you get a tmux session, can type `launch`, see gum TUI.

---

## Execution Order

```
Task 1  (config.sh)          — no deps
Task 2  (repo.sh)            — depends on Task 1
Task 3  (session.sh)         — depends on Task 1
Task 4  (pr.sh)              — depends on Task 1
Task 5  (templates)          — no deps
─── Tasks 1-5 can be parallelized (except 2-4 depend on 1) ───
Task 6  (launch)             — depends on Tasks 1-5
Task 7  (bootstrap.sh)       — no deps (but references Tasks 5-6 outputs)
Task 8  (setup-local.sh)     — depends on Task 7
Task 9  (README)             — no deps
Task 10 (Tailscale test)     — depends on Task 8
```

## Risks & Open Questions

1. **Tailscale in Firecracker** — needs live testing. NAT traversal *should* work
   via outbound-only connections, but Sprite network policies may block UDP.
2. **~~`ls` alias conflict~~** — resolved: using `lst` for `launch status`.
3. **Multi-line task input on phone keyboard** — `gum write` with Shift+Enter
   in Echo needs testing. May need to fall back to `gum input` for single-line.
4. **Sprite idle during long Amp runs** — Amp keeps CPU active, so unlikely to
   idle mid-run. But gap between Ralph Mode handoffs could trigger idle. May
   need a background keepalive.
5. **Skills sync** — currently one-shot upload during setup. For ongoing sync,
   either re-run `setup-local.sh` or pull skills from their git repo inside
   the Sprite.
