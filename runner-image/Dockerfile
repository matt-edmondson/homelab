# Homelab runner image — official actions-runner + gh CLI overlay.
# Base pinned; bump RUNNER_BASE_VERSION in .github/workflows/build-runner-image.yml.
FROM ghcr.io/actions/actions-runner:2.333.1

USER root

RUN install -dm 0755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Disable Claude Code's bwrap sandbox — it requires CAP_SYS_ADMIN which an
# unprivileged ARC pod lacks. The pod itself is the isolation boundary.
RUN install -dm 0755 /home/runner/.claude \
 && printf '{"sandbox":{"enabled":false}}\n' > /home/runner/.claude/settings.json \
 && chown -R runner:runner /home/runner/.claude

USER runner
