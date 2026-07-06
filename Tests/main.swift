import Foundation
import GlyphSaverCore

// Minimal test harness: CLT installs ship no XCTest/Swift Testing, so this is a
// plain executable that exits non-zero on any failure (`make test`).

var testsRun = 0
var failures: [String] = []
var currentTest = ""

func test(_ name: String, _ body: () -> Void) {
    currentTest = name
    testsRun += 1
    body()
}

func expect(_ condition: Bool, _ message: String, line: Int = #line) {
    if !condition {
        failures.append("[\(currentTest)] line \(line): \(message)")
    }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String, line: Int = #line) {
    if a != b {
        failures.append("[\(currentTest)] line \(line): \(message) — got \(a), expected \(b)")
    }
}

// MARK: - Helpers

let simDT = 1.0 / 60.0

func makeContext(cols: Int = 80, rows: Int = 24, art: AsciiArt = DefaultArt.art,
                 theme: Theme = .omarchy, seed: UInt64 = 42,
                 reducedMotion: Bool = false) -> EffectContext {
    EffectContext(cols: cols, rows: rows, art: art, theme: theme,
                  seed: seed, reducedMotion: reducedMotion)
}

/// Steps the effect until complete (or timeout). Returns (completed, sawFullArt):
/// whether some frame showed every art cell with its true scalar.
func runEffect(_ effect: GlyphEffect, ctx: EffectContext,
               maxSimSeconds: Double = 45) -> (completed: Bool, sawFullArt: Bool) {
    var canvas = GlyphCanvas(cols: ctx.cols, rows: ctx.rows)
    effect.reset(ctx)
    var sawFullArt = ctx.artCells.isEmpty
    var t = 0.0
    while t < maxSimSeconds && !effect.isComplete {
        effect.update(dt: simDT, canvas: &canvas)
        t += simDT
        if !sawFullArt {
            sawFullArt = ctx.artCells.allSatisfy { cell in
                canvas.at(x: cell.x, y: cell.y)?.scalar == cell.scalar
            }
        }
    }
    return (effect.isComplete, sawFullArt)
}

// MARK: - RGBA

test("RGBA lerp endpoints and midpoint") {
    let mid = RGBA.lerp(.black, .white, 0.5)
    expect(abs(mid.r - 0.5) < 0.001, "midpoint r should be 0.5")
    expectEqual(RGBA.lerp(.black, .white, 0), .black, "t=0 returns start")
    expectEqual(RGBA.lerp(.black, .white, 1), .white, "t=1 returns end")
    expectEqual(RGBA.lerp(.black, .white, 2), .white, "t clamps above 1")
}

test("RGBA hex parsing") {
    let c = RGBA(hex: 0xFF8000)
    expect(abs(c.r - 1.0) < 0.01 && abs(c.g - 0.5) < 0.01 && c.b < 0.01, "0xFF8000 parses")
}

// MARK: - GlyphCanvas

test("Canvas clips out-of-bounds writes") {
    var c = GlyphCanvas(cols: 4, rows: 3)
    c.put(GlyphCell("X", fg: .white), x: -1, y: 0)
    c.put(GlyphCell("X", fg: .white), x: 4, y: 0)
    c.put(GlyphCell("X", fg: .white), x: 0, y: 3)
    expect(c.cells.allSatisfy { $0 == .blank }, "no OOB write landed")
    c.put(GlyphCell("A", fg: .white), x: 3, y: 2)
    expectEqual(c.at(x: 3, y: 2)?.scalar, "A", "in-bounds write lands")
    expectEqual(c.at(x: 4, y: 2), nil, "OOB read returns nil")
}

test("Canvas guards degenerate size (Tahoe 0x0 bug)") {
    let c = GlyphCanvas(cols: 0, rows: 0)
    expect(c.cols == 1 && c.rows == 1, "degenerate canvas clamps to 1x1")
}

test("Canvas fadeAll moves colors toward target") {
    var c = GlyphCanvas(cols: 2, rows: 1)
    c.put(GlyphCell("A", fg: .white), x: 0, y: 0)
    c.fadeAll(toward: .black, t: 1)
    expectEqual(c.at(x: 0, y: 0)?.fg, .black, "full fade reaches target")
}

// MARK: - SeededRandom

