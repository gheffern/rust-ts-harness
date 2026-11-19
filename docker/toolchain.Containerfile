FROM rust:1.99-slim-trixie

# Install project-agnostic build, lint, profiling, and Node.js tools
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gh \
        jq \
        ripgrep \
        pkg-config \
        g++ \
        mold \
        valgrind \
        python3 && \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y -qq nodejs && \
    rustup component add clippy rustfmt && \
    rustup target add wasm32-unknown-unknown && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install pinned sccache v0.17.0 with SHA256 verification
RUN set -eu; \
    sccache_version=0.17.0; \
    sccache_sha256=67c4a96dd237c1f518f6b36083f270f9976d516f1e57fce891755ea782e50006; \
    archive="/tmp/sccache.tar.gz"; \
    curl -fsSL --retry 3 -o "$archive" \
        "https://github.com/mozilla/sccache/releases/download/v${sccache_version}/sccache-v${sccache_version}-x86_64-unknown-linux-musl.tar.gz"; \
    echo "${sccache_sha256}  $archive" | sha256sum --check --strict -; \
    tar -xzf "$archive" --strip-components=1 -C /usr/local/bin "sccache-v${sccache_version}-x86_64-unknown-linux-musl/sccache"; \
    chmod 0755 /usr/local/bin/sccache; \
    rm -f "$archive"; \
    sccache --version

# Install pinned wasm-opt 122 with SHA256 verification
RUN set -eu; \
    wasm_opt_version=122; \
    wasm_opt_sha256=dcf0d3b19d55a354f0a277812cbba603d8bf0231f52adccfc83ed3387b805dcd; \
    archive="/tmp/binaryen.tar.gz"; \
    curl -fsSL --retry 3 -o "$archive" \
        "https://github.com/WebAssembly/binaryen/releases/download/version_${wasm_opt_version}/binaryen-version_${wasm_opt_version}-x86_64-linux.tar.gz"; \
    echo "${wasm_opt_sha256}  $archive" | sha256sum --check --strict -; \
    tar -xzf "$archive" --strip-components=2 -C /usr/local/bin "binaryen-version_${wasm_opt_version}/bin/wasm-opt"; \
    chmod 0755 /usr/local/bin/wasm-opt; \
    rm -f "$archive"; \
    wasm-opt --version

# Install pinned cargo-nextest 0.9.143 with SHA256 verification
RUN set -eu; \
    nextest_version=0.9.143; \
    nextest_sha256=66786b9abe23920d022a182d1416b1bbc8130dd4872a9553d76985a1708dcd1e; \
    archive="/tmp/cargo-nextest.tar.gz"; \
    curl -fsSL --retry 3 -o "$archive" \
        "https://github.com/nextest-rs/nextest/releases/download/cargo-nextest-${nextest_version}/cargo-nextest-${nextest_version}-x86_64-unknown-linux-gnu.tar.gz"; \
    echo "${nextest_sha256}  $archive" | sha256sum --check --strict -; \
    tar -xzf "$archive" -C /usr/local/cargo/bin; \
    chmod 0755 /usr/local/cargo/bin/cargo-nextest; \
    rm -f "$archive"; \
    cargo nextest --version

ENV CARGO_HOME=/usr/local/cargo
ENV SCCACHE_DIR=/sccache
