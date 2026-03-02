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
| `VAULT_PASSWORD` | If E2E enabled | — | Vault end-to-end encryption password (see below) |
| `PUID` | No | `1000` | UID that will own synced files on the host (see below) |
| `PGID` | No | `1000` | GID that will own synced files on the host (see below) |
| `VAULT_PATH` | No | `/vault` | In-container mount path (advanced) |
| `DEVICE_NAME` | No | `obsidian-docker` | Label shown in Obsidian Sync history |
| `CONFLICT_STRATEGY` | No | `merge` | `merge` or `conflict` |
| `EXCLUDED_FOLDERS` | No | — | Comma-separated vault folders to skip |
| `FILE_TYPES` | No | — | Extra types to sync: `image,audio,video,pdf,unsupported` |
| `GHCR_REPO` | No | — | Override image repository when self-building |

---

## File Ownership (PUID / PGID)

By default the container process drops to UID/GID `1000:1000` before writing any files, so vault files on the host are owned by that user. Set `PUID` and `PGID` in `.env` to match whichever host user should own the files.

**Regular Docker** (daemon runs as root):

```bash
# Find your UID and GID
id
# uid=1000(you) gid=1000(you) ...
```

```env
PUID=1000
PGID=1000
```

**Rootless Docker** (daemon runs as your user):

In rootless mode, container UID 0 already maps to the host user running the daemon — so files written by "root" inside the container land as your user on the host. Set both to `0`:

```env
PUID=0
PGID=0
```

Setting any other UID in rootless mode will map to a sub-UID from `/etc/subuid` (typically a high number like `100999`), which is almost certainly not what you want.

---

## End-to-End Encryption (VAULT_PASSWORD)

Obsidian Sync supports optional end-to-end encryption with a separate vault password. If your vault has this enabled, `ob sync-setup` will fail to authenticate until the password is provided.

**To check:** In the Obsidian desktop app, go to **Settings → Sync** and look for an "Encryption password" field — if it's present and set, E2E is active.

Add the password to your `.env`:

```env
VAULT_PASSWORD=your-vault-encryption-password
```

> **Note:** `VAULT_PASSWORD` is the *vault encryption password* you chose in Obsidian, not your Obsidian account password. They are separate credentials.

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

## Troubleshooting

**Container exits immediately**
- Check that `OBSIDIAN_AUTH_TOKEN` and `VAULT_NAME` are set: `docker compose config`

**"Vault not found" error on setup**
- Confirm the vault name matches exactly (case-sensitive): run `ob sync-list-remote` as shown in Step 2.

**"Failed to validate password" on setup**
- Your vault has end-to-end encryption enabled. Set `VAULT_PASSWORD` in `.env` to the encryption password from **Obsidian → Settings → Sync**. This is distinct from your Obsidian account password.

**Vault files owned by wrong user / permission denied**
- Set `PUID` and `PGID` in `.env` to the UID/GID of the host user who should own the files (`id` will show your current values).
- For rootless Docker, set both to `0`.

**Sync stops after a while**
- The `restart: unless-stopped` policy in `docker-compose.yml` will restart the container automatically.

**Token expired / login required**
- Re-run the `get-token` step, update `OBSIDIAN_AUTH_TOKEN` in `.env`, and restart: `docker compose up -d`

---

## License

MIT
