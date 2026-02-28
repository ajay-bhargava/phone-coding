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

  # Reuse existing tmux session if it's still alive
  if tmux has-session -t "$session_name" 2>/dev/null; then
    echo "$session_name"
    return
  fi

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

# Attach or switch to a tmux session (works from inside tmux too)
attach_session() {
  local session_name="$1"
  if [ -n "${TMUX:-}" ]; then
    tmux switch-client -t "$session_name"
  else
    tmux attach -t "$session_name"
  fi
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