test("SeededRandom is deterministic") {
    var a = SeededRandom(seed: 7)
    var b = SeededRandom(seed: 7)
    for _ in 0..<100 {
        expectEqual(a.next(), b.next(), "same seed, same sequence")
    }
    var c = SeededRandom(seed: 8)
    var d = SeededRandom(seed: 7)
    expect((0..<10).map { _ in c.next() } != (0..<10).map { _ in d.next() },
           "different seeds diverge")
}

// MARK: - AsciiArt

test("AsciiArt parses and trims") {
    let art = AsciiArt(text: "\n\n  AB\t\n  CDE   \n\n")
    expectEqual(art.height, 2, "leading/trailing blank lines dropped")
    expectEqual(art.width, 5, "width is longest line after trailing whitespace strip")
    expectEqual(AsciiArt(text: "A\tB").width, 4, "mid-line tab expands to two spaces")
}

test("AsciiArt empty input falls back") {
    let art = AsciiArt(text: "   \n  \n")
    expect(art.width >= 1 && art.height == 1, "blank art becomes 1-cell fallback")
}

test("AsciiArt centers on canvas") {
    let art = AsciiArt(text: "ABCD\nEFGH")
    let o = art.origin(cols: 10, rows: 6)
    expectEqual(o.x, 3, "x centered")
    expectEqual(o.y, 2, "y centered")
    let cells = art.placedCells(cols: 10, rows: 6)
    expectEqual(cells.count, 8, "all glyphs placed")
    expect(cells.contains(ArtCell(x: 3, y: 2, scalar: "A")), "top-left glyph at origin")
}

test("AsciiArt crops when larger than canvas") {
    let art = AsciiArt(text: String(repeating: "X", count: 100))
    let cells = art.placedCells(cols: 10, rows: 1)
    expect(!cells.isEmpty && cells.count <= 10, "oversized art crops to canvas")
    expect(cells.allSatisfy { $0.x >= 0 && $0.x < 10 }, "cropped cells in bounds")
}

test("Default art parses to sane dimensions") {
    let art = DefaultArt.art
    expect(art.width > 30 && art.width < 60, "logo width plausible, got \(art.width)")
    expectEqual(art.height, 8, "logo is 8 rows (6 letters + gap + subtitle)")
}

// MARK: - Config

test("Config sanitized clamps garbage") {
    var c = Config.default
    c.fps = 500
    c.speed = .nan
    c.theme = "hotdog"
    c.enabledEffects = ["nope", "matrix"]
    c.cycleMode = "chaos"
    c.fontSize = -3
    let s = c.sanitized
    expectEqual(s.fps, 120, "fps clamps to 120")
    expectEqual(s.speed, 1.0, "NaN speed falls back to default")
    expectEqual(s.theme, "omarchy", "unknown theme falls back")
    expectEqual(s.enabledEffects, ["matrix"], "unknown effects dropped")
    expectEqual(s.cycleMode, "random", "bad cycle mode falls back")
    expectEqual(s.fontSize, 0, "negative font size becomes auto")
}

test("Config from garbage dictionary never crashes") {
    let dict: [String: Any] = [
        "customArt": 12345,
        "enabledEffects": "matrix",
        "theme": ["a"],
        "fps": "fast",
        "speed": Double.infinity,
        "reducedMotion": "yes",
    ]
    let c = Config.fromDictionary(dict)
    expectEqual(c.theme, "omarchy", "garbage theme ignored")
    expectEqual(c.fps, 60, "garbage fps ignored")
    expectEqual(c.speed, 1.0, "infinite speed sanitized")
    expectEqual(c.enabledEffects, EffectRegistry.allNames, "garbage effects ignored")
}

test("Config dictionary roundtrip") {
    var c = Config.default
    c.theme = "matrix"
    c.fps = 30
    c.customArt = "hi\nthere"
    expectEqual(Config.fromDictionary(c.toDictionary()), c.sanitized, "roundtrip preserves")
}

// MARK: - Theme

test("Theme lookup and ramp") {
    expect(Theme.named("matrix") != nil, "matrix theme exists")
    expect(Theme.named("nope") == nil, "unknown theme nil")
    expectEqual(Theme.all.count, 4, "four built-in themes")
    let t = Theme.matrix
    expectEqual(t.rampColor(0), t.ramp.first!, "ramp t=0 is first stop")
    expectEqual(t.rampColor(1), t.ramp.last!, "ramp t=1 is last stop")
}

// MARK: - Effects

