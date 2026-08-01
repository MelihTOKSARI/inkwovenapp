# syntax = docker/dockerfile:1

# Adjust NODE_VERSION as desired. The digest is pinned alongside the tag so two
# deploys from the same git SHA produce byte-identical images — the `-slim` tag
# is mutable and its Debian base is re-pushed regularly. Bump both together
# (`docker buildx imagetools inspect node:<version>-slim` prints the digest).
ARG NODE_VERSION=20.19.5
FROM node:${NODE_VERSION}-slim@sha256:9e70124bd00f47dd023e349cd587132ae61892acc0e47ed641416c3e18f401c3 AS base

LABEL fly_launch_runtime="Node.js"

# Node.js app lives here
WORKDIR /app

# Set production environment
ENV NODE_ENV="production"


# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build node modules
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential node-gyp pkg-config python-is-python3

# Install node modules. NODE_ENV=production already implies --omit=dev; the flag
# is explicit so a future change to that ENV cannot silently pull devDeps
# (@flydotio/dockerfile is scaffolding and must never reach the runtime image).
COPY package-lock.json package.json ./
RUN npm ci --omit=dev

# Copy application code
COPY . .


# Final stage for app image
FROM base

# Copy built application. Deliberately NOT chowned to `node`: the proxy writes
# nothing to disk (state lives in Redis/Postgres), so leaving /app root-owned
# and world-readable means the unprivileged runtime user can read and execute
# but cannot rewrite src/ or node_modules — no persistent backdoor after an RCE.
COPY --from=build /app /app

# Drop root. node:20-slim ships an unprivileged `node` user (uid 1000) that the
# fly launch template never selected.
USER node

# Must match src/index.js (PORT ?? 8787) and fly.toml's internal_port. EXPOSE is
# documentation-only, but `fly launch` reads it when regenerating fly.toml — a
# stale 3000 here is how internal_port silently regresses.
EXPOSE 8787

# Exec form, not `npm run start`: npm sits between the init process and node and
# does not reliably forward SIGTERM, so `fly deploy` would hard-kill in-flight
# SSE streams instead of letting the server drain them. Keep in sync with the
# `start` script in package.json.
CMD [ "node", "src/index.js" ]
