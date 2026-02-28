# phone-coding

Control your GitHub repos from your phone. Run Amp agents remotely on
an EC2 spot instance, connected via
[Tailscale](https://tailscale.com) + [Mosh](https://mosh.org), accessed through
[Echo](https://replay.software/echo) on iOS.

## How It Works

```
iPhone (Echo) → Mosh → Tailscale → EC2 Spot → tmux → Amp CLI → GitHub PR
```

One persistent EC2 instance acts as your cloud dev machine. Mosh in from your
phone, pick a repo, tell Amp what to do, and walk away. Come back to a PR.

## Quick Start

### 1. Prerequisites

- [Terraform](https://terraform.io) installed
- AWS CLI configured (`aws login --profile with-context`)
- [Tailscale](https://tailscale.com) account + reusable auth key
- [Amp](https://ampcode.com) API key
- [GitHub](https://github.com) personal access token
- [Echo](https://replay.software/echo) on your iPhone

### 2. Provision EC2

```bash
# Set secrets in .env
cat > .env << 'EOF'
TS_AUTHKEY=tskey-auth-...
AMP_API_KEY=...
GITHUB_TOKEN=ghp_...
EOF

# Deploy
./deploy.sh apply

# Upload launch CLI + skills
./deploy.sh upload
```

### 3. Connect from Phone

1. Open Echo on iPhone
2. Add host: `amp-phone` (Tailscale MagicDNS resolves it)
3. `mosh ubuntu@amp-phone` — you land in a tmux session

### 4. Use It

```bash
launch                # Pick repo + mode → start Amp
launch status         # Check running sessions
launch attach         # Reattach to a session
launch kill           # Stop sessions
launch clean          # Clear finished session records
```

## deploy.sh Commands

| Command | Description |
|---------|-------------|
| `./deploy.sh plan` | Preview infrastructure changes |
| `./deploy.sh apply` | Provision EC2 spot instance |
| `./deploy.sh destroy` | Tear down everything |
| `./deploy.sh ssh` | SSH into the instance |
| `./deploy.sh mosh` | Mosh into the instance |
| `./deploy.sh upload` | Push skills + launch CLI |
| `./deploy.sh status` | Show instance outputs |

## Execution Modes

| Mode | Description |
|------|-------------|
| **Interactive** | Full Amp session — you type prompts, see results live |
| **Fire & Forget** | Describe a task, Amp runs autonomously, creates PR |
| **Ralph Mode** | PRD-driven multi-iteration autonomous development |

## Aliases (on the EC2 instance)

- `l` → `launch`
- `lst` → `launch status`
- `la` → `launch attach`

## Cost

~$0.01/hr for t3.medium spot. $0 when stopped.
