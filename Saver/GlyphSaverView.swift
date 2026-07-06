import ScreenSaver
import GlyphSaverCore
import GlyphSaverKit

/// Principal class of the .saver bundle. Thin shell: all rendering lives in
/// GlyphSaverKit so the preview app exercises identical code.
///
/// The @objc name is pinned because Info.plist's NSPrincipalClass must match
/// the Objective-C runtime name exactly (no Swift module prefix).
@objc(GlyphSaverView)
public final class GlyphSaverView: ScreenSaverView {
    private var contentView: GlyphSaverContentView?
    private var sheet: ConfigSheet?

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        animationTimeInterval = 1.0 / 60.0
        // Since Sonoma the engine never calls stopAnimation for the real run and
        // keeps instances animating invisibly. The willstop broadcast is the only
        // reliable teardown signal (ScreenSaverMinimal's documented workaround).
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(willStop(_:)),
            name: Notification.Name("com.apple.screensaver.willstop"),
            object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    static var moduleDefaults: ScreenSaverDefaults? {
        let bundleId = Bundle(for: GlyphSaverView.self).bundleIdentifier
            ?? "com.melgeorge.glyphsaver"
        return ScreenSaverDefaults(forModuleWithName: bundleId)
    }

    /// isPreview lies on several macOS releases (Sonoma/Tahoe); the frame-size
    /// heuristic is the community-standard fallback.
    private var looksLikePreview: Bool {
        isPreview || bounds.width < 700
    }

    public override func startAnimation() {
        super.startAnimation()

        // Tahoe can hand us 0x0 bounds; adopt the main screen's size once.
        if bounds.width < 1 || bounds.height < 1, let screen = NSScreen.main {
            setFrameSize(screen.frame.size)
        }

        // Studio-written config.json wins over the in-saver sheet's defaults.
        let config = ConfigStore.loadPreferred(defaults: Self.moduleDefaults)
        let content = GlyphSaverContentView(
            frame: bounds,
            config: config,
            seed: UInt64.random(in: 0...UInt64.max)  // each screen animates differently
        )
        content.autoresizingMask = [.width, .height]
        addSubview(content)
        contentView = content
        content.startDriving()
    }

    public override func stopAnimation() {
        super.stopAnimation()
        teardown()
    }

    // Driving happens on our own timer (animateOneFrame cadence is unreliable
    // across modern macOS); nothing to do here.
    public override func animateOneFrame() {}

    private func teardown() {
        contentView?.stopDriving()
        contentView?.removeFromSuperview()
        contentView = nil
    }

    @objc private func willStop(_ notification: Notification) {
        teardown()
        // Without this, Sonoma+ leaves the saver process running (and stacking
        // instances) behind the desktop forever. Never exit the System Settings
        // preview host.
        if !looksLikePreview {
            exit(0)
        }
    }

    // MARK: - Configuration

    public override var hasConfigureSheet: Bool { true }

    public override var configureSheet: NSWindow? {
        // Keep a strong reference: the framework does not retain the sheet.
        let sheet = ConfigSheet(defaults: Self.moduleDefaults)
        self.sheet = sheet
        return sheet.window
    }
}
