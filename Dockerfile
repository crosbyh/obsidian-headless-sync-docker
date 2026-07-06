FROM node:lts-alpine

# su-exec: minimal privilege-dropping tool (replaces gosu on Alpine)
RUN apk add --no-cache su-exec

# Install obsidian-headless CLI (requires Node 22+)
# Pinned via build arg so version-triggered CI builds bust the layer cache
# and the image actually contains the version its tag claims.
ARG OBSIDIAN_HEADLESS_VERSION=latest
RUN npm install -g "obsidian-headless@${OBSIDIAN_HEADLESS_VERSION}"

# Copy helper scripts
COPY entrypoint.sh /usr/local/bin/docker-entrypoint
COPY get-token.sh  /usr/local/bin/get-token
RUN chmod +x /usr/local/bin/docker-entrypoint /usr/local/bin/get-token

# Vault data directory (bind-mount your local vault here)
VOLUME ["/vault"]

ENTRYPOINT ["docker-entrypoint"]
