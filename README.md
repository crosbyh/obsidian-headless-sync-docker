# obsidian-headless-sync-docker

A minimal Docker image for continuously syncing an [Obsidian](https://obsidian.md) vault via [obsidian-headless](https://github.com/obsidianmd/obsidian-headless) — the official headless client for Obsidian Sync released February 2026.

The container authenticates with a single environment variable token and runs `ob sync --continuous` to keep your vault in sync indefinitely.

**Requirements:** An active [Obsidian Sync](https://obsidian.md/sync) subscription.

---

## Quick Start

### Step 1 — Get your auth token (one-time)

Pull the image and run the interactive login helper. It will prompt for your Obsidian email, password, and MFA code (if enabled), then print your token to the terminal.

```bash
docker run --rm -it ghcr.io/crosbyh/obsidian-headless-sync-docker:latest get-token
```

Copy the printed `OBSIDIAN_AUTH_TOKEN` value — you'll need it in step 3.

> **Note:** The token persists until you explicitly log out or revoke it from your Obsidian account. You only need to run this once per machine (or per token rotation).

---

### Step 2 — Find your remote vault name (one-time)

List the vaults available on your Obsidian Sync account:

```bash
docker run --rm \
  -e OBSIDIAN_AUTH_TOKEN=your-token-here \
  ghcr.io/crosbyh/obsidian-headless-sync-docker:latest \
  ob sync-list-remote
```

Note the exact vault name — you'll use it in `VAULT_NAME`.

---

### Step 3 — Configure your environment

```bash
cp .env.example .env
```

Edit `.env` and fill in at minimum:

```env
OBSIDIAN_AUTH_TOKEN=<token from step 1>
VAULT_NAME=My Vault
VAULT_HOST_PATH=./vault
```

See [Environment Variables](#environment-variables) for all options.

---

### Step 4 — Start continuous sync

```bash
docker compose up -d
```

On first run the container performs a one-time `ob sync-setup` to link the local directory to your remote vault, then enters continuous sync mode. Subsequent restarts skip the setup and go straight to syncing.

Watch logs:

```bash
docker compose logs -f
```

---

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `OBSIDIAN_AUTH_TOKEN` | Yes | — | Auth token from `get-token` |
| `VAULT_NAME` | Yes (first run) | — | Exact name of the remote Obsidian Sync vault |
| `VAULT_HOST_PATH` | Yes | `./vault` | Host path where vault files will be written |
| `VAULT_PATH` | No | `/vault` | In-container mount path (advanced) |
| `DEVICE_NAME` | No | `obsidian-docker` | Label shown in Obsidian Sync history |
| `CONFLICT_STRATEGY` | No | `merge` | `merge` or `conflict` |
| `EXCLUDED_FOLDERS` | No | — | Comma-separated vault folders to skip |
| `FILE_TYPES` | No | — | Extra types to sync: `image,audio,video,pdf,unsupported` |
| `GHCR_REPO` | No | — | Override image repository when self-building |

---

## Using a Pre-Built Image vs. Building Locally

### Pre-built (recommended)

Images are published to the GitHub Container Registry on every push to `main` and on version tags.

```yaml
# docker-compose.yml already points to:
image: ghcr.io/crosbyh/obsidian-headless-sync-docker:latest
```

### Build locally

```bash
docker build -t obsidian-headless-sync-docker .
```

Then update `docker-compose.yml` to use `image: obsidian-headless-sync-docker`.

---

## Publishing to GitHub Container Registry

The workflow at `.github/workflows/docker-publish.yml` handles this automatically.

### What triggers a publish

| Event | Tags pushed |
|---|---|
| Push to `main` / `master` | `latest`, `sha-<short-sha>` |
| Push tag `v1.2.3` | `1.2.3`, `1.2` |
| Pull request | Image built but **not** pushed |

### Required setup (one-time, in your GitHub repo)

1. Go to **Settings → Actions → General** and confirm "Read and write permissions" is enabled for `GITHUB_TOKEN`.
2. After the first successful push, go to **Packages** on your GitHub profile, find the package, and set visibility to **Public** if desired.

No secrets need to be added manually — the workflow uses the automatically-provided `GITHUB_TOKEN`.

### Making the package public

By default GHCR packages inherit the repo's visibility. To make the image publicly pullable:

1. GitHub profile → **Packages** → select the package
2. **Package settings** → **Change visibility** → Public

---

## Updating the Image

```bash
docker compose pull
docker compose up -d
```

---

## Stopping

```bash
docker compose down
```

Your vault files remain on disk at `VAULT_HOST_PATH`.

---

## How It Works

```
┌─────────────────────────────────────────────────┐
│  node:22-alpine container                       │
│                                                 │
│  entrypoint.sh                                  │
│    1. Validates OBSIDIAN_AUTH_TOKEN             │
│    2. Runs ob sync-setup (first run only)       │
│    3. Applies optional sync config              │
│    4. exec ob sync --continuous                 │
│         ↕ (watches for local & remote changes) │
└──────────────────┬──────────────────────────────┘
                   │ bind mount
            ┌──────▼──────┐
            │  ./vault/   │  ← your Obsidian vault on the host
            └─────────────┘
```

The container uses `OBSIDIAN_AUTH_TOKEN` directly — no system keychain or interactive login is needed after the initial token retrieval.

---

## Troubleshooting

**Container exits immediately**
- Check that `OBSIDIAN_AUTH_TOKEN` and `VAULT_NAME` are set: `docker compose config`

**"Vault not found" error on setup**
- Confirm the vault name matches exactly (case-sensitive): run `ob sync-list-remote` as shown in Step 2.

**Sync stops after a while**
- The `restart: unless-stopped` policy in `docker-compose.yml` will restart the container automatically.

**Token expired / login required**
- Re-run the `get-token` step, update `OBSIDIAN_AUTH_TOKEN` in `.env`, and restart: `docker compose up -d`

---

## License

MIT
