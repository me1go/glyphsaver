import AppKit
import CoreText
import GlyphSaverCore

/// Draws a GlyphCanvas into a CGContext at 60fps by batching: cells are grouped
/// by (font, quantized color) and each group is emitted with one
/// CTFontDrawGlyphs call — no per-cell string layout or allocation.
public final class GlyphRenderer {
    public struct Metrics {
        public let fontSize: CGFloat
        public let cellWidth: CGFloat
        public let cellHeight: CGFloat
        public let ascent: CGFloat
    }

    public private(set) var metrics: Metrics

    private var fonts: [CTFont]                 // [0] regular, [1] bold, 2+ fallbacks
    private var glyphCache: [UInt32: (fontIndex: Int, glyph: CGGlyph)] = [:]
    private var boldGlyphCache: [UInt32: (fontIndex: Int, glyph: CGGlyph)] = [:]

    private struct Group {
        var fontIndex = 0
        var color = RGBA.clear
        var glyphs: [CGGlyph] = []
        var positions: [CGPoint] = []
    }

    private struct BackgroundGroup {
        var color = RGBA.clear
        var rects: [CGRect] = []
    }

    // Pool batches by frame slot, not color: animated palettes must not grow a
    // persistent cache indefinitely. Keep array capacity across draws.
    private var groups: [Group] = []
    private var backgroundGroups: [BackgroundGroup] = []
    private var groupIndices: [UInt64: Int] = [:]
    private var backgroundIndices: [UInt32: Int] = [:]

    public init(fontSize: CGFloat) {
        let regular = GlyphRenderer.bestFont(size: fontSize, bold: false)
        let bold = GlyphRenderer.bestFont(size: fontSize, bold: true)
        self.fonts = [regular, bold]
        self.metrics = GlyphRenderer.measure(font: regular, fontSize: fontSize)
    }

