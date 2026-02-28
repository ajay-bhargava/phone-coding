#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# Sprite Bootstrap — run ONCE inside a fresh Sprite, then checkpoint.
#
# Expects to be invoked by setup-local.sh which uploads:
#   /tmp/skills.tar.gz   — agent skills
#   /tmp/launch.tar.gz   — launch CLI + lib + templates
#
# Required env vars (passed via sprite exec -env):
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
# Start tailscaled daemon (no systemd in Sprites)
tailscaled --state=/var/lib/tailscale/tailscaled.state --tun=userspace-networking &>/dev/null &
sleep 3

if [ -n "${TS_AUTHKEY:-}" ]; then
  if timeout 15 tailscale up --authkey="$TS_AUTHKEY" --ssh --hostname=amp-sprite 2>&1; then
    echo "   Tailscale connected. SSH enabled."
  else
    echo "   WARN: Tailscale auth failed. Key may be invalid."
    echo "   Generate an auth key (not API key) at:"
    echo "   https://login.tailscale.com/admin/settings/keys"
    echo "   Key must start with tskey-auth-"
    echo "   Continuing bootstrap without Tailscale..."
  fi
else
  echo "   WARN: No TS_AUTHKEY. Run 'tailscale up --ssh' manually."
fi

# ── 3. Amp CLI ──
echo ">> Amp CLI..."
if ! command -v amp &>/dev/null; then
  curl -fsSL https://ampcode.com/install.sh | bash
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
  echo "$GITHUB_TOKEN" | gh auth login --with-token 2>&1 || true
  echo "   gh authenticated."
fi

# ── 5. Gum ──
echo ">> Gum..."
if ! command -v gum &>/dev/null; then
  GUM_VER=$(curl -s https://api.github.com/repos/charmbracelet/gum/releases/latest | jq -r '.tag_name' | sed 's/^v//')
  curl -fsSL "https://github.com/charmbracelet/gum/releases/download/v${GUM_VER}/gum_${GUM_VER}_Linux_x86_64.tar.gz" \
    | tar xz -C /tmp
  mv "/tmp/gum_${GUM_VER}_Linux_x86_64/gum" /usr/local/bin/gum
  rm -rf "/tmp/gum_${GUM_VER}_Linux_x86_64"
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
