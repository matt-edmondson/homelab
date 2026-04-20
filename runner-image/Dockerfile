# Homelab runner image — official actions-runner + gh CLI + .NET 10 SDK overlay.
# Base pinned; bump RUNNER_BASE_VERSION in .github/workflows/build-runner-image.yml.
FROM ghcr.io/actions/actions-runner:2.333.1

USER root

# gh CLI
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

# .NET 10 SDK — installed to /usr/share/dotnet so jobs using actions/setup-dotnet
# can skip the install step (the default install path is not writable by the
# unprivileged runner user, which is why setup-dotnet fails on this runner).
# Using dotnet-install.sh keeps us independent of distro-specific package feeds.
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
 && chmod +x /tmp/dotnet-install.sh \
 && /tmp/dotnet-install.sh --channel 10.0 --install-dir /usr/share/dotnet \
 && ln -s /usr/share/dotnet/dotnet /usr/local/bin/dotnet \
 && rm /tmp/dotnet-install.sh

ENV DOTNET_ROOT=/usr/share/dotnet \
    DOTNET_NOLOGO=1 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1

# Disable Claude Code's bwrap sandbox — it requires CAP_SYS_ADMIN which an
# unprivileged ARC pod lacks. The pod itself is the isolation boundary.
RUN install -dm 0755 /home/runner/.claude \
 && printf '{"sandbox":{"enabled":false}}\n' > /home/runner/.claude/settings.json \
 && chown -R runner:runner /home/runner/.claude

USER runner
