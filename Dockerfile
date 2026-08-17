FROM node:lts-alpine

# su-exec: minimal privilege-dropping tool (replaces gosu on Alpine)
RUN apk add --no-cache su-exec

# Install obsidian-headless CLI (requires Node 22+)
# Pinned via build arg so version-triggered CI builds bust the layer cache
# and the image actually contains the version its tag claims.
ARG OBSIDIAN_HEADLESS_VERSION=latest
RUN npm install -g "obsidian-headless@${OBSIDIAN_HEADLESS_VERSION}" \
 && node -e "console.log(require('/usr/local/lib/node_modules/obsidian-headless/package.json').version)" \
      > /etc/obsidian-headless-version

# Copy helper scripts
COPY entrypoint.sh  /usr/local/bin/docker-entrypoint
COPY get-token.sh   /usr/local/bin/get-token
COPY healthcheck.sh /usr/local/bin/healthcheck
RUN chmod +x /usr/local/bin/docker-entrypoint /usr/local/bin/get-token /usr/local/bin/healthcheck

# CLI state (auth/device/sync db) lives under XDG_CONFIG_HOME. Set it via ENV
# rather than the entrypoint: su-exec overwrites HOME with the target UID's
# passwd home on every privilege drop, but leaves XDG_CONFIG_HOME alone, and
# the healthcheck inherits it too. /data is a volume so the registered sync
# device identity survives container recreates.
ENV XDG_CONFIG_HOME=/data/config

# /vault: bind-mount your local vault here. /data: persistent sync state.
VOLUME ["/vault", "/data"]

HEALTHCHECK --interval=60s --timeout=15s --start-period=120s --retries=3 \
  CMD ["healthcheck"]

ENTRYPOINT ["docker-entrypoint"]
