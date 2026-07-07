import AppKit
import UniformTypeIdentifiers
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
    var themeChips: [String: ThemeChipButton] = [:]
    var effectChecks: [String: NSButton] = [:]
    let cyclePopup = NSPopUpButton()
    let speedSlider = NSSlider(value: 1, minValue: 0.25, maxValue: 4, target: nil, action: nil)
    let speedLabel = NSTextField(labelWithString: "1.00×")
    let fpsPopup = NSPopUpButton()
    let fontPopup = NSPopUpButton()
    let reducedMotionCheck = NSButton(checkboxWithTitle: "Reduce motion", target: nil, action: nil)
    let statuslineCheck = NSButton(checkboxWithTitle: "Show effect · theme label",
                                   target: nil, action: nil)
    let clockCheck = NSButton(checkboxWithTitle: "Show clock & date", target: nil, action: nil)
    let weatherCheck = NSButton(checkboxWithTitle: "Show weather (wttr.in)",
                                target: nil, action: nil)
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
        config.themes = Theme.all.map(\.id).filter { themeChips[$0]?.state == .on }
        config.theme = config.themes.first ?? "omarchy"
        config.enabledEffects = effectChecks
            .compactMap { name, check in check.state == .on ? name : nil }
            .sorted()
        config.cycleMode = cyclePopup.selectedItem?.representedObject as? String ?? "random"
        config.speed = speedSlider.doubleValue
        config.fps = fpsPopup.selectedItem?.representedObject as? Double ?? 60
        config.fontSize = fontPopup.selectedItem?.representedObject as? Double ?? 0
        config.reducedMotion = reducedMotionCheck.state == .on
        config.showStatusline = statuslineCheck.state == .on
        config.showClock = clockCheck.state == .on
        config.showWeather = weatherCheck.state == .on
        return config.sanitized
    }

    func populate(from config: Config) {
        textsView.string = config.artTexts.joined(separator: "\n")
        artView.string = config.customArt
        let activeThemes = config.themes.isEmpty ? [config.theme] : config.themes
        for (id, chip) in themeChips {
            chip.state = activeThemes.contains(id) ? .on : .off
        }
        for (name, check) in effectChecks {
            check.state = config.enabledEffects.contains(name) ? .on : .off
        }
        cyclePopup.selectItem(at: config.cycleMode == "sequential" ? 1 : 0)
        speedSlider.doubleValue = config.speed
        fpsPopup.selectItem(at: StudioController.fpsOptions.firstIndex(of: config.fps) ?? 1)
        fontPopup.selectItem(
            at: StudioController.fontOptions.firstIndex { $0.1 == config.fontSize } ?? 0)
        reducedMotionCheck.state = config.reducedMotion ? .on : .off
        statuslineCheck.state = config.showStatusline ? .on : .off
        clockCheck.state = config.showClock ? .on : .off
        weatherCheck.state = config.showWeather ? .on : .off
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

    // MARK: - Pieces

    private func makeTextWell(_ view: NSTextView, height: CGFloat) -> NSScrollView {
        view.font = StudioStyle.menlo(11.5)
        view.isRichText = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.allowsUndo = true
        view.delegate = self
        view.drawsBackground = true
        view.backgroundColor = StudioStyle.well
        view.textColor = StudioStyle.text
        view.insertionPointColor = StudioStyle.accent
        view.selectedTextAttributes = [
            .backgroundColor: StudioStyle.accent.withAlphaComponent(0.25),
        ]
        view.textContainerInset = NSSize(width: 6, height: 6)
        view.autoresizingMask = [.width]
        view.isVerticallyResizable = true
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                              height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView()
        scroll.documentView = view
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = StudioStyle.well
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 8
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = StudioStyle.hairline.cgColor
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        return scroll
    }

    private func quietButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.contentTintColor = StudioStyle.muted
        button.font = .systemFont(ofSize: 11)
        return button
    }

    private func styledPopup(_ popup: NSPopUpButton) -> NSPopUpButton {
        popup.font = .systemFont(ofSize: 11)
        popup.controlSize = .small
        return popup
    }

    private func header() -> NSView {
        let mark = NSTextField(labelWithString: "")
        let title = NSMutableAttributedString()
        for (i, ch) in ["░", "▒", "▓"].enumerated() {
            title.append(NSAttributedString(string: ch, attributes: [
                .font: StudioStyle.menlo(13),
                .foregroundColor: StudioStyle.accent.withAlphaComponent(0.35 + 0.3 * CGFloat(i)),
            ]))
        }
        title.append(NSAttributedString(string: " GLYPHSAVER", attributes: [
            .font: StudioStyle.menlo(13, bold: true),
            .foregroundColor: StudioStyle.text,
            .kern: 2.5,
        ]))
        title.append(NSAttributedString(string: " STUDIO", attributes: [
            .font: StudioStyle.menlo(13),
            .foregroundColor: StudioStyle.muted,
            .kern: 2.5,
        ]))
        mark.attributedStringValue = title

        let stack = NSStackView(views: [mark])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 14, right: 20)
        return stack
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1320, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "GlyphSaver Studio"
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = StudioStyle.canvas
        window.minSize = NSSize(width: 1080, height: 720)

        previewContainer = NSView()
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.wantsLayer = true
        previewContainer.layer?.backgroundColor = NSColor.black.cgColor

        let nextButton = NSButton(title: "next ⌘E", target: self, action: #selector(nextEffect))
        nextButton.isBordered = false
        nextButton.font = StudioStyle.menlo(10)
        nextButton.contentTintColor = StudioStyle.accent
        nextButton.keyEquivalent = "e"
        nextButton.keyEquivalentModifierMask = .command
        let nextHolder = NSView()
        nextHolder.wantsLayer = true
        nextHolder.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        nextHolder.layer?.cornerRadius = 6
        nextHolder.layer?.borderWidth = 1
        nextHolder.layer?.borderColor = StudioStyle.hairline.cgColor
        nextHolder.translatesAutoresizingMaskIntoConstraints = false
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextHolder.addSubview(nextButton)

        // Sections.
        let textsWell = makeTextWell(textsView, height: 74)
        let artWell = makeTextWell(artView, height: 96)

        var themeRows: [[NSView]] = []
        var themeRow: [NSView] = []
        for theme in Theme.all {
            let chip = ThemeChipButton(theme: theme, target: self, action: #selector(controlChanged))
            themeChips[theme.id] = chip
            themeRow.append(chip)
            if themeRow.count == 3 {
                themeRows.append(themeRow)
                themeRow = []
            }
        }
        if !themeRow.isEmpty { themeRows.append(themeRow) }
        let themesGrid = NSGridView(views: themeRows)
        themesGrid.rowSpacing = 6
        themesGrid.columnSpacing = 6

        var effectRows: [[NSView]] = []
        var effectRow: [NSView] = []
        for name in EffectRegistry.allNames {
            let check = NSButton(checkboxWithTitle: name, target: self,
                                 action: #selector(controlChanged))
            check.font = StudioStyle.menlo(10.5)
            check.contentTintColor = StudioStyle.accent
            effectChecks[name] = check
            effectRow.append(check)
            if effectRow.count == 3 {
                effectRows.append(effectRow)
                effectRow = []
            }
        }
        if !effectRow.isEmpty { effectRows.append(effectRow) }
        let effectsGrid = NSGridView(views: effectRows)
        effectsGrid.rowSpacing = 3
        effectsGrid.columnSpacing = 8

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
        speedSlider.controlSize = .small
        speedSlider.translatesAutoresizingMaskIntoConstraints = false
        speedSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
        speedLabel.font = StudioStyle.menlo(10)
        speedLabel.textColor = StudioStyle.muted

        reducedMotionCheck.target = self
        reducedMotionCheck.action = #selector(controlChanged)
        reducedMotionCheck.font = .systemFont(ofSize: 11)

        func optionLabel(_ text: String) -> NSTextField {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 11)
            label.textColor = StudioStyle.muted
            return label
        }

        let speedRow = NSStackView(views: [speedSlider, speedLabel])
        speedRow.orientation = .horizontal
        let optionsGrid = NSGridView(views: [
            [optionLabel("Cycle"), styledPopup(cyclePopup)],
            [optionLabel("Speed"), speedRow],
            [optionLabel("Frame rate"), styledPopup(fpsPopup)],
            [optionLabel("Font size"), styledPopup(fontPopup)],
            [NSGridCell.emptyContentView, reducedMotionCheck],
            [NSGridCell.emptyContentView, statuslineCheck],
            [NSGridCell.emptyContentView, clockCheck],
            [NSGridCell.emptyContentView, weatherCheck],
        ])
        optionsGrid.rowSpacing = 8
        optionsGrid.columnSpacing = 12
        optionsGrid.column(at: 0).xPlacement = .trailing

        let allButton = quietButton("all", action: #selector(allEffects))
        let noneButton = quietButton("none", action: #selector(noEffects))
        allButton.font = StudioStyle.menlo(10)
        noneButton.font = StudioStyle.menlo(10)
        let effectsHeader = NSStackView(views: [
            StudioStyle.eyebrow("Effects"), NSView(), allButton, noneButton,
        ])
        effectsHeader.orientation = .horizontal
        effectsHeader.distribution = .fill

        let importButton = quietButton("import image…", action: #selector(importImage))
        importButton.font = StudioStyle.menlo(10)
        importButton.contentTintColor = StudioStyle.accent
        let artHeader = NSStackView(views: [
            StudioStyle.eyebrow("Custom art"), NSView(), importButton,
        ])
        artHeader.orientation = .horizontal
        artHeader.distribution = .fill

        let sections = NSStackView(views: [
            StudioStyle.eyebrow("Texts"),
            StudioStyle.hint("One per line, drawn as block letters; entries rotate between "
                + "effects. Also: fractal:mandelbrot, fractal:julia, fractal:sierpinski."),
            textsWell,
            artHeader,
            StudioStyle.hint("Optional ASCII art shown as-is — or import a logo image "
                + "and it becomes block art you can tweak."),
            artWell,
            StudioStyle.eyebrow("Themes"),
            StudioStyle.hint("Check several — the palette rotates between effect cycles."),
            themesGrid,
            effectsHeader,
            effectsGrid,
            StudioStyle.eyebrow("Playback"),
            optionsGrid,
        ])
        sections.orientation = .vertical
        sections.alignment = .leading
        sections.spacing = 8
        sections.setCustomSpacing(16, after: textsWell)
        sections.setCustomSpacing(16, after: artWell)
        sections.setCustomSpacing(16, after: themesGrid)
        sections.setCustomSpacing(16, after: effectsGrid)
        sections.edgeInsets = NSEdgeInsets(top: 4, left: 20, bottom: 16, right: 20)
        sections.translatesAutoresizingMaskIntoConstraints = false
        effectsHeader.widthAnchor.constraint(equalTo: sections.widthAnchor,
                                             constant: -40).isActive = true
        artHeader.widthAnchor.constraint(equalTo: sections.widthAnchor,
                                         constant: -40).isActive = true

        let scroll = NSScrollView()
        let clip = FlippedClipView()
        clip.drawsBackground = false
        scroll.contentView = clip
        scroll.documentView = sections
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        // Footer: the one loud thing in the sidebar.
        let applyButton = NSButton(title: "Apply to Screensaver", target: self,
                                   action: #selector(applyToScreensaver))
        applyButton.keyEquivalent = "s"
        applyButton.keyEquivalentModifierMask = .command
        applyButton.bezelStyle = .rounded
        applyButton.controlSize = .large
        applyButton.bezelColor = StudioStyle.accent
        applyButton.contentTintColor = .black
        applyButton.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = StudioStyle.menlo(10)
        statusLabel.textColor = StudioStyle.muted
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2

        let secondaryRow = NSStackView(views: [
            quietButton("Remove Studio config", action: #selector(removeStudioConfig)),
            NSView(),
            quietButton("Screen Saver Settings…", action: #selector(openScreenSaverSettings)),
        ])
        secondaryRow.orientation = .horizontal

        let footer = NSStackView(views: [applyButton, secondaryRow, statusLabel])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 8
        footer.edgeInsets = NSEdgeInsets(top: 14, left: 20, bottom: 16, right: 20)
        footer.translatesAutoresizingMaskIntoConstraints = false

        let sidebar = NSView()
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = StudioStyle.canvas.cgColor
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let headerView = header()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        let headerLine = StudioStyle.hairlineView()
        let footerLine = StudioStyle.hairlineView()
        sidebar.addSubview(headerView)
        sidebar.addSubview(headerLine)
        sidebar.addSubview(scroll)
        sidebar.addSubview(footerLine)
        sidebar.addSubview(footer)

        let root = window.contentView!
        root.addSubview(previewContainer)
        root.addSubview(sidebar)
        previewContainer.addSubview(nextHolder)

        NSLayoutConstraint.activate([
            // Required floor so autolayout can never collapse the window.
            previewContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 640),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 380),

            previewContainer.topAnchor.constraint(equalTo: root.topAnchor),
            previewContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            previewContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 420),
            previewContainer.trailingAnchor.constraint(equalTo: sidebar.leadingAnchor),

            headerView.topAnchor.constraint(equalTo: sidebar.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            headerLine.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            headerLine.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            headerLine.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: headerLine.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            footerLine.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            footerLine.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            footerLine.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            footer.topAnchor.constraint(equalTo: footerLine.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            sections.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            applyButton.widthAnchor.constraint(equalTo: footer.widthAnchor, constant: -40),
            secondaryRow.widthAnchor.constraint(equalTo: footer.widthAnchor, constant: -40),

            nextHolder.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -14),
            nextHolder.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: -14),
            nextButton.topAnchor.constraint(equalTo: nextHolder.topAnchor, constant: 4),
            nextButton.bottomAnchor.constraint(equalTo: nextHolder.bottomAnchor, constant: -4),
            nextButton.leadingAnchor.constraint(equalTo: nextHolder.leadingAnchor, constant: 9),
            nextButton.trailingAnchor.constraint(equalTo: nextHolder.trailingAnchor, constant: -9),
        ])
        window.setContentSize(NSSize(width: 1320, height: 860))
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
        previewContainer.addSubview(view, positioned: .below, relativeTo: nil)
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

    @objc func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .bmp, .webP, .heic]
        panel.message = "Choose a logo or image to convert to block art"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            guard let image = NSImage(contentsOf: url),
                  let ascii = ImageToAscii.convert(image: image, targetWidth: 64) else {
                self.status("Could not read \(url.lastPathComponent) as an image.")
                return
            }
            self.artView.string = ascii
            self.scheduleApply()
            self.status("Converted \(url.lastPathComponent) — tweak the art or apply.")
        }
    }

    @objc func applyToScreensaver() {
        do {
            try ConfigStore.saveToFile(currentConfig())
            status("Applied — takes effect next time the screensaver starts.")
        } catch {
            status("Could not save: \(error.localizedDescription)")
        }
    }

    @objc func removeStudioConfig() {
        do {
            if ConfigStore.configFileExists {
                try FileManager.default.removeItem(at: ConfigStore.configFileURL)
            }
            status("Removed — the saver now uses its own Options sheet settings.")
        } catch {
            status("Could not remove: \(error.localizedDescription)")
        }
    }

    @objc func openScreenSaverSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    func status(_ text: String) {
        statusLabel.stringValue = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
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
