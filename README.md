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
- [Tailscale](https://tailscale.com) account + reusable auth key
- [Amp](https://ampcode.com) API key
- [GitHub](https://github.com) personal access token
- [Echo](https://replay.software/echo) on your iPhone

### 2. Provision Your Sprite

```bash
export TS_AUTHKEY="tskey-auth-..."
export AMP_API_KEY="..."
export GITHUB_TOKEN="ghp_..."

./setup-local.sh          # defaults to sprite name "phone"
./setup-local.sh my-name  # or pick your own
```

### 3. Connect from Phone

1. Open Echo on iPhone
2. Add host: `amp-sprite` (Tailscale MagicDNS resolves it)
3. Tap to connect — you land in a tmux session

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

## Architecture

See [docs/plans/2026-02-27-sprite-remote-amp.md](docs/plans/2026-02-27-sprite-remote-amp.md) for the full plan.
