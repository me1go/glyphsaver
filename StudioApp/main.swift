import AppKit
import GlyphSaverCore
import GlyphSaverKit

// GlyphSaver Studio — configure the screensaver with a live preview.
// Writes ~/Library/Application Support/GlyphSaver/config.json, which the
// sandboxed saver reads at every activation (config.json wins over the
// in-saver options sheet).

final class StudioController: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    var window: NSWindow!
    var previewContainer: NSView!
    var preview: GlyphSaverContentView?

    let textsView = NSTextView()
    let artView = NSTextView()
    let themePopup = NSPopUpButton()
    var effectChecks: [String: NSButton] = [:]
    let cyclePopup = NSPopUpButton()
    let speedSlider = NSSlider(value: 1, minValue: 0.25, maxValue: 4, target: nil, action: nil)
    let speedLabel = NSTextField(labelWithString: "1.00×")
    let fpsPopup = NSPopUpButton()
    let fontPopup = NSPopUpButton()
    let reducedMotionCheck = NSButton(checkboxWithTitle: "Reduce motion", target: nil, action: nil)
    let statusLabel = NSTextField(labelWithString: " ")

    var applyDebounce: Timer?

    static let fpsOptions: [Double] = [30, 60, 120]
    static let fontOptions: [(String, Double)] = [
        ("Auto-fit", 0), ("10 pt", 10), ("12 pt", 12), ("14 pt", 14),
        ("18 pt", 18), ("24 pt", 24), ("32 pt", 32),
    ]

    // MARK: - Config <-> UI

    func currentConfig() -> Config {
        var config = Config.default
        config.artTexts = textsView.string
            .split(separator: "\n").map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        config.customArt = artView.string
        config.theme = themePopup.selectedItem?.representedObject as? String ?? "omarchy"
        config.enabledEffects = effectChecks
            .compactMap { name, check in check.state == .on ? name : nil }
            .sorted()
        config.cycleMode = cyclePopup.selectedItem?.representedObject as? String ?? "random"
        config.speed = speedSlider.doubleValue
        config.fps = fpsPopup.selectedItem?.representedObject as? Double ?? 60
        config.fontSize = fontPopup.selectedItem?.representedObject as? Double ?? 0
        config.reducedMotion = reducedMotionCheck.state == .on
        return config.sanitized
    }

    func populate(from config: Config) {
        textsView.string = config.artTexts.joined(separator: "\n")
        artView.string = config.customArt
        themePopup.selectItem(at: Theme.all.firstIndex { $0.id == config.theme } ?? 0)
        for (name, check) in effectChecks {
            check.state = config.enabledEffects.contains(name) ? .on : .off
        }
        cyclePopup.selectItem(at: config.cycleMode == "sequential" ? 1 : 0)
        speedSlider.doubleValue = config.speed
        fpsPopup.selectItem(at: StudioController.fpsOptions.firstIndex(of: config.fps) ?? 1)
        fontPopup.selectItem(
            at: StudioController.fontOptions.firstIndex { $0.1 == config.fontSize } ?? 0)
        reducedMotionCheck.state = config.reducedMotion ? .on : .off
        speedChanged()
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()
        populate(from: ConfigStore.loadPreferred(defaults: nil))
        rebuildPreview()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About GlyphSaver Studio",
                                   action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                                   keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit GlyphSaver Studio",
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q"))
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All",
                                    action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        NSApp.mainMenu = mainMenu
    }

    private func makeTextArea(_ view: NSTextView, height: CGFloat) -> NSScrollView {
        view.font = NSFont(name: "Menlo", size: 11)
            ?? .monospacedSystemFont(ofSize: 11, weight: .regular)
        view.isRichText = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.allowsUndo = true
        view.delegate = self
        view.autoresizingMask = [.width]
        view.isVerticallyResizable = true
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                              height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView()
        scroll.documentView = view
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        return scroll
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 12, weight: .semibold)
        return l
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "GlyphSaver Studio"
        window.minSize = NSSize(width: 1000, height: 700)

        previewContainer = NSView()
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.wantsLayer = true
        previewContainer.layer?.backgroundColor = NSColor.black.cgColor

        // Controls column.
        for theme in Theme.all {
            themePopup.addItem(withTitle: theme.displayName)
            themePopup.lastItem?.representedObject = theme.id
        }
        themePopup.target = self
        themePopup.action = #selector(controlChanged)

        cyclePopup.addItem(withTitle: "Random order")
        cyclePopup.lastItem?.representedObject = "random"
        cyclePopup.addItem(withTitle: "Sequential order")
        cyclePopup.lastItem?.representedObject = "sequential"
        cyclePopup.target = self
        cyclePopup.action = #selector(controlChanged)

        for fps in StudioController.fpsOptions {
            fpsPopup.addItem(withTitle: "\(Int(fps)) fps")
            fpsPopup.lastItem?.representedObject = fps
        }
        fpsPopup.target = self
        fpsPopup.action = #selector(controlChanged)

        for (title, size) in StudioController.fontOptions {
            fontPopup.addItem(withTitle: title)
            fontPopup.lastItem?.representedObject = size
        }
        fontPopup.target = self
        fontPopup.action = #selector(controlChanged)

        speedSlider.target = self
        speedSlider.action = #selector(speedMoved)
        speedSlider.translatesAutoresizingMaskIntoConstraints = false
        speedSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        reducedMotionCheck.target = self
        reducedMotionCheck.action = #selector(controlChanged)

        var effectRows: [[NSView]] = []
        var row: [NSView] = []
        for name in EffectRegistry.allNames {
            let check = NSButton(checkboxWithTitle: name, target: self,
                                 action: #selector(controlChanged))
            check.font = .systemFont(ofSize: 11)
            effectChecks[name] = check
            row.append(check)
            if row.count == 3 {
                effectRows.append(row)
                row = []
            }
        }
        if !row.isEmpty { effectRows.append(row) }
        let effectsGrid = NSGridView(views: effectRows)
        effectsGrid.rowSpacing = 2
        effectsGrid.columnSpacing = 6

        let allButton = NSButton(title: "All", target: self, action: #selector(allEffects))
        let noneButton = NSButton(title: "None", target: self, action: #selector(noEffects))
        allButton.controlSize = .small
        noneButton.controlSize = .small
        let effectButtons = NSStackView(views: [allButton, noneButton])
        effectButtons.orientation = .horizontal

        let textsScroll = makeTextArea(textsView, height: 66)
        let artScroll = makeTextArea(artView, height: 100)

        let textsHint = NSTextField(wrappingLabelWithString:
            "One per line — each renders as big block letters; entries rotate between effects. "
            + "Special: fractal:mandelbrot, fractal:julia, fractal:sierpinski.")
        textsHint.font = .systemFont(ofSize: 10)
        textsHint.textColor = .secondaryLabelColor
        let artHint = NSTextField(wrappingLabelWithString:
            "Optional ASCII art shown as-is (paste FIGlet output, box art, …).")
        artHint.font = .systemFont(ofSize: 10)
        artHint.textColor = .secondaryLabelColor

        let speedRow = NSStackView(views: [speedSlider, speedLabel])
        speedRow.orientation = .horizontal

        let settingsGrid = NSGridView(views: [
            [sectionLabel("Theme"), themePopup],
            [sectionLabel("Cycle"), cyclePopup],
            [sectionLabel("Speed"), speedRow],
            [sectionLabel("Frame rate"), fpsPopup],
            [sectionLabel("Font size"), fontPopup],
            [NSGridCell.emptyContentView, reducedMotionCheck],
        ])
        settingsGrid.rowSpacing = 6
        settingsGrid.column(at: 0).xPlacement = .trailing

        let applyButton = NSButton(title: "Apply to Screensaver",
                                   target: self, action: #selector(applyToScreensaver))
        applyButton.keyEquivalent = "s"
        applyButton.keyEquivalentModifierMask = .command
        applyButton.bezelColor = .controlAccentColor
        let removeButton = NSButton(title: "Remove Studio Config",
                                    target: self, action: #selector(removeStudioConfig))
        let settingsButton = NSButton(title: "Open Screen Saver Settings…",
                                      target: self, action: #selector(openScreenSaverSettings))
        let nextButton = NSButton(title: "Next Effect (preview)",
                                  target: self, action: #selector(nextEffect))

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        let controls = NSStackView(views: [
            sectionLabel("Texts"), textsHint, textsScroll,
            sectionLabel("Custom art"), artHint, artScroll,
            settingsGrid,
            sectionLabel("Effects"), effectButtons, effectsGrid,
            nextButton,
            NSBox(), // separator
            applyButton, removeButton, settingsButton, statusLabel,
        ])
        controls.orientation = .vertical
        controls.alignment = .leading
        controls.spacing = 8
        controls.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        controls.translatesAutoresizingMaskIntoConstraints = false

        let controlsScroll = NSScrollView()
        let flipped = FlippedClipView()
        controlsScroll.contentView = flipped
        controlsScroll.documentView = controls
        controlsScroll.hasVerticalScroller = true
        controlsScroll.drawsBackground = false
        controlsScroll.translatesAutoresizingMaskIntoConstraints = false

        let root = window.contentView!
        root.addSubview(previewContainer)
        root.addSubview(controlsScroll)
        NSLayoutConstraint.activate([
            previewContainer.topAnchor.constraint(equalTo: root.topAnchor),
            previewContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            previewContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            controlsScroll.topAnchor.constraint(equalTo: root.topAnchor),
            controlsScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            controlsScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            controlsScroll.widthAnchor.constraint(equalToConstant: 400),
            previewContainer.trailingAnchor.constraint(equalTo: controlsScroll.leadingAnchor),
            controls.widthAnchor.constraint(equalTo: controlsScroll.widthAnchor),
        ])
        window.center()
    }

    // MARK: - Live preview

    func rebuildPreview() {
        preview?.stopDriving()
        preview?.removeFromSuperview()
        let view = GlyphSaverContentView(
            frame: previewContainer.bounds,
            config: currentConfig(),
            seed: UInt64.random(in: 0...UInt64.max)
        )
        view.autoresizingMask = [.width, .height]
        previewContainer.addSubview(view)
        preview = view
        view.startDriving()
    }

    func scheduleApply() {
        applyDebounce?.invalidate()
        applyDebounce = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.rebuildPreview()
        }
    }

    // MARK: - Actions

    @objc func controlChanged() {
        scheduleApply()
    }

    @objc func speedMoved() {
        speedChanged()
        scheduleApply()
    }

    func speedChanged() {
        speedLabel.stringValue = String(format: "%.2f×", speedSlider.doubleValue)
    }

    func textDidChange(_ notification: Notification) {
        scheduleApply()
    }

    @objc func allEffects() {
        effectChecks.values.forEach { $0.state = .on }
        scheduleApply()
    }

    @objc func noEffects() {
        effectChecks.values.forEach { $0.state = .off }
        scheduleApply()
    }

    @objc func nextEffect() {
        preview?.skipToNextEffect()
    }

    @objc func applyToScreensaver() {
        do {
            try ConfigStore.saveToFile(currentConfig())
            status("Saved — the screensaver picks this up next time it starts.")
        } catch {
            status("Save failed: \(error.localizedDescription)")
        }
    }

    @objc func removeStudioConfig() {
        do {
            if ConfigStore.configFileExists {
                try FileManager.default.removeItem(at: ConfigStore.configFileURL)
            }
            status("Removed — the saver now uses its own Options sheet settings.")
        } catch {
            status("Remove failed: \(error.localizedDescription)")
        }
    }

    @objc func openScreenSaverSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    func status(_ text: String) {
        statusLabel.stringValue = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.statusLabel.stringValue == text {
                self?.statusLabel.stringValue = " "
            }
        }
    }
}

/// Keeps the controls stack pinned to the top of its scroll view.
final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let controller = StudioController()
app.delegate = controller
app.run()
