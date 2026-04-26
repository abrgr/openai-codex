FROM gitpod/workspace-full:2026-02-12-23-06-03

ARG CODEX_VERSION

USER root
RUN find /etc/apt/sources.list.d \
      -maxdepth 1 \
      -type f \
      -name '*.list' \
      -exec grep -l 'ppa.launchpadcontent.net/ondrej/nginx' {} + \
      | xargs -r rm -f && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      jq less tree && \
    rm -rf /var/lib/apt/lists/*

# Install exact Codex CLI version
RUN npm install -g "@openai/codex@${CODEX_VERSION}" && npm cache clean --force

# Make home dir world-traversable so any --user UID can reach nvm/node
RUN chmod 755 /home/gitpod

USER gitpod

CMD ["bash"]
