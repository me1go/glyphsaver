/// One terminal cell. `bg == nil` means the canvas background shows through.
public struct GlyphCell: Equatable {
    public var scalar: Unicode.Scalar
    public var fg: RGBA
    public var bg: RGBA?
    public var bold: Bool

    public init(_ scalar: Unicode.Scalar, fg: RGBA, bg: RGBA? = nil, bold: Bool = false) {
        self.scalar = scalar
        self.fg = fg
        self.bg = bg
        self.bold = bold
    }

    public static let blank = GlyphCell(" ", fg: .clear)

    public var isBlank: Bool {
        scalar == " " && bg == nil
    }
}

/// A cols×rows grid of glyph cells. Writes outside the grid are clipped, like any raster target.
public struct GlyphCanvas {
    public let cols: Int
    public let rows: Int
    public private(set) var cells: [GlyphCell]

    public init(cols: Int, rows: Int) {
        // A zero-sized canvas can arrive from degenerate view bounds (macOS Tahoe 0x0 bug);
        // a 1x1 grid keeps every downstream index computation valid.
        self.cols = max(cols, 1)
        self.rows = max(rows, 1)
        self.cells = Array(repeating: .blank, count: self.cols * self.rows)
    }

    public mutating func clear() {
        for i in cells.indices { cells[i] = .blank }
    }

    @inlinable
    public func contains(x: Int, y: Int) -> Bool {
        x >= 0 && x < cols && y >= 0 && y < rows
    }

    public mutating func put(_ cell: GlyphCell, x: Int, y: Int) {
        guard contains(x: x, y: y) else { return }
        cells[y * cols + x] = cell
    }

    public func at(x: Int, y: Int) -> GlyphCell? {
        guard contains(x: x, y: y) else { return nil }
        return cells[y * cols + x]
    }

    /// Blend every visible cell's colors toward `color` — used for effect fade-outs.
    public mutating func fadeAll(toward color: RGBA, t: Float) {
        guard t > 0 else { return }
        for i in cells.indices where !cells[i].isBlank {
            cells[i].fg = RGBA.lerp(cells[i].fg, color, t)
            if let bg = cells[i].bg {
                cells[i].bg = RGBA.lerp(bg, color, t)
            }
        }
    }
}
