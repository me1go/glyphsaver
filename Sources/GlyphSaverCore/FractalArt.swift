import Foundation

/// Generates fractals as ASCII/block art. Reached from config texts with the
/// `fractal:` prefix — e.g. "fractal:mandelbrot", "fractal:julia",
/// "fractal:sierpinski" — so every reveal effect can operate on them.
public enum FractalArt {
    public static let names = ["mandelbrot", "julia", "sierpinski"]

    /// Returns art for a "fractal:<name>" spec, nil if the spec isn't one.
    public static func render(_ spec: String) -> AsciiArt? {
        let trimmed = spec.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.hasPrefix("fractal:") else { return nil }
        switch String(trimmed.dropFirst("fractal:".count)) {
        case "mandelbrot": return AsciiArt(text: mandelbrot())
        case "julia": return AsciiArt(text: julia())
        case "sierpinski": return AsciiArt(text: sierpinski())
        default: return AsciiArt(text: mandelbrot())
        }
    }

    /// Escape-time density ramp, sparse → solid.
    static let density = Array(" .,:;~=+*#%@▒▓█".unicodeScalars)

    static func escapeChar(cr: Double, ci: Double, maxIter: Int) -> Unicode.Scalar {
        var zr = 0.0, zi = 0.0
        var iter = 0
        while iter < maxIter && zr * zr + zi * zi < 4 {
            let t = zr * zr - zi * zi + cr
            zi = 2 * zr * zi + ci
            zr = t
            iter += 1
        }
        if iter >= maxIter { return "█" }
        // Skip index 0 (space) only for points that showed some activity.
        let idx = Int(Double(iter) / Double(maxIter) * Double(density.count - 2))
        return density[min(idx, density.count - 2)]
    }

    /// Classic Mandelbrot bug. Terminal cells are ~2x taller than wide, so the
    /// imaginary step is doubled to keep the set round.
    static func mandelbrot(width: Int = 130, height: Int = 46) -> String {
        var rows: [String] = []
        for y in 0..<height {
            var row = ""
            for x in 0..<width {
                let cr = -2.1 + Double(x) / Double(width - 1) * 2.7
                let ci = -1.25 + Double(y) / Double(height - 1) * 2.5
                let scalar = escapeChar(cr: cr, ci: ci, maxIter: 48)
                row.unicodeScalars.append(scalar)
            }
            rows.append(row)
        }
        return rows.joined(separator: "\n")
    }

    /// A dendrite-y Julia set (c = -0.7269 + 0.1889i).
    static func julia(width: Int = 130, height: Int = 46) -> String {
        var rows: [String] = []
        for y in 0..<height {
            var row = ""
            for x in 0..<width {
                var zr = -1.6 + Double(x) / Double(width - 1) * 3.2
                var zi = -1.3 + Double(y) / Double(height - 1) * 2.6
                var iter = 0
                while iter < 48 && zr * zr + zi * zi < 4 {
                    let t = zr * zr - zi * zi - 0.7269
                    zi = 2 * zr * zi + 0.1889
                    zr = t
                    iter += 1
                }
                if iter >= 48 {
                    row.unicodeScalars.append("█")
                } else {
                    let idx = Int(Double(iter) / 48 * Double(density.count - 2))
                    row.unicodeScalars.append(density[min(idx, density.count - 2)])
                }
            }
            rows.append(row)
        }
        return rows.joined(separator: "\n")
    }

    /// Sierpinski triangle via the (x & y) bit trick; cells doubled so the
    /// triangle stays equilateral-ish at terminal cell aspect.
    static func sierpinski(order: Int = 5) -> String {
        let n = 1 << order  // 32 rows
        var rows: [String] = []
        for r in 0..<n {
            var row = String(repeating: " ", count: n - r - 1)
            for c in 0...r {
                row += (r & c) == c ? "█ " : "  "
            }
            rows.append(row)
        }
        return rows.joined(separator: "\n")
    }
}
