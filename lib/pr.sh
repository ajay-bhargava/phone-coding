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
