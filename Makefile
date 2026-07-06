# GlyphSaver — built with swiftc alone (no Xcode required, CLT is enough).
# The .saver is a loadable Mach-O bundle assembled by hand; SPM has no bundle
# product type, so SPM covers only tests/preview (`make test`, `make preview`).

NAME    := GlyphSaver
BUILD   := build
BUNDLE  := $(BUILD)/$(NAME).saver
SDK     := $(shell xcrun --show-sdk-path)
MIN     := 13.0
ARCHS   := arm64 x86_64
INSTALL_DIR := $(HOME)/Library/Screen Savers

SWIFTFLAGS := -O -whole-module-optimization -parse-as-library -swift-version 5

CORE_SRC  := $(wildcard Sources/GlyphSaverCore/*.swift Sources/GlyphSaverCore/Effects/*.swift)
KIT_SRC   := $(wildcard Sources/GlyphSaverKit/*.swift)
SAVER_SRC := $(wildcard Saver/*.swift)

.PHONY: all saver test preview bench install uninstall verify clean

all: saver

saver: $(BUNDLE)

$(BUNDLE): $(CORE_SRC) $(KIT_SRC) $(SAVER_SRC) Saver/Info.plist Makefile
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS"
	@for arch in $(ARCHS); do \
	  echo "== $$arch =="; \
	  mkdir -p "$(BUILD)/$$arch"; \
	  swiftc $(SWIFTFLAGS) -target $$arch-apple-macos$(MIN) -sdk "$(SDK)" \
	    -module-name GlyphSaverCore \
	    -emit-module -emit-module-path "$(BUILD)/$$arch/GlyphSaverCore.swiftmodule" \
	    -emit-object -o "$(BUILD)/$$arch/core.o" \
	    $(CORE_SRC) || exit 1; \
	  swiftc $(SWIFTFLAGS) -target $$arch-apple-macos$(MIN) -sdk "$(SDK)" \
	    -module-name GlyphSaverKit -I "$(BUILD)/$$arch" \
	    -emit-module -emit-module-path "$(BUILD)/$$arch/GlyphSaverKit.swiftmodule" \
	    -emit-object -o "$(BUILD)/$$arch/kit.o" \
	    $(KIT_SRC) || exit 1; \
	  swiftc $(SWIFTFLAGS) -target $$arch-apple-macos$(MIN) -sdk "$(SDK)" \
	    -module-name $(NAME) -I "$(BUILD)/$$arch" \
	    -emit-object -o "$(BUILD)/$$arch/saver.o" \
	    $(SAVER_SRC) || exit 1; \
	  swiftc -target $$arch-apple-macos$(MIN) -sdk "$(SDK)" \
	    -emit-library -Xlinker -bundle \
	    -o "$(BUILD)/$$arch/$(NAME)" \
	    "$(BUILD)/$$arch/core.o" "$(BUILD)/$$arch/kit.o" "$(BUILD)/$$arch/saver.o" \
	    -framework ScreenSaver -framework AppKit -framework CoreText || exit 1; \
	done
	lipo -create $(foreach a,$(ARCHS),"$(BUILD)/$(a)/$(NAME)") \
	  -output "$(BUNDLE)/Contents/MacOS/$(NAME)"
	cp Saver/Info.plist "$(BUNDLE)/Contents/Info.plist"
	codesign --force --sign - --timestamp=none "$(BUNDLE)"
	@echo "Built $(BUNDLE)"
	@otool -h "$(BUNDLE)/Contents/MacOS/$(NAME)" | tail -3

APP := $(BUILD)/GlyphSaver Studio.app

app:
	swift build -c release --product GlyphSaverStudio
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	cp .build/release/GlyphSaverStudio "$(APP)/Contents/MacOS/GlyphSaverStudio"
	cp StudioApp/Info.plist "$(APP)/Contents/Info.plist"
	codesign --force --sign - --timestamp=none "$(APP)"
	@echo "Built $(APP)"

install-app: app
	rm -rf "$(HOME)/Applications/GlyphSaver Studio.app"
	mkdir -p "$(HOME)/Applications"
	cp -R "$(APP)" "$(HOME)/Applications/"
	@echo "Installed to ~/Applications/GlyphSaver Studio.app"

test:
	swift run GlyphSaverTests

preview:
	swift run GlyphSaverPreview

bench:
	swift run -c release GlyphSaverPreview --bench

verify: saver
	swift scripts/verify-bundle.swift "$(BUNDLE)"

install: saver
	rm -rf "$(INSTALL_DIR)/$(NAME).saver"
	mkdir -p "$(INSTALL_DIR)"
	cp -R "$(BUNDLE)" "$(INSTALL_DIR)/"
	@# macOS caches loaded savers aggressively; kill the hosts so System
	@# Settings picks up the fresh build (they respawn on demand).
	-pkill -f legacyScreenSaver 2>/dev/null || true
	-pkill -x ScreenSaverEngine 2>/dev/null || true
	@echo "Installed to $(INSTALL_DIR)/$(NAME).saver"
	@echo "Select it in System Settings → Screen Saver (relaunch Settings if it was open)."

uninstall:
	rm -rf "$(INSTALL_DIR)/$(NAME).saver"
	-pkill -f legacyScreenSaver 2>/dev/null || true

clean:
	rm -rf "$(BUILD)" .build