for name in EffectRegistry.allNames {
    test("Effect \(name) completes and reveals the art") {
        guard let effect = EffectRegistry.make(name) else {
            expect(false, "registry makes \(name)")
            return
        }
        let ctx = makeContext()
        let result = runEffect(effect, ctx: ctx)
        expect(result.completed, "\(name) reached isComplete within sim budget")
        expect(result.sawFullArt, "\(name) showed the complete art at some frame")
    }

    test("Effect \(name) is deterministic for a fixed seed") {
        guard let e1 = EffectRegistry.make(name), let e2 = EffectRegistry.make(name) else {
            expect(false, "registry makes \(name)")
            return
        }
        let ctx = makeContext(seed: 1234)
        var c1 = GlyphCanvas(cols: ctx.cols, rows: ctx.rows)
        var c2 = GlyphCanvas(cols: ctx.cols, rows: ctx.rows)
        e1.reset(ctx)
        e2.reset(ctx)
        for _ in 0..<180 {
            e1.update(dt: simDT, canvas: &c1)
            e2.update(dt: simDT, canvas: &c2)
        }
        expect(c1.cells == c2.cells, "\(name) same seed, same frame 180")
    }

    test("Effect \(name) survives empty art") {
        guard let effect = EffectRegistry.make(name) else { return }
        let ctx = makeContext(art: AsciiArt(text: ""), seed: 5)
        let result = runEffect(effect, ctx: ctx)
        expect(result.completed, "\(name) completes with empty art")
    }

    test("Effect \(name) survives tiny canvas with big art") {
        guard let effect = EffectRegistry.make(name) else { return }
        let ctx = makeContext(cols: 3, rows: 2, seed: 5)
        let result = runEffect(effect, ctx: ctx)
        expect(result.completed, "\(name) completes on 3x2 canvas")
    }

    test("Effect \(name) completes with reduced motion") {
        guard let effect = EffectRegistry.make(name) else { return }
        let ctx = makeContext(seed: 9, reducedMotion: true)
        let result = runEffect(effect, ctx: ctx, maxSimSeconds: 60)
        expect(result.completed, "\(name) completes in reduced motion")
    }
}

// MARK: - AnimationController

test("Controller cycles effects without immediate repeats") {
    var config = Config.default
    config.speed = 4  // fastest sanctioned speed to shorten the sim
    let controller = AnimationController(cols: 60, rows: 20, config: config, seed: 77)
    var played: [String] = []
    var lastName = controller.currentEffect?.name ?? ""
    played.append(lastName)
    var t = 0.0
    while t < 180 && played.count < 7 {
        controller.step(dt: simDT)
        t += simDT
        if let now = controller.currentEffect?.name, now != lastName {
            played.append(now)
            lastName = now
        }
    }
    expect(played.count >= 4, "cycled through several effects, got \(played)")
    for i in 1..<played.count {
        expect(played[i] != played[i - 1], "no back-to-back repeat: \(played)")
    }
}

test("Controller clamps runaway delta time") {
    let controller = AnimationController(cols: 40, rows: 12, config: .default, seed: 3)
    controller.step(dt: 9999)   // app nap / debugger pause
    controller.step(dt: -5)     // clock weirdness
    expect(true, "no crash on absurd dt")
}

test("Controller resize rebuilds canvas") {
    let controller = AnimationController(cols: 40, rows: 12, config: .default, seed: 3)
    controller.step(dt: simDT)
    controller.resize(cols: 100, rows: 30)
    expectEqual(controller.canvas.cols, 100, "canvas took new cols")
    controller.step(dt: simDT)
    expect(true, "steps after resize")
}

test("Controller sequential mode preserves order") {
    var config = Config.default
    config.cycleMode = "sequential"
    config.speed = 4
    let controller = AnimationController(cols: 60, rows: 20, config: config, seed: 1)
    var played: [String] = [controller.currentEffect?.name ?? ""]
    var t = 0.0
    while t < 180 && played.count < 6 {
        controller.step(dt: simDT)
        t += simDT
        if let now = controller.currentEffect?.name, now != played.last {
            played.append(now)
        }
    }
    let names = EffectRegistry.allNames
    for (i, name) in played.enumerated() {
        expectEqual(name, names[i % names.count], "sequential order at position \(i)")
    }
}

// MARK: - Summary

if failures.isEmpty {
    print("OK — \(testsRun) tests passed")
    exit(0)
} else {
    print("FAILED — \(failures.count) failure(s) in \(testsRun) tests:")
    for f in failures { print("  ✗ \(f)") }
    exit(1)
}
