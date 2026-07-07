import AppKit
import GlyphSaverCore

/// Converts a logo/image into block ASCII art. Designed for flat-color logos:
/// the background color is detected from the image border (or transparency),
/// everything else is foreground. Each text row samples two pixel rows, so
/// half blocks (▀ ▄) double the vertical resolution — the Omarchy
/// transcode-ascii look.
public enum ImageToAscii {
    public static func convert(image: NSImage, targetWidth: Int = 64) -> String? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.width > 0, cg.height > 0 else { return nil }

        let cols = min(max(targetWidth, 16), 200)
        // Terminal cells are ~2x taller than wide; two samples per cell row.
        let rows = max(Int((Double(cols) * Double(cg.height) / Double(cg.width) * 0.5)
                           .rounded()), 1)
        let sampleH = rows * 2

        guard let ctx = CGContext(
            data: nil, width: cols, height: sampleH,
            bitsPerComponent: 8, bytesPerRow: cols * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cols, height: sampleH))
        guard let buf = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        // (x, y) with y = 0 at the top — bitmap memory row 0 is the top scanline.
        func pixel(_ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double, a: Double) {
            let i = (y * cols + x) * 4
            let a = Double(buf[i + 3]) / 255
            guard a > 0.001 else { return (0, 0, 0, 0) }
            // Un-premultiply so flat colors compare cleanly.
            return (Double(buf[i]) / 255 / a, Double(buf[i + 1]) / 255 / a,
                    Double(buf[i + 2]) / 255 / a, a)
        }

        // Background = the most common border color (mode, not mean — a mean of
        // a bicolor border matches nothing). Mostly-transparent border means
        // the alpha channel is the mask.
        var borderPixels: [(r: Double, g: Double, b: Double)] = []
        var transparentCount = 0
        var buckets: [UInt32: Int] = [:]
        func sampleBorder(_ x: Int, _ y: Int) {
            let p = pixel(x, y)
            if p.a <= 0.5 {
                transparentCount += 1
                return
            }
            borderPixels.append((p.r, p.g, p.b))
            let key = UInt32(p.r * 15) << 8 | UInt32(p.g * 15) << 4 | UInt32(p.b * 15)
            buckets[key, default: 0] += 1
        }
        for x in 0..<cols {
            sampleBorder(x, 0)
            sampleBorder(x, sampleH - 1)
        }
        for y in 0..<sampleH {
            sampleBorder(0, y)
            sampleBorder(cols - 1, y)
        }
        let totalBorder = borderPixels.count + transparentCount
        let transparentBackground = Double(transparentCount) / Double(max(totalBorder, 1)) > 0.5
        let modeKey = buckets.max { $0.value < $1.value }?.key ?? 0
        let modePixels = borderPixels.filter {
            (UInt32($0.r * 15) << 8 | UInt32($0.g * 15) << 4 | UInt32($0.b * 15)) == modeKey
        }
        let bg = modePixels.isEmpty
            ? (r: 0.0, g: 0.0, b: 0.0)
            : (r: modePixels.map(\.r).reduce(0, +) / Double(modePixels.count),
               g: modePixels.map(\.g).reduce(0, +) / Double(modePixels.count),
               b: modePixels.map(\.b).reduce(0, +) / Double(modePixels.count))

        func isForeground(_ x: Int, _ y: Int) -> Bool {
            let p = pixel(x, y)
            if p.a < 0.5 { return false }
            if transparentBackground { return true }
            let dr = p.r - bg.r, dg = p.g - bg.g, db = p.b - bg.b
            return (dr * dr + dg * dg + db * db).squareRoot() > 0.22
        }

        var lines = [String]()
        for row in 0..<rows {
            var line = ""
            for x in 0..<cols {
                let top = isForeground(x, row * 2)
                let bottom = isForeground(x, row * 2 + 1)
                switch (top, bottom) {
                case (true, true): line.append("█")
                case (true, false): line.append("▀")
                case (false, true): line.append("▄")
                case (false, false): line.append(" ")
                }
            }
            lines.append(line)
        }

        // Strip the uniform left margin so the art centers true.
        let margins = lines.compactMap { line -> Int? in
            let trimmed = line.drop { $0 == " " }
            return trimmed.isEmpty ? nil : line.count - trimmed.count
        }
        if let margin = margins.min(), margin > 0 {
            lines = lines.map { String($0.dropFirst(min(margin, $0.count))) }
        }

        let text = lines.joined(separator: "\n")
        let art = AsciiArt(text: text)
        guard art.placedCells(cols: 10_000, rows: 10_000).count > 3 else { return nil }
        return text
    }
}
