#!/usr/bin/env bash
set -euo pipefail
mkdir -p build
nim c --nimcache:build/nimcache --mm:arc --threads:on --path:src --passL:"-L$LICENSEBOX_LIB_DIR" --out:build/binding -r tests/binding.nim
nim c --nimcache:build/nimcache --mm:arc --threads:on --path:src --passL:"-L$LICENSEBOX_LIB_DIR" --out:build/adapter tests/adapter.nim
NIMBLE_DIR="$PWD/build/nimble" nimble install -y
nim c --path:build/nimble/pkgs/licensebox-0.1.0 --nimcache:build/nimcache --mm:arc --threads:on --passL:"-L$LICENSEBOX_LIB_DIR" --out:build/consumer examples/status.nim
