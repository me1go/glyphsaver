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
    }
}
