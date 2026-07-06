# GlyphSaver

A native macOS screensaver that renders fast, terminal-style ASCII/block-art
animations — Matrix rain, movie-style decryption, and buffer-overflow glitch
reveals — over your own ASCII art or the built-in block logo. Inspired by the
[Omarchy](https://github.com/basecamp/omarchy) screensaver and
[TerminalTextEffects](https://github.com/ChrisBuilds/terminaltexteffects).

No Xcode required: builds with the Command Line Tools alone (`swiftc` + `make`).
Pure Swift + AppKit + ScreenSaver framework — no Python, no WebView, no
Terminal windows.

## Features

- **3 effects**, cycled randomly or sequentially, each: reveal → hold → fade
  - `matrix` — digital rain with bright heads and fading trails that fills the
    screen, then resolves into the art
  - `decrypt` — ciphertext types in across the art, flickers, then locks to the
    real glyphs in scattered order with a white flash
  - `overflow` — shuffled copies of the art's own rows flood up from the bottom
    in scrolling color bands with glitch tearing, then the true art locks in
- **4 themes**: Omarchy (Tokyo Night blues), Matrix Green, Amber CRT, ANSI/BBS
- **Custom art**: paste any text/ASCII/block art in the options sheet; it is
  centered and the font auto-fits. Empty = built-in logo.
- Multi-monitor: one independently-seeded animation per display
- 60 fps default (30/120 configurable), speed 0.25–4×, reduced-motion mode
- Renders ~28,000 cells at 4K in under 1 ms/frame (batched CoreText)

## Build & install

```sh
make            # builds build/GlyphSaver.saver (universal arm64 + x86_64)
make install    # copies to ~/Library/Screen Savers and restarts the saver host
```

Then: **System Settings → Screen Saver → Other → GlyphSaver**. If System
Settings was open during install, quit and reopen it.

Other targets:

```sh
make test       # deterministic unit tests for the effect engine (no Xcode/XCTest)
make preview    # dev window: n = next effect, t = next theme, q = quit
make bench      # frame-time report at simulated 4K Retina
make verify     # loads the built bundle the way macOS does and checks it draws
make uninstall
```

The preview app also has headless modes used for development:

```sh
swift run -c release GlyphSaverPreview --snapshot /tmp/out --effect matrix --theme matrix
swift run -c release GlyphSaverPreview --bench --font 10 --seconds 15
swift run -c release GlyphSaverPreview --soak 1800   # memory soak, prints RSS
```

## Configuration

Click **Options…** under the saver in System Settings:

| Setting | Values | Default |
|---|---|---|
| Theme | Omarchy / Matrix Green / Amber CRT / ANSI-BBS | Omarchy |
| Effects | any subset of matrix, decrypt, overflow | all |
| Cycle | random (no back-to-back repeats) or sequential | random |
| Speed | 0.25×–4× | 1× |
| Frame rate | 30 / 60 / 120 fps | 60 |
| Font size | auto-fit or 10–32 pt | auto-fit |
| Reduce motion | slower fall, no flicker/glitch bursts | off |
| Custom art | any pasted text; centered, cropped if oversized | built-in logo |

Settings are stored via `ScreenSaverDefaults` (the only prefs mechanism that
works inside the sandboxed saver host), under the module
`com.melgeorge.glyphsaver`. Invalid/garbage values are silently replaced with
defaults — bad config can't crash the saver.

Tip for custom art: generate FIGlet/“ANSI Shadow” text at
[patorjk.com/software/taag](https://patorjk.com/software/taag/) and paste it in.

## Troubleshooting

- **New build doesn't show up / old animation still runs** — macOS caches
  loaded savers aggressively. `make install` already kills the host processes
  (`legacyScreenSaver`, `ScreenSaverEngine`), but System Settings itself also
  caches: quit and relaunch it, or select a different saver and back.
- **Preview pane in System Settings is black/frozen** — known System Settings
  bug on Sonoma+; select another saver, then re-select GlyphSaver. The actual
  fullscreen saver is unaffected.
- **Options button does nothing** — same cache issue; relaunch System Settings.
- **"GlyphSaver can't be opened" on another Mac** — the bundle is ad-hoc
  signed, fine for the machine that built it. On other machines run
  `xattr -d com.apple.quarantine ~/Library/Screen\ Savers/GlyphSaver.saver`
  or build from source there.
- **Battery/CPU** — on Sonoma+ macOS sometimes leaves saver instances running
  invisibly after dismissal. GlyphSaver listens for the system's
  `willstop` notification, tears down its timers, and exits the host — the
  documented community workaround (see ScreenSaverMinimal).
- **Changed settings don't apply to a running saver** — the engine reads
  config at start; lock/unlock once and the next activation picks it up.

## Architecture

```
GlyphSaverView (ScreenSaverView, thin shell — Saver/)
  └── GlyphSaverContentView (AppKit view + frame timer — Sources/GlyphSaverKit)
        ├── AnimationController (effect cycling, delta-time — Sources/GlyphSaverCore)
        │     └── GlyphEffect: MatrixRain | Decrypt | OverflowGlitch
        │           writes GlyphCell{scalar, fg, bg, bold} into GlyphCanvas
        └── GlyphRenderer (batched CTFontDrawGlyphs grouped by font+color)
PreviewApp — same content view in a window + headless snapshot/bench/soak
```

The core is pure Swift (no AppKit) and fully deterministic under a seeded RNG,
so effects are unit-testable and the preview app exercises byte-identical
animation code to the real saver. See `docs/DESIGN.md` for details and the
macOS Sonoma/Tahoe workarounds this build encodes.

## Credits & license

MIT — see `LICENSE`.

- Effect algorithms are original Swift implementations following the shapes of
  [TerminalTextEffects](https://github.com/ChrisBuilds/terminaltexteffects)
  (MIT) — thank you ChrisBuilds.
- Behavior modeled on the [Omarchy](https://github.com/basecamp/omarchy) (MIT)
  screensaver: black screen, centered logo, random effect per cycle.
- macOS saver survival tactics from
  [ScreenSaverMinimal](https://github.com/AerialScreensaver/ScreenSaverMinimal)
  (MIT) and the wider Aerial community.
- The built-in logo is original block art in the ANSI-Shadow style; Omarchy's
  own wordmark is not bundled.
