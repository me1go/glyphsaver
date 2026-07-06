# GlyphSaver

A native macOS screensaver that renders fast, terminal-style ASCII/block-art
animations over your own text (rendered as big block letters) or pasted ASCII
art. All **37 effects from the TerminalTextEffects showroom** are implemented
natively in Swift. Inspired by the
[Omarchy](https://github.com/basecamp/omarchy) screensaver and
[TerminalTextEffects](https://github.com/ChrisBuilds/terminaltexteffects).

No Xcode required: builds with the Command Line Tools alone (`swiftc` + `make`).
Pure Swift + AppKit + ScreenSaver framework — no Python, no WebView, no
Terminal windows.

## Features

- **All 37 TTE showroom effects**, cycled randomly or sequentially, each:
  reveal → hold → fade. beams, binarypath, blackhole, bouncyballs, bubbles,
  burn, colorshift, crumble, decrypt, errorcorrect, expand, fireworks,
  highlight, laseretch, matrix, middleout, orbittingvolley, overflow, pour,
  print, rain, randomsequence, rings, scattered, slice, slide, smoke,
  spotlights, spray, swarm, sweep, synthgrid, thunderstorm, unstable, vhstape,
  waves, wipe.
- **6 themes**: Omarchy (Tokyo Night blues), Matrix Green, Amber CRT, ANSI/BBS,
  Synthwave (magenta→cyan→white gradient), Rainbow (drifting hue cycle). Most
  themes color the art with a gradient across its bounding box, TTE-style.
- **Your text as block art**: type plain texts ("LEAP CRM", "me1g0") and they
  render through a built-in ANSI-Shadow block font — no FIGlet needed. Multiple
  texts rotate between effect cycles. Raw multi-line ASCII art also supported.
- **GlyphSaver Studio** — a companion Mac app with a live preview and all
  settings; one click pushes the config straight to the screensaver.
- Multi-monitor: one independently-seeded animation per display
- 60 fps default (30/120 configurable), speed 0.25–4×, reduced-motion mode
- Renders ~28,000 cells at 4K in under 1 ms/frame (batched CoreText)

## Build & install

```sh
make            # builds build/GlyphSaver.saver (universal arm64 + x86_64)
make install    # copies to ~/Library/Screen Savers and restarts the saver host
make install-app  # builds + installs ~/Applications/GlyphSaver Studio.app
```

Then: **System Settings → Screen Saver → Other → GlyphSaver**. If System
Settings was open during install, quit and reopen it.

## GlyphSaver Studio (recommended way to configure)

Open **GlyphSaver Studio** (in `~/Applications`). Left side is a live preview;
right side has every setting: texts (one per line), raw art, theme, all 37
effect checkboxes, cycle order, speed, frame rate, font size, reduced motion.

- Changes apply to the live preview as you type.
- **Apply to Screensaver** (⌘S) writes
  `~/Library/Application Support/GlyphSaver/config.json`, which the saver reads
  every time it starts — no reinstall, no System Settings dance.
- While config.json exists it *wins* over the in-saver Options sheet (the sheet
  shows a notice). **Remove Studio Config** hands control back to the sheet.

The sandboxed saver host can read (not write) the real home directory, which is
why the app→saver channel is a JSON file rather than shared preferences.

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

Use **GlyphSaver Studio** (above), or click **Options…** under the saver in
System Settings:

| Setting | Values | Default |
|---|---|---|
| Theme | Omarchy / Matrix / Amber / ANSI / Synthwave / Rainbow | Omarchy |
| Effects | any subset of the 37 | all |
| Cycle | random (no back-to-back repeats) or sequential | random |
| Speed | 0.25×–4× | 1× |
| Frame rate | 30 / 60 / 120 fps | 60 |
| Font size | auto-fit or 10–32 pt | auto-fit |
| Reduce motion | slower motion, no flicker/strobe/glitch bursts | off |
| Texts | one per line, block-font rendered, rotate per cycle | built-in logo |
| Custom art | pasted ASCII art shown as-is | — |

Sheet settings are stored via `ScreenSaverDefaults` under
`com.melgeorge.glyphsaver`; Studio settings live in
`~/Library/Application Support/GlyphSaver/config.json` and take precedence.
Invalid/garbage values are silently replaced with defaults — bad config can't
crash the saver.

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
