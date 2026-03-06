FROM gitpod/workspace-full:latest

USER root
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      jq less tree && \
    rm -rf /var/lib/apt/lists/*

# Install Codex CLI globally — always pulls latest published version
RUN npm install -g @openai/codex && npm cache clean --force

RUN groupadd -g 1001 user && \
    useradd -m -u 1001 -g 1001 -s /bin/bash user

# Default to interactive shell so the alias can pass commands/args
CMD ["bash"]
