FROM gitpod/workspace-full:latest

ARG CODEX_VERSION

USER root
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      jq less tree && \
    rm -rf /var/lib/apt/lists/*

# Install exact Codex CLI version
RUN npm install -g "@openai/codex@${CODEX_VERSION}" && npm cache clean --force

# Make home dir world-traversable so any --user UID can reach nvm/node
RUN chmod 755 /home/gitpod

USER gitpod

CMD ["bash"]
