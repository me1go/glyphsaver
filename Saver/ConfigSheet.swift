import AppKit
import GlyphSaverCore
import GlyphSaverKit

/// Programmatic options sheet (no XIB — this bundle is built with swiftc alone).
/// When a Studio-managed config.json exists it takes precedence over anything
/// saved here, so the sheet shows a notice.
final class ConfigSheet: NSObject {
    let window: NSPanel
    private let defaults: UserDefaults?

    private var themeChecks: [String: NSButton] = [:]
    private var effectChecks: [String: NSButton] = [:]
    private let cyclePopup = NSPopUpButton()
    private let speedSlider = NSSlider(value: 1, minValue: 0.25, maxValue: 4,
                                       target: nil, action: nil)
    private let speedLabel = NSTextField(labelWithString: "")
    private let fpsPopup = NSPopUpButton()
    private let fontPopup = NSPopUpButton()
    private let reducedMotionCheck = NSButton(checkboxWithTitle: "Reduce motion",
                                              target: nil, action: nil)
    private let textsView = NSTextView()
    private let artView = NSTextView()

    private static let fpsOptions: [Double] = [30, 60, 120]
    private static let fontOptions: [(String, Double)] = [
        ("Auto-fit", 0), ("10 pt", 10), ("12 pt", 12), ("14 pt", 14),
        ("18 pt", 18), ("24 pt", 24), ("32 pt", 32),
    ]

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 780),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        super.init()
        window.title = "GlyphSaver Options"
        buildUI()
        loadValues()
    }

    private func makeMonoTextArea(height: CGFloat, view: NSTextView) -> NSScrollView {
        view.font = NSFont(name: "Menlo", size: 11)
            ?? .monospacedSystemFont(ofSize: 11, weight: .regular)
        view.isRichText = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.allowsUndo = true
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

    private func buildUI() {
        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))

        func label(_ text: String) -> NSTextField {
            let l = NSTextField(labelWithString: text)
            l.font = .systemFont(ofSize: 13, weight: .semibold)
            return l
        }

        // Multi-select themes: checked palettes rotate between effect cycles.
        var themeRows: [[NSView]] = []
        var themeRow: [NSView] = []
        for theme in Theme.all {
            let check = NSButton(checkboxWithTitle: theme.displayName, target: nil, action: nil)
            check.font = .systemFont(ofSize: 11)
            themeChecks[theme.id] = check
            themeRow.append(check)
            if themeRow.count == 3 {
                themeRows.append(themeRow)
                themeRow = []
            }
        }
        if !themeRow.isEmpty { themeRows.append(themeRow) }
        let themesGrid = NSGridView(views: themeRows)
        themesGrid.rowSpacing = 3
        themesGrid.columnSpacing = 8

        // Effects → grid of checkboxes, 4 per row.
        var effectRows: [[NSView]] = []
        var row: [NSView] = []
        for name in EffectRegistry.allNames {
            let check = NSButton(checkboxWithTitle: name, target: nil, action: nil)
            check.font = .systemFont(ofSize: 11)
            effectChecks[name] = check
            row.append(check)
            if row.count == 4 {
                effectRows.append(row)
                row = []
            }
        }
        if !row.isEmpty { effectRows.append(row) }
        let effectsGrid = NSGridView(views: effectRows)
        effectsGrid.rowSpacing = 3
        effectsGrid.columnSpacing = 8

        let allButton = NSButton(title: "All", target: self, action: #selector(selectAllEffects))
        let noneButton = NSButton(title: "None", target: self, action: #selector(selectNoEffects))
        allButton.controlSize = .small
        noneButton.controlSize = .small
        let effectButtons = NSStackView(views: [allButton, noneButton])
        effectButtons.orientation = .horizontal

        cyclePopup.addItem(withTitle: "Random order")
        cyclePopup.lastItem?.representedObject = "random"
        cyclePopup.addItem(withTitle: "Sequential order")
        cyclePopup.lastItem?.representedObject = "sequential"

        for fps in ConfigSheet.fpsOptions {
            fpsPopup.addItem(withTitle: "\(Int(fps)) fps")
            fpsPopup.lastItem?.representedObject = fps
        }
        for (title, size) in ConfigSheet.fontOptions {
            fontPopup.addItem(withTitle: title)
            fontPopup.lastItem?.representedObject = size
        }

        speedSlider.target = self
        speedSlider.action = #selector(speedChanged)
        speedSlider.translatesAutoresizingMaskIntoConstraints = false
        speedSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        let textsScroll = makeMonoTextArea(height: 70, view: textsView)
        let artScroll = makeMonoTextArea(height: 110, view: artView)

        let textsHint = NSTextField(wrappingLabelWithString:
            "One text per line — each renders as big block letters and they rotate between "
            + "effects. Special: fractal:mandelbrot, fractal:julia, fractal:sierpinski.")
        textsHint.font = .systemFont(ofSize: 11)
        textsHint.textColor = .secondaryLabelColor
        let artHint = NSTextField(wrappingLabelWithString:
            "Optional ready-made ASCII art, shown as-is (FIGlet output, box art, …).")
        artHint.font = .systemFont(ofSize: 11)
        artHint.textColor = .secondaryLabelColor

        let speedRow = NSStackView(views: [speedSlider, speedLabel])
        speedRow.orientation = .horizontal

        let grid = NSGridView(views: [
            [label("Themes"), themesGrid],
            [label("Cycle"), cyclePopup],
            [label("Speed"), speedRow],
            [label("Frame rate"), fpsPopup],
            [label("Font size"), fontPopup],
            [NSGridCell.emptyContentView, reducedMotionCheck],
        ])
        grid.rowSpacing = 8
        grid.column(at: 0).xPlacement = .trailing

        let okButton = NSButton(title: "OK", target: self, action: #selector(save))
        okButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.addView(cancelButton, in: .trailing)
        buttons.addView(okButton, in: .trailing)

        var stackedViews: [NSView] = []
        if ConfigStore.configFileExists {
            let notice = NSTextField(wrappingLabelWithString:
                "⚠︎ Settings are currently managed by the GlyphSaver Studio app "
                + "(config.json). Changes made here are ignored until that file is removed.")
            notice.font = .systemFont(ofSize: 11, weight: .semibold)
            notice.textColor = .systemOrange
            stackedViews.append(notice)
        }
        stackedViews += [
            grid,
            label("Effects"), effectButtons, effectsGrid,
            label("Texts"), textsHint, textsScroll,
            label("Custom art"), artHint, artScroll,
            buttons,
        ]

        let main = NSStackView(views: stackedViews)
        main.orientation = .vertical
        main.alignment = .leading
        main.spacing = 10
        main.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        main.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(main)
        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: content.topAnchor),
            main.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            main.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            main.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            textsScroll.widthAnchor.constraint(equalTo: main.widthAnchor, constant: -40),
            artScroll.widthAnchor.constraint(equalTo: main.widthAnchor, constant: -40),
            buttons.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -20),
        ])
        window.contentView = content
    }

    private func loadValues() {
        let config = defaults.map(ConfigStore.load(from:)) ?? .default
        let activeThemes = config.themes.isEmpty ? [config.theme] : config.themes
        for (id, check) in themeChecks {
            check.state = activeThemes.contains(id) ? .on : .off
        }
        for (name, check) in effectChecks {
            check.state = config.enabledEffects.contains(name) ? .on : .off
        }
        cyclePopup.selectItem(at: config.cycleMode == "sequential" ? 1 : 0)
        speedSlider.doubleValue = config.speed
        fpsPopup.selectItem(at: ConfigSheet.fpsOptions.firstIndex(of: config.fps) ?? 1)
        let fontIndex = ConfigSheet.fontOptions.firstIndex { $0.1 == config.fontSize } ?? 0
        fontPopup.selectItem(at: fontIndex)
        reducedMotionCheck.state = config.reducedMotion ? .on : .off
        textsView.string = config.artTexts.joined(separator: "\n")
        artView.string = config.customArt
        speedChanged()
    }

    @objc private func selectAllEffects() {
        effectChecks.values.forEach { $0.state = .on }
    }

    @objc private func selectNoEffects() {
        effectChecks.values.forEach { $0.state = .off }
    }

    @objc private func speedChanged() {
        speedLabel.stringValue = String(format: "%.2f×", speedSlider.doubleValue)
    }

    @objc private func save() {
        var config = Config.default
        config.themes = Theme.all.map(\.id).filter { themeChecks[$0]?.state == .on }
        config.theme = config.themes.first ?? Config.default.theme
        config.enabledEffects = effectChecks.compactMap { name, check in
            check.state == .on ? name : nil
        }.sorted()
        config.cycleMode = cyclePopup.selectedItem?.representedObject as? String ?? "random"
        config.speed = speedSlider.doubleValue
        config.fps = fpsPopup.selectedItem?.representedObject as? Double ?? 60
        config.fontSize = fontPopup.selectedItem?.representedObject as? Double ?? 0
        config.reducedMotion = reducedMotionCheck.state == .on
        config.artTexts = textsView.string
            .split(separator: "\n").map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        config.customArt = artView.string
        if let defaults {
            ConfigStore.save(config, to: defaults)
        }
        dismiss(.OK)
    }

    @objc private func cancel() {
        dismiss(.cancel)
    }

    private func dismiss(_ code: NSApplication.ModalResponse) {
        // sheetParent belongs to System Settings — endSheet through it or the
        // sheet stays stuck and Settings hangs.
        if let parent = window.sheetParent {
            parent.endSheet(window, returnCode: code)
        } else {
            window.orderOut(nil)
        }
    }
}
