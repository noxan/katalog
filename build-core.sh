#!/usr/bin/env bash
# Build the Rust core, generate Swift bindings, and package an xcframework
# that the macOS app links. Re-run whenever the core's public API changes.
#
# ponytail: builds for the host arch only. For a universal binary, build both
# aarch64/x86_64 targets and `lipo` them before -create-xcframework.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "==> cargo build --release"
cargo build --release -p katalog-core

DYLIB="target/release/libkatalog.dylib"
STATIC="target/release/libkatalog.a"
GEN="macos/Generated"

echo "==> generate Swift bindings"
rm -rf "$GEN"; mkdir -p "$GEN"
cargo run --release --bin uniffi-bindgen -- \
  generate --library "$DYLIB" --language swift --out-dir "$GEN"

# xcframework wants headers together with a file literally named module.modulemap.
HEADERS="$GEN/headers"
mkdir -p "$HEADERS"
mv "$GEN"/*.h "$HEADERS"/
mv "$GEN"/*.modulemap "$HEADERS/module.modulemap"

echo "==> assemble xcframework"
rm -rf dist/Katalog.xcframework
mkdir -p dist
xcodebuild -create-xcframework \
  -library "$STATIC" -headers "$HEADERS" \
  -output dist/Katalog.xcframework

echo "==> done: dist/Katalog.xcframework + $GEN/katalog.swift"
