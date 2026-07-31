.PHONY: app core run bundle release publish test clean

# debug for dev, release for anything that leaves this machine.
CONFIG ?= debug

# Full rebuild: Rust core + Swift bindings/xcframework, then the macOS app.
# (build-core.sh always builds the Rust side --release.)
app: core
	cd macos && swift build -c $(CONFIG)

# Rust core → dist/Katalog.xcframework + Generated/katalog.swift.
core:
	./build-core.sh

# Rebuild everything and launch the app.
run: app
	cd macos && swift run Katalog

# Sandbox entitlements, applied when bundling. Sandboxed is what ships, so it
# is the default — but it redirects Application Support (and so the library
# index) into ~/Library/Containers/org.stromer.katalog. To bundle the way the
# app used to behave: make bundle ENTITLEMENTS=
ENTITLEMENTS ?= macos/Katalog.entitlements

# Ad-hoc by default; `release` overrides with the Developer ID cert and adds
# the hardened runtime + secure timestamp that notarization insists on.
SIGN ?= -
CODESIGN_FLAGS ?=

# Assemble a real Katalog.app (self-contained: core links statically) and
# register it with LaunchServices so it shows up as an .epub handler.
# Then: right-click any .epub → Open With → Katalog → Change All… to default it.
bundle: app
	rm -rf dist/Katalog.app
	mkdir -p dist/Katalog.app/Contents/MacOS dist/Katalog.app/Contents/Resources
	cp macos/Info.plist dist/Katalog.app/Contents/Info.plist
	cp macos/.build/$(CONFIG)/Katalog dist/Katalog.app/Contents/MacOS/Katalog
	macos/build-icon.sh macos/icon.svg dist/Katalog.app/Contents/Resources/AppIcon.icns
	codesign --force --sign "$(SIGN)" $(CODESIGN_FLAGS) $(if $(ENTITLEMENTS),--entitlements $(ENTITLEMENTS)) dist/Katalog.app
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(PWD)/dist/Katalog.app"
	@echo "Built dist/Katalog.app — set default via Finder Get Info → Open With → Change All."

TEAM_ID ?= J7794KYKGV
DEV_ID  ?= Developer ID Application: Richard Stromer ($(TEAM_ID))
PLIST    = macos/Info.plist
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" $(PLIST))
BUILD   := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleVersion" $(PLIST))
DMG      = dist/Katalog-$(VERSION).dmg

# Notarization credentials, already stored in the keychain from the App Store
# Connect API key. See the README to recreate the profile on another machine.
NOTARY_PROFILE ?= katalog-notary

# Signed, notarized, stapled DMG for a GitHub release. Notarizing takes a few
# minutes; --wait blocks until Apple answers.
# ponytail: arm64 only, because build-core.sh builds the host arch. Intel needs
# both cargo targets lipo'd there first.
release:
	$(MAKE) bundle CONFIG=release SIGN="$(DEV_ID)" \
		CODESIGN_FLAGS="--options runtime --timestamp"
	rm -rf dist/dmg $(DMG)
	mkdir -p dist/dmg
	cp -R dist/Katalog.app dist/dmg/
	ln -s /Applications dist/dmg/Applications
	hdiutil create -volname Katalog -srcfolder dist/dmg -ov -format ULFO $(DMG)
	rm -rf dist/dmg
	codesign --force --sign "$(DEV_ID)" --timestamp $(DMG)
	xcrun notarytool submit $(DMG) --keychain-profile $(NOTARY_PROFILE) --wait
	xcrun stapler staple $(DMG)
	@echo "Notarized $(DMG) — attach it to a GitHub release."

# Cut a release end to end:  make publish VERSION=0.2
# Bumps the version, builds and notarizes, then commits, tags and publishes to
# GitHub. Notarizing happens before anything is committed or pushed, so a failed
# build leaves only an uncommitted plist edit behind (git checkout $(PLIST)).
publish:
	@test "$(origin VERSION)" = "command line" || { echo "usage: make publish VERSION=0.2"; exit 1; }
	@test -z "$$(git status --porcelain)" || { echo "working tree is dirty"; exit 1; }
	@! git rev-parse -q --verify v$(VERSION) >/dev/null \
		|| { echo "tag v$(VERSION) already exists"; exit 1; }
	/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $(VERSION)" $(PLIST)
	/usr/libexec/PlistBuddy -c "Set CFBundleVersion $$(($(BUILD) + 1))" $(PLIST)
	$(MAKE) release VERSION=$(VERSION)
	git commit -q -m "Release $(VERSION)" $(PLIST)
	git tag v$(VERSION)
	git push origin HEAD v$(VERSION)
	gh release create v$(VERSION) $(DMG) --title "Katalog $(VERSION)" --generate-notes
	@echo "Published v$(VERSION)."

# Core unit tests (epub parse + library roundtrip).
test:
	cargo test

clean:
	cargo clean
	rm -rf dist macos/Generated macos/.build
