.PHONY: app core run test clean

# Full rebuild: Rust core + Swift bindings/xcframework, then the macOS app.
app: core
	cd macos && swift build

# Rust core → dist/Katalog.xcframework + Generated/katalog.swift.
core:
	./build-core.sh

# Rebuild everything and launch the app.
run: app
	cd macos && swift run Katalog

# Core unit tests (epub parse + library roundtrip).
test:
	cargo test

clean:
	cargo clean
	rm -rf dist macos/Generated macos/.build
