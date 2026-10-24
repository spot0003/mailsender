#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$project_root/app"
fvm flutter pub get --enforce-lockfile
fvm flutter analyze
fvm flutter test
cd "$project_root"
cargo test --locked --manifest-path packages/core/Cargo.toml --features full -j 3
cargo build --locked -p rust_lib_localsend_app -j 3
cd "$project_root/packages/localsend_isolates"
fvm flutter test
cd "$project_root"
# Use the caller's activated Python venv with requirements.lock already installed.
python -m unittest discover -s quicklink/tests -v
