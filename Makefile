.PHONY: app core run bundle release publish test clean

# `publish` uses Bash for its version-selection prompt and bump helper.
SHELL := /bin/bash

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

# Cut a release end to end. With no options, choose patch/minor/major at a
# prompt; use BUMP=patch (or minor/major) to avoid the prompt, or VERSION=0.2.0
# to specify an exact version. Notarization happens before anything is committed
# or pushed, and a failed build restores the plist.
publish:
	@set -euo pipefail; \
	command -v gh >/dev/null || { echo "gh is not installed" >&2; exit 1; }; \
	[[ -z "$$(git status --porcelain)" ]] || { echo "working tree is dirty" >&2; exit 1; }; \
	bump() { local ma mi pa; IFS=. read -r ma mi pa <<< "$$1"; case "$$2" in patch) pa=$$(( $${pa:-0} + 1 ));; minor) mi=$$(( $${mi:-0} + 1 )); pa=0;; major) ma=$$(( $${ma:-0} + 1 )); mi=0; pa=0;; esac; echo "$${ma:-0}.$${mi:-0}.$${pa:-0}"; }; \
	if [[ "$(origin VERSION)" == "command line" ]]; then version="$(VERSION)"; \
	else \
		latest=$$(git tag --list 'v*' --sort=-v:refname | head -1); latest=$${latest#v}; latest=$${latest:-0.0.0}; \
		kind="$(BUMP)"; \
		if [[ -z "$$kind" ]]; then \
			echo "Latest release: v$$latest"; echo "  1) patch  $$(bump "$$latest" patch)"; echo "  2) minor  $$(bump "$$latest" minor)"; echo "  3) major  $$(bump "$$latest" major)"; \
			read -rp "Which? [1-3] " choice; case "$$choice" in 1) kind=patch;; 2) kind=minor;; 3) kind=major;; *) echo "aborted" >&2; exit 1;; esac; \
		fi; \
		case "$$kind" in patch|minor|major) version=$$(bump "$$latest" "$$kind");; *) echo "BUMP must be patch, minor, or major" >&2; exit 1;; esac; \
	fi; \
	git rev-parse -q --verify "v$$version" >/dev/null && { echo "tag v$$version already exists" >&2; exit 1; }; \
	read -rp "Build, tag and publish v$$version? [y/N] " ok; [[ "$$ok" == [yY] ]] || { echo "aborted"; exit 1; }; \
	build=$$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" $(PLIST)); \
	/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $$version" $(PLIST); \
	/usr/libexec/PlistBuddy -c "Set CFBundleVersion $$((build + 1))" $(PLIST); \
	if ! $(MAKE) release VERSION="$$version"; then git checkout -- $(PLIST); echo "build failed — version bump reverted" >&2; exit 1; fi; \
	git commit -q -m "Release $$version" $(PLIST); \
	git tag "v$$version"; git push -q origin HEAD "v$$version"; \
	gh release create "v$$version" "dist/Katalog-$$version.dmg" --title "Katalog $$version" --generate-notes; \
	echo "Published v$$version."

# Core unit tests (epub parse + library roundtrip).
test:
	cargo test

clean:
	cargo clean
	rm -rf dist macos/Generated macos/.build
