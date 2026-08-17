# obsidian-headless-sync-docker

A minimal Docker image for continuously syncing an [Obsidian](https://obsidian.md) vault via [obsidian-headless](https://github.com/obsidianmd/obsidian-headless) — the official headless client for Obsidian Sync released February 2026.

The container authenticates with a single environment variable token and runs `ob sync --continuous` to keep your vault in sync indefinitely.

**Requirements:** An active [Obsidian Sync](https://obsidian.md/sync) subscription.

---

## Quick Start

### Step 1 — Get your auth token (one-time)

Pull the image and run the interactive login helper. It will prompt for your Obsidian email, password, and MFA code (if enabled), then print your token to the terminal.

```bash
# Docker
docker run --rm -it ghcr.io/crosbyh/obsidian-headless-sync-docker:latest get-token

# Podman
podman run --rm -it ghcr.io/crosbyh/obsidian-headless-sync-docker:latest get-token
```

Copy the printed `OBSIDIAN_AUTH_TOKEN` value — you'll need it in step 3.

> **Note:** The token persists until you explicitly log out or revoke it from your Obsidian account. You only need to run this once per machine (or per token rotation).

---

### Step 2 — Find your remote vault name (one-time)

List the vaults available on your Obsidian Sync account:

```bash
# Docker
docker run --rm \
  -e OBSIDIAN_AUTH_TOKEN=your-token-here \
  ghcr.io/crosbyh/obsidian-headless-sync-docker:latest \
  ob sync-list-remote

# Podman
podman run --rm \
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
| `OBSIDIAN_AUTH_TOKEN_FILE` | No | — | Read the token from a file instead (Docker/Podman secrets) |
| `VAULT_NAME` | Yes (first run) | — | Exact name of the remote Obsidian Sync vault |
| `VAULT_HOST_PATH` | Yes | `./vault` | Host path where vault files will be written |
| `VAULT_PASSWORD` | If E2E enabled | — | Vault end-to-end encryption password (see below) |
| `VAULT_PASSWORD_FILE` | No | — | Read the vault password from a file instead |
| `VAULT_NAME_1`, `VAULT_NAME_2`, … | No | — | Multi-vault mode: sync several vaults, each to a subdirectory (see below) |
| `VAULT_PASSWORD_1`, … | No | — | Per-vault E2E password in multi-vault mode (`_FILE` variants also work) |
| `SYNC_ONESHOT` | No | — | `true` = sync once and exit instead of running continuously |
| `PUID` | No | `1000` | UID that will own synced files on the host (see below) |
| `PGID` | No | `1000` | GID that will own synced files on the host (see below) |
| `VAULT_PATH` | No | `/vault` | In-container mount path (advanced) |
| `DEVICE_NAME` | No | `obsidian-docker` | Label shown in Obsidian Sync history |
| `CONFLICT_STRATEGY` | No | `merge` | `merge` or `conflict` |
| `EXCLUDED_FOLDERS` | No | — | Comma-separated vault folders to skip |
| `FILE_TYPES` | No | — | Extra types to sync: `image,audio,video,pdf,unsupported` |
| `SYNC_MODE` | No | `bidirectional` | `bidirectional`, `pull-only` (download only, ignore local changes), or `mirror-remote` (download only, revert local changes) |
| `SYNC_CONFIGS` | No | — | Config categories to sync: `app,appearance,appearance-data,hotkey,core-plugin,core-plugin-data,community-plugin,community-plugin-data` |
| `CONFIG_DIR` | No | `.obsidian` | Vault config directory name |
| `GHCR_REPO` | No | — | Override image repository when self-building |

---

## Multi-Vault Mode

To sync more than one vault from a single container, use numbered variables instead of `VAULT_NAME`:

```env
VAULT_NAME_1=Personal
VAULT_NAME_2=Work
VAULT_PASSWORD_2=work-vault-e2e-password
```

Each vault syncs to a subdirectory of the vault volume named after the vault (e.g. `./vault/Personal`, `./vault/Work`). Shared settings (`DEVICE_NAME`, `CONFLICT_STRATEGY`, `SYNC_MODE`, etc.) apply to every vault. If any vault's sync process dies, the container exits so the restart policy can bring everything back up.

`VAULT_NAME` is ignored when numbered variables are present.

---

## One-Shot Mode

Set `SYNC_ONESHOT=true` to run a single sync per configured vault and exit (exit code `1` if any vault failed). Useful for cron jobs, systemd timers, or Kubernetes CronJobs:

```bash
docker compose run --rm -e SYNC_ONESHOT=true obsidian-sync
```

Pair with `restart: "no"` if you set it permanently in compose.

---

## Secrets (`*_FILE` variables)

Instead of putting credentials in environment variables (visible in `docker inspect`), point `OBSIDIAN_AUTH_TOKEN_FILE` / `VAULT_PASSWORD_FILE` (or `VAULT_PASSWORD_<n>_FILE` in multi-vault mode) at a file — e.g. a Docker/Podman secret mounted at `/run/secrets/...`. Setting both the plain and `_FILE` variant of the same variable is an error.

### Docker Compose example

Create the secret files (mode 600, and keep the directory out of version control):

```bash
mkdir -p secrets
install -m 600 /dev/null secrets/obsidian_token.txt
install -m 600 /dev/null secrets/vault_password.txt
# then paste the token / vault encryption password into each file
```

Declare them in `compose.yml` (uncomment the ready-made blocks):

```yaml
services:
  obsidian-sync:
    # ...
    secrets:
      - obsidian_token
      - vault_password

secrets:
  obsidian_token:
    file: ./secrets/obsidian_token.txt
  vault_password:
    file: ./secrets/vault_password.txt
```

Then in `.env`, point the `_FILE` variables at the mounted secrets and leave the plain variables empty:

```env
OBSIDIAN_AUTH_TOKEN=
OBSIDIAN_AUTH_TOKEN_FILE=/run/secrets/obsidian_token
VAULT_PASSWORD=
VAULT_PASSWORD_FILE=/run/secrets/vault_password
```

> **Note:** the secret file should contain only the credential itself. A single trailing newline is fine (editors usually add one), but avoid extra whitespace or comments.

**Multi-vault:** add one secret per encrypted vault and reference them with numbered variables, e.g. `VAULT_PASSWORD_1_FILE=/run/secrets/vault_password_1`.

**Docker Swarm:** the same `_FILE` variables work with Swarm-managed secrets — create them with `docker secret create obsidian_token -` and reference them by `external: true` in the stack file; they mount at `/run/secrets/<name>` just like file-based secrets.

**Podman:** `podman secret create` + `podman run --secret obsidian_token,mode=0400` mounts the secret at `/run/secrets/obsidian_token`, so the same `_FILE` values apply.

---

## Healthcheck

The image ships a `HEALTHCHECK` that verifies the sync process is alive and `ob sync-status` succeeds for every configured vault (checked every 60s after a 120s start period). Inspect it with:

```bash
docker inspect --format '{{.State.Health.Status}}' obsidian-sync
```

The Podman quadlet wires the same check via `HealthCmd=`; add `Notify=healthy` to the unit if you want systemd to consider the service started only after the first passing check. One-shot mode disables the check.

---

## Security

- The container starts as root only to fix vault ownership, then drops to `PUID:PGID` (via `su-exec`) before running any `ob` command.
- CLI state (auth token cache, sync device identity, sync database) lives under `XDG_CONFIG_HOME=/data/config` on a dedicated `/data` volume; everything else writable is on a `/run` tmpfs. Nothing is written to the image filesystem, so `compose.yml` runs the container with a **read-only root filesystem**, `no-new-privileges`, and all capabilities dropped except the handful needed (`SETUID`, `SETGID`, `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `KILL`). The quadlet sets `ReadOnly=true` and `NoNewPrivileges=true` likewise.
- Because `/data` persists, the container re-uses the same registered sync device across restarts and recreates instead of registering a new device in your Obsidian Sync account each time. Remove the `sync-state` volume if you ever want a factory-fresh state (the container will register as a new device on next start).
- Prefer `*_FILE` secrets over plain env vars so the token doesn't appear in `docker inspect` output.

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

Or, better, provide it as a Docker secret via `VAULT_PASSWORD_FILE` so it never appears in `docker inspect` — see [Secrets](#secrets-_file-variables).

> **Note:** `VAULT_PASSWORD` is the *vault encryption password* you chose in Obsidian, not your Obsidian account password. They are separate credentials.

> **⚠️ Passwords containing `$`:** Docker Compose interpolates `.env` files, so a bare `$` in the value (e.g. `pa$sword`) is treated as the start of a variable reference and silently stripped, truncating your password. If your password contains a `$`, wrap it in single quotes so Compose treats it literally:
>
> ```env
> VAULT_PASSWORD='pa$sword'
> ```
>
> The same applies to `VAULT_PASSWORD_1`, `VAULT_PASSWORD_2`, … in multi-vault mode. Passwords provided via `*_FILE` secrets are read verbatim and don't need escaping.

---

## Using a Pre-Built Image vs. Building Locally

### Pre-built (recommended)

Images are published to the GitHub Container Registry on every push to `main`, and automatically whenever a new `obsidian-headless` version is released on npm (a daily workflow checks and rebuilds). Version-tagged images (`:0.0.12`, `:0.0`) pin the exact `obsidian-headless` version baked into the image.

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

## Podman Quadlet (systemd)

A ready-made quadlet unit file (`obsidian-sync.container`) is included for running the container as a systemd service under rootless Podman.

### Install

```bash
# Copy the quadlet into the user systemd search path
mkdir -p ~/.config/containers/systemd
cp obsidian-sync.container ~/.config/containers/systemd/

# Create a secrets file (mode 600 keeps your token private)
mkdir -p ~/.config/obsidian-sync
install -m 600 /dev/null ~/.config/obsidian-sync/obsidian-sync.env
```

Populate `~/.config/obsidian-sync/obsidian-sync.env` with at minimum:

```env
OBSIDIAN_AUTH_TOKEN=<token from get-token>
VAULT_NAME=My Vault
```

Optional keys (defaults are set in the unit file):

```env
VAULT_PASSWORD=
PUID=0
PGID=0
DEVICE_NAME=obsidian-podman
CONFLICT_STRATEGY=merge
EXCLUDED_FOLDERS=
FILE_TYPES=
SYNC_MODE=
SYNC_CONFIGS=
CONFIG_DIR=
SYNC_ONESHOT=
OBSIDIAN_AUTH_TOKEN_FILE=
VAULT_PASSWORD_FILE=
```

### Start

```bash
systemctl --user daemon-reload
systemctl --user start obsidian-sync
systemctl --user status obsidian-sync
```

Watch logs:

```bash
journalctl --user -u obsidian-sync -f
```

### Automatic image updates

Enable the built-in Podman auto-update timer to pull new images from ghcr on a schedule:

```bash
systemctl --user enable --now podman-auto-update.timer
```

The unit also sets `Pull=newer`, so it will fetch a newer image from ghcr.io each time the service restarts.

### File ownership

The unit defaults to `PUID=0` / `PGID=0`, which is correct for rootless Podman — container root maps to your host user. For system-wide (root) Podman, override these in the env file with the UID/GID of the vault owner.

### Vault location

By default the vault is stored at `~/obsidian-vault`. To use a different path, edit the `Volume=` line in the unit file before copying it:

```ini
Volume=/path/to/your/vault:/vault:z
```

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
- If the password contains a `$` character, make sure it's wrapped in single quotes in `.env` (e.g. `VAULT_PASSWORD='pa$sword'`), otherwise Compose's variable interpolation will silently truncate it. Run `docker compose config` and check the resolved `VAULT_PASSWORD` value matches what you expect.

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
