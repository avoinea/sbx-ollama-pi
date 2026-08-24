# syntax=docker/dockerfile:1

FROM docker/sandbox-templates:shell

USER root

# Install dependencies for Ollama and nvm
RUN apt-get update \
    && apt-get install -y curl ca-certificates gnupg zstd \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Ollama for local model serving (supports local models and cloud models like glm-5.2:cloud)
RUN curl -fsSL https://ollama.com/install.sh | sh

USER agent

# Clear base image npm prefix config so nvm manages per-version globals
ARG NODE_DEFAULT=22
ENV NVM_DIR=/home/agent/.nvm
ENV NPM_CONFIG_PREFIX=

# Install nvm with Node.js 22 and 24 (default: 22, override with --build-arg NODE_DEFAULT=24)
RUN unset NPM_CONFIG_PREFIX \
    && rm -f "$HOME/.npmrc" 2>/dev/null || true \
    && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.7/install.sh | bash \
    && . "$NVM_DIR/nvm.sh" \
    && nvm install 22 \
    && nvm install 24 \
    && nvm alias default "${NODE_DEFAULT}" \
    && nvm use 22 \
    && npm install -g --ignore-scripts @earendil-works/pi-coding-agent@latest \
    && nvm use 24 \
    && npm install -g --ignore-scripts @earendil-works/pi-coding-agent@latest \
    && nvm use default

# Pre-create pi config so thinking works with ollama launch pi
# ollama launch pi does NOT set defaultThinkingLevel, reasoning:true, or thinkingLevelMap,
# so we pre-seed them. ollama launch pi merges into these files (preserving our fields) on each run.
# Users can override models.json by placing one in the project root (workspace).
RUN mkdir -p /home/agent/.pi/agent
COPY --chown=agent:agent settings.json /home/agent/.pi/agent/settings.json
COPY --chown=agent:agent models.json   /home/agent/.pi/agent/models.json

# Auto-launch pi via Ollama in interactive shells
# - If a models.json exists in the project root, it overrides the pre-seeded one
# - Local Ollama: starts ollama serve, runs ollama signin if needed, then launches pi
# - Remote Ollama (OLLAMA_HOST set): skips local server/signin, updates baseUrl in models.json
# - defaultThinkingLevel (xhigh) and reasoning:true are pre-seeded so thinking works
# Override model with: sbx run -e PI_MODEL=minimax-m3:cloud ...
# Override thinking with: sbx run -e PI_THINKING=high ...
# Use remote Ollama: sbx run -e OLLAMA_HOST=http://host.docker.internal:11434 ...
# Use custom models: place models.json in project root
RUN printf '\n\
# Auto-launch pi coding agent (via Ollama) in interactive shells\n\
if [[ $- == *i* ]] && command -v pi &> /dev/null; then\n\
    if [[ -f "$HOME/workspace/models.json" ]]; then\n\
        cp "$HOME/workspace/models.json" "$HOME/.pi/agent/models.json"\n\
    fi\n\
    if [[ -z "$OLLAMA_HOST" ]]; then\n\
        ollama serve &>/dev/null & sleep 2\n\
        if [[ ! -f "$HOME/.ollama/id_ed25519" ]]; then\n\
            ollama signin\n\
        fi\n\
    else\n\
        sed -i "s|\"baseUrl\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"baseUrl\": \"${OLLAMA_HOST%%/}/v1\"|" "$HOME/.pi/agent/models.json" 2>/dev/null\n\
    fi\n\
    sed -i "s/\"defaultThinkingLevel\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"defaultThinkingLevel\": \"${PI_THINKING:-xhigh}\"/" "$HOME/.pi/agent/settings.json" 2>/dev/null\n\
    ollama launch pi --model="${PI_MODEL:-glm-5.2:cloud}" --yes\n\
fi\n' >> ~/.bashrc