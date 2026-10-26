# syntax=docker/dockerfile:1

ARG GLEAM_VERSION=1.19.2
ARG OTP_VERSION=29

# ---- build: compile everything and export the Erlang shipment ----
FROM ghcr.io/gleam-lang/gleam:v${GLEAM_VERSION}-erlang AS build
WORKDIR /app
COPY shared/ shared/
COPY client/ client/
COPY server/ server/
# Bundle the Lustre client into the server's static directory (served at
# /static/client.js). lustre_dev_tools downloads its bundler (bun) on first use.
RUN cd client && gleam run -m lustre/dev build --no-html --minify --outdir=../server/priv/static
RUN cd server && gleam export erlang-shipment

# ---- test: gleam test in every package ----
# Node.js is needed only to run the client's JavaScript-target tests.
FROM build AS test
RUN apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*
RUN cd shared && gleam format --check src test && gleam test \
    && gleam test --target javascript \
    && cd ../server && gleam format --check src test && gleam test \
    && cd ../client && gleam format --check src test && gleam test
# Tests run during the build above; the base image's entrypoint is `gleam`.
ENTRYPOINT ["echo"]
CMD ["all tests passed"]

# ---- runtime: only the shipment, non-root ----
FROM erlang:${OTP_VERSION}-slim AS runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends wget \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --no-create-home --uid 10001 mission
WORKDIR /app
COPY --from=build --chown=mission:mission /app/server/build/erlang-shipment /app
USER mission
ENV PORT=8000
EXPOSE 8000
CMD ["./entrypoint.sh", "run"]
