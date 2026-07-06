import Foundation

/// One non-space glyph of the art, in absolute canvas coordinates.
public struct ArtCell: Equatable {
    public let x: Int
    public let y: Int
    public let scalar: Unicode.Scalar

    public init(x: Int, y: Int, scalar: Unicode.Scalar) {
        self.x = x
        self.y = y
        self.scalar = scalar
    }
}

/// Parsed multi-line ASCII/block art with centered placement.
public struct AsciiArt: Equatable {
    public let lines: [[Unicode.Scalar]]
    public let width: Int
    public let height: Int

    public init(text: String) {
        var parsed: [[Unicode.Scalar]] = []
        let expanded = text.replacingOccurrences(of: "\t", with: "  ")
        for raw in expanded.split(separator: "\n", omittingEmptySubsequences: false) {
            var scalars = Array(raw.unicodeScalars)
            while scalars.last == " " || scalars.last == "\r" {
                scalars.removeLast()
            }
            parsed.append(scalars)
        }
        while parsed.first?.isEmpty == true { parsed.removeFirst() }
        while parsed.last?.isEmpty == true { parsed.removeLast() }
        if parsed.isEmpty { parsed = [Array("?".unicodeScalars)] }

        self.lines = parsed
        self.width = parsed.map(\.count).max() ?? 1
        self.height = parsed.count
    }

    /// Top-left placement that centers the art on a canvas. Oversized art gets a
    /// negative origin so its center stays on the canvas center (edges crop).
    public func origin(cols: Int, rows: Int) -> (x: Int, y: Int) {
        ((cols - width) / 2, (rows - height) / 2)
    }

    /// Non-space glyphs placed centered on the canvas; off-canvas glyphs are cropped.
    public func placedCells(cols: Int, rows: Int) -> [ArtCell] {
        let o = origin(cols: cols, rows: rows)
        var out: [ArtCell] = []
        out.reserveCapacity(width * height / 2)
        for (dy, line) in lines.enumerated() {
            let y = o.y + dy
            guard y >= 0 && y < rows else { continue }
            for (dx, scalar) in line.enumerated() where scalar != " " {
                let x = o.x + dx
                guard x >= 0 && x < cols else { continue }
                out.append(ArtCell(x: x, y: y, scalar: scalar))
            }
        }
        return out
    }
}
