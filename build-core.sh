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
# Build beside the real one and swap: a failure here (no Xcode selected, say)
# used to leave the app with no framework at all.
mkdir -p dist
rm -rf dist/.staging  # xcodebuild insists the output end in .xcframework
xcodebuild -create-xcframework \
  -library "$STATIC" -headers "$HEADERS" \
  -output dist/.staging/Katalog.xcframework
rm -rf dist/Katalog.xcframework
mv dist/.staging/Katalog.xcframework dist/Katalog.xcframework
rmdir dist/.staging

echo "==> done: dist/Katalog.xcframework + $GEN/katalog.swift"
