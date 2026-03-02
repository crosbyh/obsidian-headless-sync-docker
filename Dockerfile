FROM node:22-alpine

# Install obsidian-headless CLI (requires Node 22+)
RUN npm install -g obsidian-headless

# Copy helper scripts
COPY entrypoint.sh /usr/local/bin/docker-entrypoint
COPY get-token.sh  /usr/local/bin/get-token
RUN chmod +x /usr/local/bin/docker-entrypoint /usr/local/bin/get-token

# Vault data directory (bind-mount your local vault here)
VOLUME ["/vault"]

ENTRYPOINT ["docker-entrypoint"]
