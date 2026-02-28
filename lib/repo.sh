#!/usr/bin/env bash
# Repo listing, cloning, and management

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# List repos from GitHub via gh CLI
list_repos() {
  local limit="${1:-$DEFAULT_GH_LIMIT}"
  gh repo list --json nameWithOwner,updatedAt \
    --limit "$limit" \
    -q '[.[] | .nameWithOwner] | .[]'
}

# List orgs the user belongs to (active memberships only)
# Uses GH_CLASSIC_TOKEN for read:org scope (fine-grained PATs can't list orgs)
list_orgs() {
  if [ -n "$GH_CLASSIC_TOKEN" ]; then
    GH_TOKEN="$GH_CLASSIC_TOKEN" gh api user/memberships/orgs \
      --jq '[.[] | select(.state == "active")] | .[].organization.login' 2>/dev/null | sort
  else
    gh api user/memberships/orgs \
      --jq '[.[] | select(.state == "active")] | .[].organization.login' 2>/dev/null | sort
  fi
}

# List repos from a specific org
list_org_repos() {
  local org="$1"
  local limit="${2:-$DEFAULT_GH_LIMIT}"
  gh repo list "$org" --json nameWithOwner,updatedAt \
    --limit "$limit" \
    -q '[.[] | .nameWithOwner] | .[]'
}

# Ensure repo is cloned and up to date. Prints local path.
ensure_repo() {
  local repo="$1"
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