    /// Menlo → Monaco → SF Mono → system monospaced.
    static func bestFont(size: CGFloat, bold: Bool) -> CTFont {
        let candidates = bold
            ? ["Menlo-Bold", "Monaco", "SFMono-Bold"]
            : ["Menlo-Regular", "Monaco", "SFMono-Regular"]
        for name in candidates {
            let font = CTFontCreateWithName(name as CFString, size, nil)
            // CTFontCreateWithName falls back to Helvetica-ish when missing; verify.
            if (CTFontCopyPostScriptName(font) as String).hasPrefix(String(name.prefix(4))) {
                return font
            }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    static func measure(font: CTFont, fontSize: CGFloat) -> Metrics {
        var glyph = CGGlyph(0)
        var chars: [UniChar] = [77]  // 'M'
        CTFontGetGlyphsForCharacters(font, &chars, &glyph, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        return Metrics(
            fontSize: fontSize,
            cellWidth: max(advance.width, 1),
            cellHeight: max(ceil(ascent + descent + leading), 1),
            ascent: ascent
        )
    }

    /// Cell footprint for an arbitrary size without building a renderer —
    /// metrics scale linearly with point size, so measure once at 100pt.
    public static func cellSize(forFontSize size: CGFloat) -> CGSize {
        struct Cache {
            static let base: Metrics = GlyphRenderer.measure(
                font: GlyphRenderer.bestFont(size: 100, bold: false), fontSize: 100)
        }
        return CGSize(
            width: Cache.base.cellWidth * size / 100,
            height: Cache.base.cellHeight * size / 100
        )
    }

    private func resolveGlyph(_ scalar: Unicode.Scalar, bold: Bool) -> (fontIndex: Int, glyph: CGGlyph) {
        let key = scalar.value
        if bold, let hit = boldGlyphCache[key] { return hit }
        if !bold, let hit = glyphCache[key] { return hit }

        let primaryIndex = bold ? 1 : 0
        var resolved: (Int, CGGlyph)? = nil
        var chars = Array(String(scalar).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        if CTFontGetGlyphsForCharacters(fonts[primaryIndex], &chars, &glyphs, chars.count),
           glyphs[0] != 0 {
            resolved = (primaryIndex, glyphs[0])
        } else {
            // Fallback for glyphs outside the mono font (exotic pasted art).
            let fallback = CTFontCreateForString(fonts[0], String(scalar) as CFString,
                                                 CFRange(location: 0, length: chars.count))
            if CTFontGetGlyphsForCharacters(fallback, &chars, &glyphs, chars.count), glyphs[0] != 0 {
                let name = CTFontCopyPostScriptName(fallback) as String
                var index = fonts.firstIndex { (CTFontCopyPostScriptName($0) as String) == name }
                if index == nil {
                    fonts.append(fallback)
                    index = fonts.count - 1
                }
                resolved = (index!, glyphs[0])
            }
        }

        // Last resort: '?' from the primary font.
        let final: (Int, CGGlyph)
        if let r = resolved {
            final = r
        } else {
            var q: [UniChar] = [63]
            var g = CGGlyph(0)
            CTFontGetGlyphsForCharacters(fonts[primaryIndex], &q, &g, 1)
            final = (primaryIndex, g)
        }
        if bold { boldGlyphCache[key] = final } else { glyphCache[key] = final }
        return final
    }

    /// Quantize a color to a batching key (32 levels per channel — visually lossless
    /// for this content while keeping group count small).
    private static func colorKey(_ c: RGBA) -> UInt32 {
        let r = UInt32(min(max(c.r, 0), 1) * 31)
        let g = UInt32(min(max(c.g, 0), 1) * 31)
        let b = UInt32(min(max(c.b, 0), 1) * 31)
        let a = UInt32(min(max(c.a, 0), 1) * 31)
        return r << 24 | g << 16 | b << 8 | a
    }

    private static func cgColor(_ c: RGBA) -> CGColor {
        CGColor(srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b),
                alpha: CGFloat(c.a))
    }

    /// Draw the canvas centered in `size`. Context uses default (bottom-left) coords.
    public func draw(canvas: GlyphCanvas, background: RGBA, in ctx: CGContext, size: CGSize) {
        ctx.setFillColor(GlyphRenderer.cgColor(background))
        ctx.fill(CGRect(origin: .zero, size: size))

        let cellW = metrics.cellWidth
        let cellH = metrics.cellHeight
        let gridW = CGFloat(canvas.cols) * cellW
        let gridH = CGFloat(canvas.rows) * cellH
        let originX = (size.width - gridW) / 2
        let originTopY = (size.height - gridH) / 2  // margin above grid

        // y of the text baseline for grid row `row` (row 0 = top).
        @inline(__always) func baselineY(_ row: Int) -> CGFloat {
            size.height - originTopY - CGFloat(row) * cellH - metrics.ascent
        }

        groupIndices.removeAll(keepingCapacity: true)
        backgroundIndices.removeAll(keepingCapacity: true)
        var groupCount = 0
        var backgroundCount = 0

        for i in canvas.cells.indices {
            let cell = canvas.cells[i]
            if cell.isBlank { continue }
            let x = i % canvas.cols
            let y = i / canvas.cols

            if let bg = cell.bg, bg.a > 0.01 {
                let rect = CGRect(
                    x: originX + CGFloat(x) * cellW,
                    y: size.height - originTopY - CGFloat(y + 1) * cellH,
                    width: cellW, height: cellH
                )
                let key = GlyphRenderer.colorKey(bg)
                let index: Int
                if let existing = backgroundIndices[key] {
                    index = existing
                } else {
                    index = backgroundCount
                    backgroundCount += 1
                    backgroundIndices[key] = index
                    if index == backgroundGroups.count { backgroundGroups.append(BackgroundGroup()) }
                    backgroundGroups[index].color = bg
                    backgroundGroups[index].rects.removeAll(keepingCapacity: true)
                }
                backgroundGroups[index].rects.append(rect)
            }

            guard cell.scalar != " ", cell.fg.a > 0.01 else { continue }
            let (fontIndex, glyph) = resolveGlyph(cell.scalar, bold: cell.bold)
            guard glyph != 0 else { continue }
            let key = UInt64(fontIndex) << 32 | UInt64(GlyphRenderer.colorKey(cell.fg))
            let index: Int
            if let existing = groupIndices[key] {
                index = existing
            } else {
                index = groupCount
                groupCount += 1
                groupIndices[key] = index
                if index == groups.count { groups.append(Group()) }
                groups[index].fontIndex = fontIndex
                groups[index].color = cell.fg
                groups[index].glyphs.removeAll(keepingCapacity: true)
                groups[index].positions.removeAll(keepingCapacity: true)
            }
            groups[index].glyphs.append(glyph)
            groups[index].positions.append(
                CGPoint(x: originX + CGFloat(x) * cellW, y: baselineY(y))
            )
        }

        for index in 0..<backgroundCount {
            let entry = backgroundGroups[index]
            ctx.setFillColor(GlyphRenderer.cgColor(entry.color))
            ctx.fill(entry.rects)
        }

        ctx.setShouldSmoothFonts(false)  // no subpixel AA — we're on our own dark bg
        ctx.setShouldAntialias(true)
        for index in 0..<groupCount {
            let entry = groups[index]
            ctx.setFillColor(GlyphRenderer.cgColor(entry.color))
            CTFontDrawGlyphs(fonts[entry.fontIndex], entry.glyphs,
                             entry.positions, entry.glyphs.count, ctx)
        }
    }
}
