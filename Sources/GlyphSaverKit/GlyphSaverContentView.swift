import AppKit
import GlyphSaverCore

/// Renders the animation. Shared by the .saver and the preview app so both
/// exercise identical code. Drive it by calling `startDriving`/`stopDriving`
/// (owns a timer) or by calling `tick()` from an external display link.
public final class GlyphSaverContentView: NSView {
    private let config: Config
    private let seed: UInt64
    private var controller: AnimationController?
    private var renderer: GlyphRenderer?
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0

    private struct Chip {
        let text: NSAttributedString
        let size: CGSize

        init(_ text: NSAttributedString) {
            self.text = text
            self.size = text.size()
        }
    }

    private var statusKey = ""
    private var statusChip: Chip?
    private var clockSecond: Double?
    private var clockWeather: String?
    private var clockChip: Chip?

    public init(frame: NSRect, config: Config, seed: UInt64) {
        self.config = config.sanitized
        self.seed = seed
        super.init(frame: frame)
        rebuildGrid()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("not used")
    }

    public override var isOpaque: Bool { true }

    // MARK: - Grid sizing

    /// Pick a font size that fits the art comfortably on screen (about 60% of
    /// the smaller dimension), clamped to a readable range. Explicit config
    /// font size wins. Also used by the headless snapshot/bench paths so they
    /// exercise the same sizing as the live view.
    public static func fittedFontSize(for size: CGSize, config: Config) -> CGFloat {
        if config.fontSize > 0 { return CGFloat(config.fontSize) }
        let art = config.resolvedArt
        let unit = GlyphRenderer.cellSize(forFontSize: 100)
        // Font size at which the art would exactly span the view.
        let fitW = size.width / (CGFloat(art.width) * unit.width / 100)
        let fitH = size.height / (CGFloat(art.height) * unit.height / 100)
        let target = 0.62 * min(fitW, fitH)
        return min(max(target, 7), 26)
    }

    private func rebuildGrid() {
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }
        let fontSize = GlyphSaverContentView.fittedFontSize(for: size, config: config)
        if renderer == nil || abs(renderer!.metrics.fontSize - fontSize) > 0.5 {
            renderer = GlyphRenderer(fontSize: fontSize)
        }
        guard let renderer else { return }
        let cols = max(Int(size.width / renderer.metrics.cellWidth), 1)
        let rows = max(Int(size.height / renderer.metrics.cellHeight), 1)
        if let controller {
            controller.resize(cols: cols, rows: rows)
        } else {
            controller = AnimationController(cols: cols, rows: rows, config: config, seed: seed)
        }
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        rebuildGrid()
    }

    // MARK: - Animation driving

    public func startDriving() {
        stopDriving()
        lastTick = CACurrentMediaTime()
        let interval = 1.0 / config.fps
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stopDriving() {
        timer?.invalidate()
        timer = nil
    }

    /// Advance by wall-clock delta and repaint.
    public func tick() {
        let now = CACurrentMediaTime()
        let dt = lastTick == 0 ? 1.0 / config.fps : now - lastTick
        lastTick = now
        controller?.step(dt: dt)
        needsDisplay = true
    }

    public func skipToNextEffect() {
        controller?.skipToNext()
    }

    public var currentEffectName: String {
        controller?.currentEffect?.name ?? "-"
    }

    public var currentThemeId: String {
        controller?.currentThemeId ?? "-"
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        guard let controller, let renderer else {
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(bounds)
            return
        }
        renderer.draw(canvas: controller.canvas, background: controller.background,
                      in: ctx, size: bounds.size)
        guard bounds.width >= 500 else { return }  // skip in tiny previews
        if config.showStatusline {
            let key = "\(controller.currentEffect?.name ?? "-") · " + controller.currentThemeId
            if statusChip == nil || statusKey != key {
                statusKey = key
                statusChip = Chip(makeMono(key, size: 12))
            }
            if let statusChip { drawChip(statusChip, corner: .left) }
        }
        if config.showClock {
            if config.showWeather {
                WeatherProvider.shared.refreshIfStale()
            }
            let now = Date()
            let second = now.timeIntervalSinceReferenceDate.rounded(.down)
            let weather = config.showWeather ? WeatherProvider.shared.summary : nil
            if clockChip == nil || clockSecond != second || clockWeather != weather {
                clockSecond = second
                clockWeather = weather
                clockChip = Chip(clockString(at: now, weather: weather))
            }
            if let clockChip { drawChip(clockChip, corner: .right) }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short   // honors the user's 12/24-hour setting
        f.dateStyle = .none
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f
    }()

    private func makeMono(_ text: String, size: CGFloat,
                          alpha: CGFloat = 0.62) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont(name: "Menlo", size: size)
                ?? .monospacedSystemFont(ofSize: size, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        ])
    }

    /// "⛅️ 23°C · 14:32 · Tue 8 Jul" with the time slightly louder.
    private func clockString(at now: Date, weather: String?) -> NSAttributedString {
        let out = NSMutableAttributedString()
        if let weather {
            out.append(makeMono("\(weather) · ", size: 12))
        }
        out.append(makeMono(GlyphSaverContentView.timeFormatter.string(from: now),
                            size: 14, alpha: 0.85))
        out.append(makeMono(" · " + GlyphSaverContentView.dateFormatter.string(from: now),
                            size: 12))
        return out
    }

    private enum ChipCorner { case left, right }

    /// Terminal-statusbar chip pinned to a bottom corner.
    private func drawChip(_ content: Chip, corner: ChipCorner) {
        let size = content.size
        let pad = CGSize(width: 10, height: 5)
        let width = size.width + pad.width * 2
        let x = corner == .left ? 18 : bounds.width - 18 - width
        let chip = NSRect(x: x, y: 16, width: width, height: size.height + pad.height * 2)
        let path = NSBezierPath(roundedRect: chip, xRadius: 7, yRadius: 7)
        NSColor.black.withAlphaComponent(0.45).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.09).setStroke()
        path.lineWidth = 1
        path.stroke()
        content.text.draw(at: NSPoint(x: chip.minX + pad.width, y: chip.minY + pad.height))
    }
}
