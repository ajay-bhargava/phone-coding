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
- [GitHub](https://github.com) classic PAT with `repo` + `read:org` scopes
- [Echo](https://replay.software/echo) on your iPhone

### 2. Create Tokens & Keys

You need three secrets in a `.env` file (gitignored). Here's how to get each:

#### Tailscale Auth Key (`TS_AUTHKEY`)

1. Go to [Tailscale Admin → Settings → Keys](https://login.tailscale.com/admin/settings/keys)
2. Click **Generate auth key**
3. Enable **Reusable** and **Ephemeral** (optional)
4. Copy the key (`tskey-auth-...`)

> **Tailscale SSH ACL**: For phone SSH access via Tailscale, add this to your
> [Access Controls](https://login.tailscale.com/admin/acls/file):
> ```json
> "ssh": [
>   {
>     "action": "accept",
>     "src": ["autogroup:members"],
>     "dst": ["autogroup:self"],
>     "users": ["ubuntu"]
>   }
> ]
> ```

#### Amp API Key (`AMP_API_KEY`)

1. Go to [ampcode.com](https://ampcode.com) → Settings → API Keys
2. Create a new key and copy it

#### GitHub Token (`GITHUB_TOKEN`)

1. Go to [GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)](https://github.com/settings/tokens)
2. Click **Generate new token (classic)**
3. Select scopes: **`repo`** and **`read:org`**
4. Copy the token (`ghp_...`)

This single classic PAT covers all orgs your account has access to (clone,
push, PR creation, org membership listing).

### 3. Configure & Deploy

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

### 4. Connect from Phone

1. Open Echo on iPhone
2. Add host: `amp-phone` (Tailscale MagicDNS resolves it)
3. `mosh ubuntu@amp-phone` — you land in a tmux session

### 5. Use It

```bash
launch                # Pick repo + mode → start Amp
launch status         # Check running sessions
launch attach         # Reattach to a session
launch kill           # Stop sessions
launch clean          # Clear finished session records
```

## Architecture

```
.
├── deploy.sh              # Provision, connect, upload to EC2
├── launch                 # TUI for picking repos and launching Amp
├── lib/
│   ├── config.sh          # Paths, defaults, shared helpers
│   ├── repo.sh            # GitHub repo listing, cloning, org access
│   ├── session.sh         # tmux session management + state tracking
│   └── pr.sh              # PR detection for finished sessions
├── templates/
│   ├── fire-and-forget.md # Prompt template for autonomous tasks
│   └── ralph-mode.md      # Prompt template for PRD-driven mode
└── terraform/
    ├── main.tf            # EC2 instance, security group, key pair
    ├── variables.tf       # Input variables (instance type, tokens, etc.)
    ├── outputs.tf         # Public IP output
    └── user-data.sh.tftpl # Bootstrap script (Tailscale, Amp, gh, ttyd)
```

### What Gets Installed on EC2

The `user-data.sh.tftpl` bootstrap installs: Tailscale, Amp CLI, GitHub CLI
(`gh`), Gum (TUI), ttyd (web terminal on port 8080), tmux, mosh.

The `.bashrc` exports `GITHUB_TOKEN`, `AMP_API_KEY`, and aliases
`GH_CLASSIC_TOKEN` to `GITHUB_TOKEN` (used by `lib/repo.sh` for org listing).

## deploy.sh Commands

| Command | Description |
|---------|-------------|
| `./deploy.sh plan` | Preview infrastructure changes |
| `./deploy.sh apply` | Provision EC2 instance |
| `./deploy.sh destroy` | Tear down everything |
| `./deploy.sh ssh` | SSH into the instance |
| `./deploy.sh mosh` | Mosh into the instance |
| `./deploy.sh upload` | Push skills + launch CLI to instance |
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
