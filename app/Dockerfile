# syntax=docker/dockerfile:1
# =============================================================================
# call_router - multi-stage Dockerfile
#
# Stage 1 ("builder") has the full Elixir toolchain and compiles a release.
# Stage 2 ("runtime") is a slim Debian image that only receives the compiled
# release. Compilers, source code and Hex caches never reach production.
# =============================================================================

# Pin exact versions so every build is reproducible. The builder and runtime
# MUST use the same Debian release, because the release contains native
# Erlang binaries linked against that OS's libraries (glibc, OpenSSL...).
ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27.3.4.16
ARG DEBIAN_VERSION=trixie-20260824-slim
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# ----------------------------------------------------------------------------
# Stage 1: build
# ----------------------------------------------------------------------------
# `AS builder` names this stage so the next stage can copy files out of it.
FROM ${BUILDER_IMAGE} AS builder

# Build tools needed by some Hex packages with native (C) code.
# --no-install-recommends keeps it lean; deleting apt lists shrinks the layer.
# The base image is date-pinned, so apt package versions are effectively pinned.
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential git \
 && rm -rf /var/lib/apt/lists/*

# All following commands run inside /app in the image.
WORKDIR /app

# Install Hex (package manager) and Rebar (Erlang build tool) non-interactively.
RUN mix local.hex --force && mix local.rebar --force

# Compile for production (no test/dev deps, optimised config).
ENV MIX_ENV=prod

# Copy ONLY the dependency manifests first. Docker caches each step ("layer");
# as long as mix.exs/mix.lock don't change, the slow deps download below is
# reused from cache even when you edit application code.
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

# Compile-time config must be present before deps compile.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Now copy the application source and compile it.
COPY lib lib
RUN mix compile

# runtime.exs is read at container start (PORT, LOG_LEVEL), so it is copied
# last - changing it doesn't invalidate the compile cache above.
COPY config/runtime.exs config/

# Assemble the self-contained release into /app/_build/prod/rel/call_router.
RUN mix release

# ----------------------------------------------------------------------------
# Stage 2: runtime
# ----------------------------------------------------------------------------
# A fresh, minimal image. Nothing from stage 1 exists here unless copied.
FROM ${RUNNER_IMAGE} AS runtime

# Runtime-only OS libraries:
#  - libstdc++6, openssl, libncurses6: needed by the Erlang VM (ERTS)
#  - ca-certificates: trust store for outbound HTTPS
#  - curl: used by HEALTHCHECK below
#  - locales: proper UTF-8 support
# `apt-get upgrade` first pulls in Debian security fixes released after the
# base image was built, so the CI vulnerability scan (HIGH/CRITICAL) stays
# green between base-image updates.
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && apt-get install -y --no-install-recommends \
      libstdc++6 openssl libncurses6 locales ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

# Elixir strings are UTF-8; tell the OS so too.
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Create an unprivileged system user/group with a fixed UID/GID (10001).
# A fixed numeric UID lets Kubernetes enforce `runAsNonRoot` / `runAsUser`.
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --home /app --no-create-home app

WORKDIR /app

# Production defaults; override at `docker run -e PORT=...` time.
ENV MIX_ENV=prod \
    PORT=4000

# Copy ONLY the built release from the builder stage, owned by our user.
COPY --from=builder --chown=app:app /app/_build/prod/rel/call_router ./

# Drop root (numeric UID so Kubernetes can verify it's non-root). Everything below (and the running app) uses UID 10001, so a
# compromised process can't modify the image or easily escape the container.
USER 10001:10001

# Documentation for humans/tools: the app listens on 4000. (It doesn't
# publish the port - `docker run -p` or a Kubernetes Service does that.)
EXPOSE 4000

# Docker marks the container "unhealthy" if /healthz fails 3 times in a row.
# (Kubernetes ignores HEALTHCHECK and uses its own probes - see Helm later.)
# Shell form is intentional here so ${PORT} gets expanded.
# hadolint ignore=DL3025
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${PORT}/healthz" || exit 1

# Signal handling: `docker stop` / Kubernetes send SIGTERM, then SIGKILL after
# a grace period. The exec-form ["..."] below (not a shell string) makes the
# release script PID 1's child chain `exec` straight into the Erlang VM, so the
# VM receives SIGTERM itself and runs a graceful shutdown (stops accepting
# connections, lets supervisors terminate children in order).
STOPSIGNAL SIGTERM
ENTRYPOINT ["/app/bin/call_router"]
CMD ["start"]
