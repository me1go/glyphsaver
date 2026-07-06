# GlyphSaver — Design

A native macOS screensaver (`.saver`) that renders fast, Omarchy-style terminal ASCII/block-art
animations: Matrix rain, decrypt reveals, glitch/overflow noise — all drawn as a simulated
terminal glyph grid on a dark background.

## Constraints discovered up front

- **No Xcode installed** (Command Line Tools only, Swift 6.3, macOS 26.4, Apple Silicon).
  → Build with `swiftc` directly and assemble the `.saver` bundle in a Makefile. No `.xcodeproj`.
- **No XCTest / Swift Testing in CLT** → tests are a plain SPM executable target (`make test`)
  that runs deterministic assertions and exits non-zero on failure.
- Third-party savers run inside `legacyScreenSaver.appex` (sandboxed) → settings go through
  `ScreenSaverDefaults`, custom art is stored as a string in defaults (no reliance on reading
  arbitrary user files).

## Architecture

```
ScreenSaverView (Saver/ — thin shell)
   └── GlyphSaverContentView (GlyphSaverKit — AppKit)
         ├── AnimationController (Core)   — effect scheduling, delta-time stepping
         │     ├── GlyphCanvas (Core)     — cols×rows buffer of GlyphCell
         │     └── GlyphEffect (Core)     — MatrixRain / Decrypt / OverflowGlitch / …
         ├── GlyphRenderer (Kit)          — batched CoreText glyph drawing, caches
         └── ConfigStore (Kit)            — ScreenSaverDefaults ⇄ Config (Core, Codable)
PreviewApp (dev harness)                  — same content view in a window + headless
                                            --snapshot / --bench modes for verification
```

### GlyphSaverCore (pure Swift, no AppKit)

- `RGBA` — 4×Float color, premultiplied nowhere, convertible in Kit. Pure value type so
  effects and tests never touch NSColor.
- `GlyphCell` — `scalar: UnicodeScalar, fg: RGBA, bg: RGBA?, bold: Bool`.
- `GlyphCanvas` — flat `[GlyphCell]` sized cols×rows; `clear()`, subscripts, bounds-safe `put`.
- `Theme` — name, background, art color, ramp (gradient stops) + accent colors.
  Built-ins: `omarchy` (monochrome blue-white on near-black), `matrix` (greens),
  `amber` (CRT amber), `ansi` (BBS 16-color).
- `AsciiArt` — parses multiline text, trims trailing blank lines, measures, computes centered
  origin for a given canvas, exposes per-cell target glyphs.
- `GlyphEffect` protocol:
  `name`, `reset(canvas:art:theme:rng:reducedMotion:)`, `update(dt:canvas:) -> Void`,
  `isComplete: Bool`. Effects are self-contained state machines: reveal → hold → fade-out.
- Effects (MVP):
  - **MatrixRain** — falling columns, bright head, fading tail, random speeds/lengths, char
    mutation; art cells lock in as rain passes over them; rain drains away during hold.
  - **Decrypt** — art cells flicker through cipher symbols and lock to the real glyph in a
    scattered order with a dark→bright color sweep; idle shimmer during hold.
  - **OverflowGlitch** — fast scrolling noise/hex-dump rows flood the screen, glitch bursts
    (horizontal tearing + colored block cells), noise collapses to reveal art; residual
    flickers during hold.
- `AnimationController` — owns canvas + effect instances; cycles enabled effects
  (random or sequential), steps active effect with clamped delta-time, applies a short
  fade between effects, respects `speed` multiplier and `reducedMotion`.
- `Config` (Codable) — customArt, enabledEffects, theme, fps, speed, fontSize (0 = auto-fit),
  cycleMode, reducedMotion. `Config.fromDictionary` is tolerant: every field falls back to
  its default on wrong type/missing/garbage. Invalid config can never crash.
- `SeededRandom` — SplitMix64; deterministic tests, per-screen seeds in production.

### GlyphSaverKit (AppKit, shared by saver + preview app)

- `GlyphRenderer` — draws a `GlyphCanvas` into a `CGContext`. Performance strategy:
  group cells by quantized color per frame, then one `CTFontDrawGlyphs` batch per color
  group (the terminal-emulator approach). Caches: `CTFont`s (regular/bold), scalar→`CGGlyph`
  map, cell metrics, `CGColor`s. No per-glyph NSAttributedString allocation.
- `GlyphSaverContentView` — NSView; computes grid size from bounds + font metrics
  (auto-fit font size when configured), owns controller + renderer, `tick()` advances with
  real delta-time and calls `setNeedsDisplay`; drawing happens in `draw(_:)` so AppKit's
  backing-scale transform gives Retina-crisp glyphs for free.
- `ConfigStore` — `ScreenSaverDefaults(forModuleWithName:)` in the saver, `UserDefaults`
  suite in the preview app; maps to/from `Config`.

### Saver target

`GlyphSaverView: ScreenSaverView` — `animationTimeInterval = 1/fps`, hosts the content view,
`animateOneFrame` calls `tick()`. One instance per display (system behavior) — each gets its
own RNG seed so screens don't animate in lockstep. `configureSheet` is a programmatic NSPanel:
theme popup, effect checkboxes, speed/fps sliders, custom-art text view, reduced motion.

### Build (Makefile)

- `make saver` — `swiftc` compiles Core+Kit+Saver into a loadable bundle binary
  (arm64 + x86_64 slices, lipo'd), assembled into `build/GlyphSaver.saver` with a hand-written
  `Info.plist` (`NSPrincipalClass` = the @objc-named view class), ad-hoc codesigned.
- `make install` — copies to `~/Library/Screen Savers`, kills `legacyScreenSaver` so
  System Settings picks up the new build.
- `make preview` / `make test` / `make bench` — SPM builds of the preview app and test runner.

### Verification plan

1. `make test` — deterministic effect/config/art assertions.
2. Preview app `--snapshot` — renders frames offscreen to PNGs; visually inspect each effect
   and theme.
3. Preview app `--bench` — frame-time report at 4K-equivalent grid size.
4. Soak: preview headless for an extended run sampling RSS to catch leaks.
5. Install the real `.saver` and verify it loads in System Settings (manual final check).

## Explicit non-goals (MVP)

Python/TTE embedding (packaging + sandbox risk, native effects cover the aesthetic),
ANSI `.ans` parsing, FIGlet generation, CRT shader effects — all documented as future work.
