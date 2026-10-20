#!/usr/bin/env bash
set -euo pipefail
mkdir -p build
nim c --nimcache:build/nimcache --mm:arc --threads:on --path:src --passL:"-L$LICENSEBOX_LIB_DIR" --out:build/binding -r tests/binding.nim
nim c --nimcache:build/nimcache --mm:arc --threads:on --path:src --passL:"-L$LICENSEBOX_LIB_DIR" --out:build/adapter tests/adapter.nim
NIMBLE_DIR="$PWD/build/nimble" nimble install -y
# nimble 0.16+ installs to pkgs2/<name>-<version>-<checksum>; older ones to pkgs/.
package=$(ls -d build/nimble/pkgs*/licensebox-* | head -n1)
nim c --path:"$package" --nimcache:build/nimcache --mm:arc --threads:on --passL:"-L$LICENSEBOX_LIB_DIR" --out:build/consumer examples/status.nim
