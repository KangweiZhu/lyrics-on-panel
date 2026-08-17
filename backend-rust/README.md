# Lyrics-on-Panel Rust Backend

This is an experimental Rust implementation of the Lyrics-on-Panel backend.
It intentionally lives alongside the production Python backend in `../backend`
and is not installed by the default `scripts/install-backend.sh` script.

## Build and test

```bash
cargo test --locked
cargo build --release --locked
```

## Install from this checkout

```bash
./scripts/install-local-rust-backend.sh
```

The installer creates a separate executable at
`~/.local/libexec/lyrics-on-panel-rust/lyrics-on-panel-backend` and a separate
`Universal-Mpris-LyricServer-Rust.service` unit. Both implementations use the
same WebSocket port, so stop the Python backend service before starting the
Rust service.
