#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# Deploy phone-coding EC2 instance via Terraform.
#
# Usage:
#   ./deploy.sh [apply|destroy|plan|ssh|mosh|status]
#
# Prerequisites:
#   - aws login (profile: with-context)
#   - terraform installed
#   - .env with TS_AUTHKEY, AMP_API_KEY, GITHUB_TOKEN
# ──────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
ACTION="${1:-plan}"

# Load .env for secrets
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  source "$SCRIPT_DIR/.env"
  set +a
fi

# Pass secrets as TF vars
export TF_VAR_ts_authkey="${TS_AUTHKEY:-}"
export TF_VAR_amp_api_key="${AMP_API_KEY:-}"
export TF_VAR_github_token="${GITHUB_TOKEN:-}"

# Export AWS credentials from profile (supports `aws login` auth)
echo ">> Loading AWS credentials from profile..."
eval "$(aws configure export-credentials --profile with-context --format env 2>/dev/null)" || {
  echo "ERROR: Could not export AWS credentials. Run: aws login --profile with-context"
  exit 1
}

case "$ACTION" in
  init)
    terraform -chdir="$TF_DIR" init
    ;;
  plan)
    terraform -chdir="$TF_DIR" init -upgrade
    terraform -chdir="$TF_DIR" plan
    ;;
  apply)
    terraform -chdir="$TF_DIR" init -upgrade
    terraform -chdir="$TF_DIR" apply -auto-approve
    ;;
  destroy)
    terraform -chdir="$TF_DIR" destroy -auto-approve
    ;;
  ssh)
    IP=$(terraform -chdir="$TF_DIR" output -raw public_ip)
    ssh -i ~/.ssh/developer-key.pem ubuntu@"$IP"
    ;;
  mosh)
    IP=$(terraform -chdir="$TF_DIR" output -raw public_ip)
    mosh --ssh="ssh -i ~/.ssh/developer-key.pem" ubuntu@"$IP"
    ;;
  upload)
    # Upload launch CLI + skills to running instance
    IP=$(terraform -chdir="$TF_DIR" output -raw public_ip)
    SKILLS_DIR="$HOME/.config/agents/skills"
    SSH_OPTS="-i $HOME/.ssh/developer-key.pem"

    echo ">> Uploading skills..."
    tar czf /tmp/skills.tar.gz -C "$SKILLS_DIR" --exclude='.git' .
    scp $SSH_OPTS /tmp/skills.tar.gz "ubuntu@$IP:/tmp/"
    ssh $SSH_OPTS ubuntu@"$IP" 'mkdir -p ~/.config/agents/skills && tar xzf /tmp/skills.tar.gz -C ~/.config/agents/skills/ && rm /tmp/skills.tar.gz'

    echo ">> Uploading launch CLI..."
    tar czf /tmp/launch.tar.gz -C "$SCRIPT_DIR" launch lib/ templates/
    scp $SSH_OPTS /tmp/launch.tar.gz "ubuntu@$IP:/tmp/"
    ssh $SSH_OPTS ubuntu@"$IP" 'mkdir -p ~/sprite-remote && tar xzf /tmp/launch.tar.gz -C ~/sprite-remote/ && chmod +x ~/sprite-remote/launch && ln -sf ~/sprite-remote/launch ~/bin/launch && rm /tmp/launch.tar.gz'

    rm -f /tmp/skills.tar.gz /tmp/launch.tar.gz
    echo ">> Done!"
    ;;
  status)
    terraform -chdir="$TF_DIR" output
    ;;
  *)
    echo "Usage: $0 [init|plan|apply|destroy|ssh|mosh|upload|status]"
    exit 1
    ;;
esac
