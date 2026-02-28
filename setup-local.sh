#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# Run from your Mac to provision a Sprite.
#
# Prerequisites:
#   - sprite CLI installed + authenticated (org: ajay-bhargava)
#   - Env vars set in .env or exported: TS_AUTHKEY, AMP_API_KEY, GITHUB_TOKEN
#
# Usage:
#   ./setup-local.sh [sprite-name]   (defaults to "phone")
# ──────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPRITE_NAME="${1:-phone}"
SKILLS_DIR="$HOME/.config/agents/skills"

# Load .env if present
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  source "$SCRIPT_DIR/.env"
  set +a
fi

echo "=== Setting up Sprite: $SPRITE_NAME ==="

for var in TS_AUTHKEY AMP_API_KEY GITHUB_TOKEN; do
  if [ -z "${!var:-}" ]; then
    echo "ERROR: $var not set"
    exit 1
  fi
done

# 1. Create sprite (or wake existing)
echo ">> Creating/waking sprite..."
sprite create "$SPRITE_NAME" 2>/dev/null || echo "   (already exists)"
sprite use "$SPRITE_NAME"

# Helper: upload a file to the sprite via stdin pipe
upload() {
  local src="$1" dest="$2"
  sprite exec bash -c "cat > '$dest'" < "$src"
  echo "   Uploaded $(basename "$src") → $dest"
}

# 2. Build and upload skills tarball
echo ">> Uploading skills..."
TMPDIR=$(mktemp -d)
tar czf "$TMPDIR/skills.tar.gz" -C "$SKILLS_DIR" \
  --exclude='.git' --exclude='.gitignore' .
upload "$TMPDIR/skills.tar.gz" /tmp/skills.tar.gz

# 3. Build and upload launch CLI tarball
echo ">> Uploading launch CLI..."
tar czf "$TMPDIR/launch.tar.gz" -C "$SCRIPT_DIR" \
  launch lib/ templates/
upload "$TMPDIR/launch.tar.gz" /tmp/launch.tar.gz

# 4. Upload bootstrap script
echo ">> Uploading bootstrap..."
upload "$SCRIPT_DIR/bootstrap.sh" /tmp/bootstrap.sh

# 5. Upload env vars as a sourceable script
echo ">> Uploading env config..."
cat > "$TMPDIR/sprite-env.sh" << ENVEOF
export TS_AUTHKEY='$TS_AUTHKEY'
export AMP_API_KEY='$AMP_API_KEY'
export GITHUB_TOKEN='$GITHUB_TOKEN'
ENVEOF
upload "$TMPDIR/sprite-env.sh" /tmp/sprite-env.sh

# 6. Run bootstrap inside sprite
echo ">> Running bootstrap..."
sprite exec bash -c 'source /tmp/sprite-env.sh && bash /tmp/bootstrap.sh'

# 7. Cleanup
rm -rf "$TMPDIR"

# 8. Checkpoint
echo ">> Checkpointing..."
sprite checkpoint create --comment "base-image"

echo ""
echo "=== Done! ==="
echo "Connect: ssh amp-sprite (via Echo + Tailscale)"
