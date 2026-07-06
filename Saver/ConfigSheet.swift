import AppKit
import GlyphSaverCore
import GlyphSaverKit

/// Programmatic options sheet (no XIB — this bundle is built with swiftc alone).
final class ConfigSheet: NSObject {
    let window: NSPanel
    private let defaults: UserDefaults?

    private let themePopup = NSPopUpButton()
    private var effectChecks: [String: NSButton] = [:]
    private let cyclePopup = NSPopUpButton()
    private let speedSlider = NSSlider(value: 1, minValue: 0.25, maxValue: 4,
                                       target: nil, action: nil)
    private let speedLabel = NSTextField(labelWithString: "")
    private let fpsPopup = NSPopUpButton()
    private let fontPopup = NSPopUpButton()
    private let reducedMotionCheck = NSButton(checkboxWithTitle: "Reduce motion",
                                              target: nil, action: nil)
    private let artView = NSTextView()

    private static let fpsOptions: [Double] = [30, 60, 120]
    private static let fontOptions: [(String, Double)] = [
        ("Auto-fit", 0), ("10 pt", 10), ("12 pt", 12), ("14 pt", 14),
        ("18 pt", 18), ("24 pt", 24), ("32 pt", 32),
    ]

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        super.init()
        window.title = "GlyphSaver Options"
        buildUI()
        loadValues()
    }

    private func buildUI() {
        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))

        func label(_ text: String) -> NSTextField {
            let l = NSTextField(labelWithString: text)
            l.font = .systemFont(ofSize: 13, weight: .semibold)
            return l
        }

        for theme in Theme.all {
            themePopup.addItem(withTitle: theme.displayName)
            themePopup.lastItem?.representedObject = theme.id
        }

        let effectsStack = NSStackView()
        effectsStack.orientation = .horizontal
        effectsStack.spacing = 12
        for name in EffectRegistry.allNames {
            let check = NSButton(checkboxWithTitle: name.capitalized, target: nil, action: nil)
            effectChecks[name] = check
            effectsStack.addArrangedSubview(check)
        }

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

        artView.font = NSFont(name: "Menlo", size: 11) ?? .monospacedSystemFont(ofSize: 11, weight: .regular)
        artView.isRichText = false
        artView.isAutomaticQuoteSubstitutionEnabled = false
        artView.allowsUndo = true
        let artScroll = NSScrollView()
        artScroll.documentView = artView
        artScroll.hasVerticalScroller = true
        artScroll.borderType = .bezelBorder
        artScroll.translatesAutoresizingMaskIntoConstraints = false
        artScroll.heightAnchor.constraint(equalToConstant: 180).isActive = true
        artView.autoresizingMask = [.width]
        artView.minSize = NSSize(width: 0, height: 180)
        artView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                 height: CGFloat.greatestFiniteMagnitude)
        artView.isVerticallyResizable = true
        artView.textContainer?.widthTracksTextView = true

        let artHint = NSTextField(wrappingLabelWithString:
            "Custom text or ASCII art (leave empty for the built-in logo). Paste FIGlet output, box art, whatever — it will be centered.")
        artHint.font = .systemFont(ofSize: 11)
        artHint.textColor = .secondaryLabelColor

        let speedRow = NSStackView(views: [speedSlider, speedLabel])
        speedRow.orientation = .horizontal

        let grid = NSGridView(views: [
            [label("Theme"), themePopup],
            [label("Effects"), effectsStack],
            [label("Cycle"), cyclePopup],
            [label("Speed"), speedRow],
            [label("Frame rate"), fpsPopup],
            [label("Font size"), fontPopup],
            [NSGridCell.emptyContentView, reducedMotionCheck],
        ])
        grid.rowSpacing = 10
        grid.column(at: 0).xPlacement = .trailing

        let okButton = NSButton(title: "OK", target: self, action: #selector(save))
        okButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.addView(cancelButton, in: .trailing)
        buttons.addView(okButton, in: .trailing)

        let main = NSStackView(views: [grid, label("Custom art"), artHint, artScroll, buttons])
        main.orientation = .vertical
        main.alignment = .leading
        main.spacing = 12
        main.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        main.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(main)
        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: content.topAnchor),
            main.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            main.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            main.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            artScroll.widthAnchor.constraint(equalTo: main.widthAnchor, constant: -40),
            buttons.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -20),
        ])
        window.contentView = content
    }

    private func loadValues() {
        let config = defaults.map(ConfigStore.load(from:)) ?? .default
        themePopup.selectItem(at: Theme.all.firstIndex { $0.id == config.theme } ?? 0)
        for (name, check) in effectChecks {
            check.state = config.enabledEffects.contains(name) ? .on : .off
        }
        cyclePopup.selectItem(at: config.cycleMode == "sequential" ? 1 : 0)
        speedSlider.doubleValue = config.speed
        fpsPopup.selectItem(at: ConfigSheet.fpsOptions.firstIndex(of: config.fps) ?? 1)
        let fontIndex = ConfigSheet.fontOptions.firstIndex { $0.1 == config.fontSize } ?? 0
        fontPopup.selectItem(at: fontIndex)
        reducedMotionCheck.state = config.reducedMotion ? .on : .off
        artView.string = config.customArt
        speedChanged()
    }

    @objc private func speedChanged() {
        speedLabel.stringValue = String(format: "%.2f×", speedSlider.doubleValue)
    }

    @objc private func save() {
        var config = Config.default
        config.theme = themePopup.selectedItem?.representedObject as? String ?? config.theme
        config.enabledEffects = effectChecks.compactMap { name, check in
            check.state == .on ? name : nil
        }
        config.cycleMode = cyclePopup.selectedItem?.representedObject as? String ?? "random"
        config.speed = speedSlider.doubleValue
        config.fps = fpsPopup.selectedItem?.representedObject as? Double ?? 60
        config.fontSize = fontPopup.selectedItem?.representedObject as? Double ?? 0
        config.reducedMotion = reducedMotionCheck.state == .on
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
