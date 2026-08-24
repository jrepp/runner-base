# Runner base image: slim Ubuntu 26.04 with current toolchain defaults.
#
# Tool versions are pinned in versions.env (dependabot-tracked). CI sources
# that file and passes the values as build arguments; the ARG defaults here
# must match versions.env.
#
# amd64-only for now. The runner-router's container hosts are amd64 today;
# add linux/arm64 (and the aarch64 asset names below) when an arm64 container
# host exists.

FROM ubuntu:26.04 AS build

ARG GO_VERSION=1.27.0
ARG NODE_VERSION=26.7.0
ARG PYTHON_VERSION=3.14.6
ARG UV_VERSION=0.12.5
ARG RUNNER_VERSION=2.336.0

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl xz-utils tar \
    && rm -rf /var/lib/apt/lists/*

# --- Go (official tarball) --------------------------------------------------
RUN set -eux; \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tgz; \
    rm -rf /usr/local/go; \
    tar -C /usr/local -xzf /tmp/go.tgz; \
    rm /tmp/go.tgz

# --- Node 26 (official tarball) ---------------------------------------------
RUN set -eux; \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" -o /tmp/node.tar.xz; \
    rm -rf /opt/node; \
    mkdir -p /opt/node; \
    tar -C /opt/node -xJf /tmp/node.tar.xz --strip-components=1; \
    rm /tmp/node.tar.xz

# --- uv + prebuilt CPython 3.14 (no source compile) --------------------------
ENV UV_INSTALL_DIR=/opt/uv \
    UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    UV_TOOL_BIN_DIR=/opt/uv/bin \
    UV_TOOL_DIR=/opt/uv/tools
RUN set -eux; \
    curl -fsSL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz" -o /tmp/uv.tgz; \
    mkdir -p "${UV_INSTALL_DIR}"; \
    tar -C "${UV_INSTALL_DIR}" -xzf /tmp/uv.tgz --strip-components=1; \
    rm /tmp/uv.tgz; \
    "${UV_INSTALL_DIR}/uv" python install "${PYTHON_VERSION}"; \
    "${UV_INSTALL_DIR}/uv" tool install pipx

# --- Rust (rustup -> stable toolchain) ---------------------------------------
ENV RUSTUP_HOME=/opt/rust \
    CARGO_HOME=/opt/cargo
RUN set -eux; \
    curl -fsSL https://sh.rustup.rs -o /tmp/rustup.sh; \
    sh /tmp/rustup.sh -y --profile default --default-toolchain stable --no-modify-path; \
    rm /tmp/rustup.sh; \
    chmod -R a+rX /opt/rust /opt/cargo

# --- GitHub Actions runner (checksummed official distribution) ---------------
RUN set -eux; \
    curl -fsSL "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" -o "/tmp/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"; \
    curl -fsSL "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz.sha256" -o "/tmp/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz.sha256"; \
    cd /tmp; \
    sha256sum -c "actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz.sha256"; \
    mkdir -p /actions-runner; \
    tar -C /actions-runner -xzf "/tmp/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"; \
    rm -f "/tmp/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" "/tmp/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz.sha256"

# ---------------------------------------------------------------------------
# Runtime stage: minimal base plus toolchains copied from the build stage.
# ---------------------------------------------------------------------------
FROM ubuntu:26.04

ARG PYTHON_VERSION=3.14.6

ENV DEBIAN_FRONTEND=noninteractive \
    RUSTUP_HOME=/opt/rust \
    CARGO_HOME=/opt/cargo \
    UV_INSTALL_DIR=/opt/uv \
    UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    UV_TOOL_BIN_DIR=/opt/uv/bin \
    UV_TOOL_DIR=/opt/uv/tools \
    AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache \
    GOPATH=/workspace/go \
    GOCACHE=/workspace/.cache/go-build \
    GOMODCACHE=/workspace/go/pkg/mod \
    PIP_CACHE_DIR=/workspace/.cache/pip

# clang from the distro is the current release for this Ubuntu; the runner
# binary also needs its ICU, krb5, and OpenSSL runtime libraries. Package names
# drift across Ubuntu releases (t64 transitions, libicu version bumps), so the
# renamed ones are resolved by trying the known candidates.
RUN set -eux; \
    apt-get update; \
    try_install() { for p in "$@"; do if apt-get install -y --no-install-recommends "${p}" >/dev/null 2>&1; then return 0; fi; done; return 1; }; \
    try_install libicu74 libicu76 libicu78 libicu80; \
    try_install libssl3 libssl3t64; \
    try_install libcurl4 libcurl4t64; \
    try_install libsqlite3-0 libsqlite3-0t64; \
    try_install libffi8 libffi8t64; \
    try_install libpcre2-8-0 libpcre2-8-0t64; \
    try_install libkrb5-3 libkrb5-3t64; \
    try_install liblttng-ust1 liblttng-ust1t64; \
    try_install libunwind8 libunwind8t64; \
    try_install libstdc++-16-dev libstdc++-15-dev libstdc++-14-dev; \
    apt-get install -y --no-install-recommends \
        ca-certificates git curl jq unzip xz-utils openssh-client \
        zlib1g libgcc-s1 libstdc++6 \
        clang make pkg-config; \
    rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local/go /usr/local/go
COPY --from=build /opt/node /opt/node
COPY --from=build /opt/rust /opt/rust
COPY --from=build /opt/cargo /opt/cargo
COPY --from=build /opt/uv /opt/uv
COPY --from=build /actions-runner /actions-runner

# Wire the toolchains onto /usr/local/bin and refresh the PATH order so the
# uv-managed Python wins over any distro interpreter.
RUN set -eux; \
    mkdir -p /opt/hostedtoolcache; \
    ln -sf /usr/local/go/bin/go /usr/local/bin/go; \
    ln -sf /opt/uv/uv /usr/local/bin/uv; \
    PYBIN="$(dirname "$(uv python find "${PYTHON_VERSION}")")"; \
    ln -sf "${PYBIN}/python3.14" /usr/local/bin/python3.14; \
    ln -sf "${PYBIN}/python3.14" /usr/local/bin/python3; \
    ln -sf "${PYBIN}/python3.14" /usr/local/bin/python; \
    if ! python3 -m pip --version >/dev/null 2>&1; then \
        python3 -m ensurepip --upgrade || /opt/uv/uv pip install --python /usr/local/bin/python3 pip; \
    fi; \
    ln -sf "${PYBIN}/pip3.14" /usr/local/bin/pip3.14; \
    ln -sf "${PYBIN}/pip3.14" /usr/local/bin/pip3; \
    ln -sf "${PYBIN}/pip3.14" /usr/local/bin/pip; \
    ln -sf /opt/uv/bin/pipx /usr/local/bin/pipx

ENV PATH=/usr/local/go/bin:/opt/node/bin:/opt/cargo/bin:/usr/local/bin:/actions-runner:/usr/bin:/bin

# Entrypoint implements the runner-router env contract (REPO_URL, RUNNER_TOKEN,
# RUNNER_NAME, LABELS, RUNNER_WORKDIR, EPHEMERAL, DISABLE_AUTO_UPDATE,
# UNSET_CONFIG_VARS). Healthcheck and smoke test are baked in for the router and
# CI respectively.
COPY scripts/runner-start /usr/local/bin/runner-start
COPY scripts/container-healthcheck.sh /usr/local/bin/runner-healthcheck
COPY scripts/runner-smoke /usr/local/bin/runner-smoke
RUN chmod +x /usr/local/bin/runner-start /usr/local/bin/runner-healthcheck /usr/local/bin/runner-smoke

HEALTHCHECK --interval=60s --timeout=10s --start-period=60s --retries=3 \
    CMD /usr/local/bin/runner-healthcheck

CMD ["/usr/local/bin/runner-start"]
