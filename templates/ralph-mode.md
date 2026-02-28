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
