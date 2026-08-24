# runner-base

Slim GitHub Actions self-hosted runner base image with current toolchain
defaults, published publicly to `docker.io/jrepp/runner-base`.

This is the trusted "candidate runner" for the runner-router fleet: t1, Artemis,
and any external repository derive their execution image from this base instead
of maintaining their own runner distributions. See
[rfc-003](https://github.com/jrepp/t1-hosting/blob/main/docs-cms/rfcs/rfc-003-runner-base-image.md).

## Image contents

- Ubuntu 26.04 slim base (multi-stage build; no source compilation).
- GitHub Actions runner binary, checksum-verified against the official release.
- Go `1.27.0`, Node `26.7.0` (with `npx`), prebuilt CPython `3.14.6` via `uv`
  (no source compile), `rustup`/cargo, `pipx`, and the distro's current
  `clang`.
- `rust-toolchain.toml` support: a repository that declares a Rust version gets
  it auto-installed by rustup on first use.

Versions are pinned in `versions.env`, tracked by Dependabot, and automerged by
Mergify when CI passes. Every merged change republishes the `:edge` tag to
docker.io; release tags publish `<version>` and `:latest`.

## Router compatibility

The image implements the entrypoint contract the runner-router writes for each
ephemeral allocation. The router passes an environment file with `REPO_URL`,
`RUNNER_TOKEN`, `RUNNER_NAME`, `LABELS`, `RUNNER_WORKDIR=/workspace`,
`EPHEMERAL`, `DISABLE_AUTO_UPDATE`, and `UNSET_CONFIG_VARS`, and mounts
`/runner-data` and `/workspace`. No router change is required; swap the pinned
image digest in host policy to adopt it.

## Deriving an image

Two supported mechanisms, both producing an immutable digest to pin in host
policy.

### Declarative (default)

Commit `.github/runner-image.yml`:

```yaml
base: docker.io/jrepp/runner-base:edge
toolchains:
  rust: 1.88.0
apt:
  packages:
    - imagemagick
```

and a workflow that calls this repository's reusable build:

```yaml
name: Build runner image

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  packages: write

jobs:
  derive:
    uses: jrepp/runner-base/.github/workflows/derive.yml@v1
    with:
      image: ghcr.io/slipgatecentral-ops/codex-biohazard-battle:edge
      login: true
    secrets:
      REGISTRY_USERNAME: ${{ github.actor }}
      REGISTRY_PASSWORD: ${{ secrets.GITHUB_TOKEN }}
```

### Dockerfile escape hatch

Repositories that need system packages or exotic toolchains beyond the
declarative surface write their own `Dockerfile`:

```dockerfile
FROM docker.io/jrepp/runner-base:1.0.0

RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*
```

and call `derive.yml` with `dockerfile: true`.

Then pin the emitted digest in the runner-router approved image list:

```json
{
  "name": "router-small",
  "image": "ghcr.io/slipgatecentral-ops/codex-biohazard-battle@sha256:<digest>"
}
```

## Release flow

- Every merged `main` change publishes `docker.io/jrepp/runner-base:edge`.
- A `v*` tag publishes `docker.io/jrepp/runner-base:<version>` and
  `:latest`, plus a `runner-image.txt` release asset recording the immutable
  digest for fleet pinning.
- CI runs a toolchain smoke test against the built image before publishing the
  digest.

## Local development

```sh
docker build -t runner-base:local . --build-arg RUNNER_VERSION=2.336.0 \
  --build-arg GO_VERSION=1.27.0 --build-arg NODE_VERSION=26.7.0 \
  --build-arg PYTHON_VERSION=3.14.6 --build-arg UV_VERSION=0.12.5
docker run --rm --entrypoint /usr/local/bin/runner-smoke runner-base:local
```
