import AppKit
import GlyphSaverCore

/// Studio design tokens — the app wears the saver's own Omarchy palette so the
/// tool and the screensaver read as one product.
enum StudioStyle {
    static let canvas = NSColor(srgbRed: 0.051, green: 0.055, blue: 0.078, alpha: 1)   // 0D0E14
    static let well = NSColor(srgbRed: 0.075, green: 0.086, blue: 0.133, alpha: 1)     // 131622
    static let hairline = NSColor.white.withAlphaComponent(0.08)
    static let text = NSColor(srgbRed: 0.753, green: 0.792, blue: 0.961, alpha: 1)     // C0CAF5
    static let muted = NSColor(srgbRed: 0.337, green: 0.373, blue: 0.537, alpha: 1)    // 565F89
    static let accent = NSColor(srgbRed: 0.490, green: 0.812, blue: 1.0, alpha: 1)     // 7DCFFF

    static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func menlo(_ size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: bold ? "Menlo-Bold" : "Menlo", size: size)
            ?? mono(size, weight: bold ? .bold : .regular)
    }

    /// Tracked-uppercase mono section label ("T E X T S" energy without the spaces).
    static func eyebrow(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.attributedStringValue = NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: menlo(10),
                .foregroundColor: muted,
                .kern: 1.8,
            ]
        )
        return label
    }

    static func hint(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 10)
        label.textColor = muted
        return label
    }

    static func hairlineView() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = hairline.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    static func color(_ rgba: RGBA) -> NSColor {
        NSColor(srgbRed: CGFloat(rgba.r), green: CGFloat(rgba.g),
                blue: CGFloat(rgba.b), alpha: CGFloat(rgba.a))
    }
}

/// A theme rendered as its own material: ▓▒░ in the theme's ramp colors on the
/// theme's background. Selected = accent ring.
final class ThemeChipButton: NSButton {
    let theme: Theme

    init(theme: Theme, target: AnyObject?, action: Selector?) {
        self.theme = theme
        super.init(frame: .zero)
        self.target = target
        self.action = action
        setButtonType(.toggle)
        isBordered = false
        title = ""
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 116).isActive = true
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        setAccessibilityLabel("\(theme.displayName) theme")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)

        StudioStyle.color(theme.background).setFill()
        path.fill()

        let glyphs = NSMutableAttributedString()
        for (i, ch) in ["▓", "▒", "░"].enumerated() {
            let ramp = theme.rampColor(1.0 - Float(i) * 0.32)
            glyphs.append(NSAttributedString(string: ch, attributes: [
                .font: StudioStyle.menlo(11),
                .foregroundColor: StudioStyle.color(ramp),
            ]))
        }
        glyphs.append(NSAttributedString(string: "  " + theme.displayName.lowercased(),
                                         attributes: [
            .font: StudioStyle.menlo(10),
            .foregroundColor: selected ? StudioStyle.color(theme.art)
                                       : StudioStyle.color(theme.art).withAlphaComponent(0.55),
        ]))
        let size = glyphs.size()
        glyphs.draw(at: NSPoint(x: rect.minX + 9,
                                y: rect.midY - size.height / 2))

        path.lineWidth = selected ? 1.5 : 1
        (selected ? StudioStyle.accent : StudioStyle.hairline).setStroke()
        path.stroke()
    }
}
