# syntax=docker/dockerfile:1

FROM debian:bookworm-slim AS fetch-data
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*
COPY scripts/fetch-data.sh /app/scripts/fetch-data.sh
ENV WOW_DATA_DIR=/wow-data
ENTRYPOINT ["/app/scripts/fetch-data.sh"]

FROM rust:1.98.1-bookworm AS build
RUN apt-get update && apt-get install -y --no-install-recommends brotli cmake nodejs \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY Cargo.lock rust-toolchain.toml ./
COPY scripts/web-setup.sh scripts/web-setup.sh
ARG CARGO_BUILD_JOBS=8
ENV CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS}
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    ./scripts/web-setup.sh
COPY . .
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/app/target \
    ./scripts/web-build.sh \
    && cargo build --release --locked -p wenilla-host \
    && cargo test --release --locked -p wenilla-host \
    && node --test web/tests/*.test.mjs \
    && install -Dm755 target/release/wenilla-host /out/wenilla-host

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /out/wenilla-host /usr/local/bin/wenilla-host
COPY --from=build /app/web/dist /app/web/dist
USER 10001:10001
EXPOSE 8090
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -fsS -o /dev/null http://127.0.0.1:8090/ \
    && curl -fsS -o /dev/null 'http://127.0.0.1:8090/data/DBFilesClient%5CMap.dbc'
ENTRYPOINT ["wenilla-host"]
CMD ["--bind", "0.0.0.0:8090", "--www", "/app/web/dist", "--data", "/wow-data/Data"]
