.PHONY: app core run bundle test clean

# Full rebuild: Rust core + Swift bindings/xcframework, then the macOS app.
app: core
	cd macos && swift build

# Rust core → dist/Katalog.xcframework + Generated/katalog.swift.
core:
	./build-core.sh

# Rebuild everything and launch the app.
run: app
	cd macos && swift run Katalog

# Assemble a real Katalog.app (self-contained: core links statically) and
# register it with LaunchServices so it shows up as an .epub handler.
# Then: right-click any .epub → Open With → Katalog → Change All… to default it.
bundle: app
	rm -rf dist/Katalog.app
	mkdir -p dist/Katalog.app/Contents/MacOS dist/Katalog.app/Contents/Resources
	cp macos/Info.plist dist/Katalog.app/Contents/Info.plist
	cp macos/.build/debug/Katalog dist/Katalog.app/Contents/MacOS/Katalog
	macos/build-icon.sh macos/icon.svg dist/Katalog.app/Contents/Resources/AppIcon.icns
	codesign --force --sign - dist/Katalog.app
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(PWD)/dist/Katalog.app"
	@echo "Built dist/Katalog.app — set default via Finder Get Info → Open With → Change All."

# Core unit tests (epub parse + library roundtrip).
test:
	cargo test

clean:
	cargo clean
	rm -rf dist macos/Generated macos/.build
