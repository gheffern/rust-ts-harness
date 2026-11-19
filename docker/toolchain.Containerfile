FROM rust:slim

# Install latest project-agnostic build, lint, profiling, and Node.js tools
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
    curl -fsSL https://deb.nodesource.com/setup_current.x | bash - && \
    apt-get install -y -qq nodejs && \
    rustup component add clippy rustfmt && \
    rustup target add wasm32-unknown-unknown && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install latest sccache, wasm-opt (binaryen), and cargo-nextest (no version/SHA pins)
RUN set -eu; \
    arch="$(uname -m)"; \
    case "$arch" in \
      x86_64)  sccache_arch="x86_64-unknown-linux-musl"; bin_arch="x86_64-linux"; nextest_url="https://get.nexte.st/latest/linux" ;; \
      aarch64) sccache_arch="aarch64-unknown-linux-musl"; bin_arch="aarch64-linux"; nextest_url="https://get.nexte.st/latest/linux-arm" ;; \
      *) echo "Unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    sccache_tag="$(curl -fsSL https://api.github.com/repos/mozilla/sccache/releases/latest | jq -r .tag_name)"; \
    curl -fsSL --retry 3 "https://github.com/mozilla/sccache/releases/download/${sccache_tag}/sccache-${sccache_tag}-${sccache_arch}.tar.gz" \
      | tar -xz --strip-components=1 -C /usr/local/bin "sccache-${sccache_tag}-${sccache_arch}/sccache"; \
    chmod 0755 /usr/local/bin/sccache; \
    wasm_tag="$(curl -fsSL https://api.github.com/repos/WebAssembly/binaryen/releases/latest | jq -r .tag_name)"; \
    curl -fsSL --retry 3 "https://github.com/WebAssembly/binaryen/releases/download/${wasm_tag}/binaryen-${wasm_tag}-${bin_arch}.tar.gz" \
      | tar -xz --strip-components=2 -C /usr/local/bin "binaryen-${wasm_tag}/bin/wasm-opt"; \
    chmod 0755 /usr/local/bin/wasm-opt; \
    curl -fsSL --retry 3 "${nextest_url}" | tar -xz -C /usr/local/cargo/bin; \
    chmod 0755 /usr/local/cargo/bin/cargo-nextest; \
    sccache --version && wasm-opt --version && cargo nextest --version

ENV CARGO_HOME=/usr/local/cargo
ENV SCCACHE_DIR=/sccache
