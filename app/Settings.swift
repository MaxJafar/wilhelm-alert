// The wilhelm-alert mini app: pick a mode, hear it, install it.
// A small AppKit control panel — no browser, no localhost, no menu bar item.
//
//   wilhelm-settings --root /path/to/wilhelm

import Cocoa

let repoRoot: String = {
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = it.next() {
        if arg == "--root", let value = it.next() { return value }
    }
    return FileManager.default.currentDirectoryPath
}()

private let wilhelmAccent = NSColor(calibratedRed: 0.91, green: 0.31, blue: 0.18, alpha: 1)

// MARK: - reusable views

final class RoundedCardView: NSView {
    var fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72) {
        didSet { needsDisplay = true }
    }
    var borderColor = NSColor.separatorColor.withAlphaComponent(0.55) {
        didSet { needsDisplay = true }
    }
    var borderWidth: CGFloat = 1 {
        didSet { needsDisplay = true }
    }
    var cornerRadius: CGFloat = 18 {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        fillColor.setFill()
        path.fill()

        guard borderWidth > 0 else { return }
        borderColor.setStroke()
        path.lineWidth = borderWidth
        path.stroke()
    }
}

final class ModeCardView: NSView {
    let modeIdentifier: String
    var onSelect: (() -> Void)?
    var isSelected = false {
        didSet {
            updateAppearance()
            needsDisplay = true
        }
    }

    private let titleLabel: NSTextField
    private let detailLabel: NSTextField
    private let badgeLabel: NSTextField
    private let clickTarget = NSButton()

    init(identifier: String, title: String, detail: String, badge: String) {
        self.modeIdentifier = identifier
        self.titleLabel = NSTextField(labelWithString: title)
        self.detailLabel = NSTextField(labelWithString: detail)
        self.badgeLabel = NSTextField(labelWithString: badge.uppercased())
        super.init(frame: .zero)

        wantsLayer = true

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        badgeLabel.font = .monospacedSystemFont(ofSize: 9, weight: .semibold)
        badgeLabel.alignment = .right

        for view in [titleLabel, detailLabel, badgeLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        clickTarget.title = ""
        clickTarget.isBordered = false
        clickTarget.isTransparent = true
        clickTarget.focusRingType = .none
        clickTarget.setButtonType(.momentaryPushIn)
        clickTarget.target = self
        clickTarget.action = #selector(pressed)
        clickTarget.toolTip = title
        addSubview(clickTarget)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 48),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: badgeLabel.leadingAnchor, constant: -10),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),

            badgeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            badgeLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 54),
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        clickTarget.frame = bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
        let fill = isSelected
            ? wilhelmAccent.withAlphaComponent(0.12)
            : NSColor.controlBackgroundColor.withAlphaComponent(0.58)
        let stroke = isSelected
            ? wilhelmAccent.withAlphaComponent(0.72)
            : NSColor.separatorColor.withAlphaComponent(0.48)
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = isSelected ? 1.5 : 1
        path.stroke()

        let indicatorRect = NSRect(x: 18, y: bounds.midY - 8, width: 16, height: 16)
        let indicator = NSBezierPath(ovalIn: indicatorRect)
        if isSelected {
            wilhelmAccent.setFill()
            indicator.fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: indicatorRect.insetBy(dx: 5, dy: 5)).fill()
        } else {
            NSColor.clear.setFill()
            indicator.fill()
            NSColor.separatorColor.setStroke()
            indicator.lineWidth = 1.2
            indicator.stroke()
        }
    }

    @objc private func pressed() {
        onSelect?()
    }

    private func updateAppearance() {
        titleLabel.textColor = isSelected ? wilhelmAccent : .labelColor
        badgeLabel.textColor = isSelected ? wilhelmAccent : .secondaryLabelColor
        clickTarget.setAccessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

// MARK: - settings controller

@MainActor
final class Controller: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var status: NSTextField!
    private var modeCards: [ModeCardView] = []
    private var statusCard: RoundedCardView!

    private let modes = [
        ("light", "Light", "Just the scream.", "QUIET"),
        ("middle", "Middle", "The scream, plus the model screaming back.", "POPULAR"),
        ("turbo", "Turbo", "The popup shakes itself apart.", "CHAOTIC"),
    ]
    private let agents = [
        ("openclaw", "OpenClaw", "HOOK"),
        ("antigravity", "Antigravity", "HOOK"),
        ("claude", "Claude", "PLUGIN"),
        ("codex", "Codex", "PLUGIN"),
        ("cursor", "Cursor", "HOOK"),
    ]

    private var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/wilhelm-alert/config")
    }

    private var selectedMode: String {
        modeCards.first(where: { $0.isSelected })?.modeIdentifier ?? "light"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let width: CGFloat = 620
        let height: CGFloat = 860
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "wilhelm-alert"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.minSize = NSSize(width: 560, height: 740)
        window.delegate = self
        window.center()

        let background = NSVisualEffectView()
        background.translatesAutoresizingMaskIntoConstraints = false
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .active
        window.contentView = background

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 30),
            content.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -30),
            content.topAnchor.constraint(equalTo: background.topAnchor, constant: 28),
            content.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -22),
        ])

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 13
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
        ])

        addFullWidth(makeHeader(), to: stack)
        addFullWidth(makeFacesSection(), to: stack)
        addFullWidth(makeModesSection(), to: stack)
        addFullWidth(makeTestRow(), to: stack)
        addFullWidth(makeSeparator(), to: stack)
        addFullWidth(makeInstallSection(), to: stack)
        addFullWidth(makeStatusCard(), to: stack)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if !FileManager.default.fileExists(atPath: repoRoot + "/sounds") {
            say("Warning: no sounds folder at " + repoRoot)
        }
    }

    // MARK: - view construction

    private func makeHeader() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 68).isActive = true

        let iconCard = RoundedCardView()
        iconCard.fillColor = wilhelmAccent.withAlphaComponent(0.13)
        iconCard.borderColor = wilhelmAccent.withAlphaComponent(0.3)
        iconCard.cornerRadius = 14
        iconCard.translatesAutoresizingMaskIntoConstraints = false

        let iconStrip = makeIconStrip()
        iconStrip.translatesAutoresizingMaskIntoConstraints = false
        iconCard.addSubview(iconStrip)
        NSLayoutConstraint.activate([
            iconCard.widthAnchor.constraint(equalToConstant: 132),
            iconCard.heightAnchor.constraint(equalToConstant: 46),
            iconStrip.leadingAnchor.constraint(equalTo: iconCard.leadingAnchor, constant: 8),
            iconStrip.trailingAnchor.constraint(equalTo: iconCard.trailingAnchor, constant: -8),
            iconStrip.topAnchor.constraint(equalTo: iconCard.topAnchor, constant: 8),
            iconStrip.bottomAnchor.constraint(equalTo: iconCard.bottomAnchor, constant: -8),
        ])

        let eyebrow = label("WILHELM ALERT", size: 10, bold: true)
        eyebrow.textColor = wilhelmAccent
        let heading = label("When agents finish, they scream.", size: 20, bold: true)
        let subheading = label("One loud little ritual for five coding agents.", size: 12, secondary: true)
        let copy = NSStackView(views: [eyebrow, heading, subheading])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 4
        copy.translatesAutoresizingMaskIntoConstraints = false

        let ready = label("READY", size: 10, bold: true)
        ready.textColor = NSColor.systemGreen
        ready.alignment = .center
        ready.wantsLayer = true
        ready.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.12).cgColor
        ready.layer?.cornerRadius = 9
        ready.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [iconCard, copy, ready])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ready.widthAnchor.constraint(equalToConstant: 58),
            ready.heightAnchor.constraint(equalToConstant: 22),
            copy.trailingAnchor.constraint(lessThanOrEqualTo: ready.leadingAnchor, constant: -8),
        ])
        copy.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return container
    }

    private func makeIconStrip() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fillEqually
        row.spacing = 4

        for (source, _, _) in agents {
            let tile = RoundedCardView()
            tile.fillColor = NSColor.black
            tile.borderColor = NSColor.white.withAlphaComponent(0.16)
            tile.cornerRadius = 8
            tile.translatesAutoresizingMaskIntoConstraints = false

            let imageView = NSImageView()
            imageView.image = NSImage(contentsOfFile: repoRoot + "/assets/scream-" + source + ".png")
            imageView.imageScaling = .scaleAxesIndependently
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 7
            imageView.layer?.masksToBounds = true
            tile.addSubview(imageView)
            NSLayoutConstraint.activate([
                tile.widthAnchor.constraint(equalToConstant: 20),
                tile.heightAnchor.constraint(equalToConstant: 30),
                imageView.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 2),
                imageView.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -2),
                imageView.topAnchor.constraint(equalTo: tile.topAnchor, constant: 2),
                imageView.bottomAnchor.constraint(equalTo: tile.bottomAnchor, constant: -2),
            ])
            row.addArrangedSubview(tile)
        }
        return row
    }

    private func makeFacesSection() -> NSView {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 9

        section.addArrangedSubview(makeSectionHeader(
            title: "Your agent roster",
            subtitle: "Five faces. One shared completion ritual."
        ))

        let faces = NSStackView()
        faces.orientation = .horizontal
        faces.alignment = .height
        faces.distribution = .fillEqually
        faces.spacing = 8
        faces.heightAnchor.constraint(equalToConstant: 126).isActive = true
        faces.widthAnchor.constraint(equalToConstant: 560).isActive = true
        for (source, title, badge) in agents {
            faces.addArrangedSubview(makeAgentFaceTile(source: source, title: title, badge: badge))
        }
        section.addArrangedSubview(faces)
        return section
    }

    private func makeAgentFaceTile(source: String, title: String, badge: String) -> NSView {
        let card = RoundedCardView()
        card.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.66)
        card.cornerRadius = 15

        let imageShell = RoundedCardView()
        imageShell.fillColor = NSColor.black
        imageShell.borderColor = NSColor.white.withAlphaComponent(0.16)
        imageShell.cornerRadius = 10
        imageShell.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        let faceImage = NSImage(contentsOfFile: repoRoot + "/assets/scream-" + source + ".png")
        imageView.image = faceImage ?? NSImage(
            systemSymbolName: "questionmark",
            accessibilityDescription: "missing face"
        )
        imageView.contentTintColor = faceImage == nil ? .tertiaryLabelColor : nil
        imageView.imageScaling = .scaleAxesIndependently
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 9
        imageView.layer?.masksToBounds = true
        imageShell.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageShell.widthAnchor.constraint(equalToConstant: 78),
            imageShell.heightAnchor.constraint(equalToConstant: 62),
            imageView.leadingAnchor.constraint(equalTo: imageShell.leadingAnchor, constant: 3),
            imageView.trailingAnchor.constraint(equalTo: imageShell.trailingAnchor, constant: -3),
            imageView.topAnchor.constraint(equalTo: imageShell.topAnchor, constant: 3),
            imageView.bottomAnchor.constraint(equalTo: imageShell.bottomAnchor, constant: -3),
        ])

        let name = label(title, size: 10, bold: true)
        name.alignment = .center
        name.lineBreakMode = .byTruncatingTail
        let loaded = label(faceImage == nil ? "MISSING" : badge, size: 8, bold: true)
        loaded.alignment = .center
        loaded.textColor = faceImage == nil ? NSColor.systemRed : NSColor.systemGreen
        let copy = NSStackView(views: [name, loaded])
        copy.orientation = .vertical
        copy.alignment = .centerX
        copy.spacing = 3
        copy.translatesAutoresizingMaskIntoConstraints = false

        let content = NSStackView(views: [imageShell, copy])
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 5
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 5),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -5),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
        ])
        return card
    }

    private func makeModesSection() -> NSView {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 7
        section.addArrangedSubview(makeSectionHeader(
            title: "Choose your volume",
            subtitle: "How much chaos should follow a finished task?"
        ))

        let cards = NSView()
        cards.translatesAutoresizingMaskIntoConstraints = false
        cards.widthAnchor.constraint(equalToConstant: 560).isActive = true
        cards.heightAnchor.constraint(equalToConstant: 182).isActive = true

        let current = readConfiguredMode()
        var previousCard: ModeCardView?
        for (index, mode) in modes.enumerated() {
            let (identifier, title, detail, badge) = mode
            let card = ModeCardView(identifier: identifier, title: title, detail: detail, badge: badge)
            card.isSelected = identifier == current
            card.onSelect = { [weak self, weak card] in
                guard let card else { return }
                self?.selectMode(card)
            }
            card.translatesAutoresizingMaskIntoConstraints = false
            modeCards.append(card)
            cards.addSubview(card)
            var constraints = [
                card.leadingAnchor.constraint(equalTo: cards.leadingAnchor),
                card.trailingAnchor.constraint(equalTo: cards.trailingAnchor),
                card.heightAnchor.constraint(equalToConstant: 56),
            ]
            if let previousCard {
                constraints.append(card.topAnchor.constraint(equalTo: previousCard.bottomAnchor, constant: 7))
            } else {
                constraints.append(card.topAnchor.constraint(equalTo: cards.topAnchor))
            }
            if index == modes.count - 1 {
                constraints.append(card.bottomAnchor.constraint(equalTo: cards.bottomAnchor))
            }
            NSLayoutConstraint.activate(constraints)
            previousCard = card
        }
        section.addArrangedSubview(cards)
        return section
    }

    private func makeTestRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        let test = NSButton(title: "Test the alert", target: self, action: #selector(testAlert))
        test.bezelStyle = .rounded
        test.controlSize = .large
        test.font = .systemFont(ofSize: 13, weight: .semibold)
        test.contentTintColor = .white
        test.bezelColor = wilhelmAccent
        test.keyEquivalent = "\r"
        test.toolTip = "Play the sound and show the selected face"
        test.setContentHuggingPriority(.required, for: .horizontal)

        let hint = label("Saved automatically to your alert config.", size: 11, secondary: true)
        hint.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(test)
        row.addArrangedSubview(hint)
        row.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return row
    }

    private func makeSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }

    private func makeInstallSection() -> NSView {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 7
        section.addArrangedSubview(makeSectionHeader(
            title: "Install into your agents",
            subtitle: "Keep your local completion hooks one click away."
        ))
        let claudeRow = makeAgentRow(
            source: "claude",
            title: "Claude Code",
            detail: "Install or refresh the Claude plugin.",
            tag: 0
        )
        let codexRow = makeAgentRow(
            source: "codex",
            title: "Codex",
            detail: "Install or refresh the Codex plugin.",
            tag: 1
        )
        let cursorRow = makeAgentRow(
            source: "cursor",
            title: "Cursor",
            detail: "Add the stop hook to ~/.cursor/hooks.json.",
            tag: 2
        )
        claudeRow.widthAnchor.constraint(equalToConstant: 560).isActive = true
        codexRow.widthAnchor.constraint(equalToConstant: 560).isActive = true
        cursorRow.widthAnchor.constraint(equalToConstant: 560).isActive = true
        section.addArrangedSubview(claudeRow)
        section.addArrangedSubview(codexRow)
        section.addArrangedSubview(cursorRow)
        return section
    }

    private func makeAgentRow(source: String, title: String, detail: String, tag: Int) -> NSView {
        let card = RoundedCardView()
        card.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.58)
        card.cornerRadius = 15
        card.heightAnchor.constraint(equalToConstant: 68).isActive = true

        let imageShell = RoundedCardView()
        let faceImage = NSImage(contentsOfFile: repoRoot + "/assets/scream-" + source + ".png")
        // Agents without their own face (Cursor, say) would otherwise render
        // as an empty white square that reads as a broken image.
        imageShell.fillColor = faceImage == nil
            ? NSColor.controlBackgroundColor
            : NSColor.black
        imageShell.borderColor = NSColor.separatorColor.withAlphaComponent(0.3)
        imageShell.cornerRadius = 10
        imageShell.translatesAutoresizingMaskIntoConstraints = false
        let imageView = NSImageView()
        imageView.image = faceImage ?? NSImage(
            systemSymbolName: "questionmark",
            accessibilityDescription: "no face yet"
        )
        imageView.contentTintColor = .tertiaryLabelColor
        imageView.imageScaling = faceImage == nil ? .scaleProportionallyDown : .scaleAxesIndependently
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 8
        imageView.layer?.masksToBounds = true
        imageShell.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageShell.widthAnchor.constraint(equalToConstant: 46),
            imageShell.heightAnchor.constraint(equalToConstant: 46),
            imageView.leadingAnchor.constraint(equalTo: imageShell.leadingAnchor, constant: 3),
            imageView.trailingAnchor.constraint(equalTo: imageShell.trailingAnchor, constant: -3),
            imageView.topAnchor.constraint(equalTo: imageShell.topAnchor, constant: 3),
            imageView.bottomAnchor.constraint(equalTo: imageShell.bottomAnchor, constant: -3),
        ])

        let name = label(title, size: 13, bold: true)
        let description = label(detail, size: 11, secondary: true)
        let copy = NSStackView(views: [name, description])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 3
        copy.translatesAutoresizingMaskIntoConstraints = false
        copy.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let install = NSButton(title: "Install / Update", target: self, action: #selector(installAgent(_:)))
        install.bezelStyle = .rounded
        install.controlSize = .regular
        install.font = .systemFont(ofSize: 11, weight: .semibold)
        install.tag = tag
        install.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [imageShell, copy, spacer, install])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 11),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -11),
        ])
        return card
    }

    private func makeStatusCard() -> NSView {
        statusCard = RoundedCardView()
        statusCard.fillColor = wilhelmAccent.withAlphaComponent(0.08)
        statusCard.borderColor = wilhelmAccent.withAlphaComponent(0.22)
        statusCard.cornerRadius = 14
        statusCard.heightAnchor.constraint(equalToConstant: 38).isActive = true

        let icon = NSImageView(image: NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Status") ?? NSImage())
        icon.contentTintColor = wilhelmAccent
        icon.translatesAutoresizingMaskIntoConstraints = false

        status = label("Ready. Pick a mode, then test the ritual.", size: 11, secondary: true)
        status.maximumNumberOfLines = 2
        status.lineBreakMode = .byTruncatingTail
        status.translatesAutoresizingMaskIntoConstraints = false
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [icon, status])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        statusCard.addSubview(row)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 17),
            icon.heightAnchor.constraint(equalToConstant: 17),
            row.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 13),
            row.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -13),
            row.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: -8),
        ])
        return statusCard
    }

    private func makeSectionHeader(title: String, subtitle: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.addArrangedSubview(label(title, size: 14, bold: true))
        stack.addArrangedSubview(label(subtitle, size: 11, secondary: true))
        return stack
    }

    private func addFullWidth(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalToConstant: 560).isActive = true
    }

    // MARK: - actions

    private func selectMode(_ selected: ModeCardView) {
        for card in modeCards {
            card.isSelected = card === selected
        }
        writeConfiguredMode(selectedMode)
        say("Mode set to \(selectedMode). Ready when your agent is.")
    }

    @objc private func testAlert() {
        run(repoRoot + "/bin/wilhelm-alert", args: [], env: ["WILHELM_ALERT_MODE": selectedMode])
        say("Testing \(selectedMode)… Look alive.")
    }

    @objc private func installAgent(_ sender: NSButton) {
        if sender.tag == 2 {
            installCursor()
            return
        }
        let isClaude = sender.tag == 0
        let tool = isClaude ? "claude" : "codex"
        guard let binary = which(tool) else {
            say("Couldn't find `\(tool)` on your PATH.")
            return
        }
        say("Installing into \(isClaude ? "Claude Code" : "Codex")…")

        let marketplace = isClaude
            ? ["plugin", "marketplace", "add", "./"]
            : ["plugin", "marketplace", "add", "."]
        _ = capture(binary, args: marketplace, cwd: repoRoot)

        let add = isClaude
            ? ["plugin", "install", "wilhelm-alert@wilhelm-alert-marketplace"]
            : ["plugin", "add", "wilhelm-alert@wilhelm-alert-marketplace"]
        var output = capture(binary, args: add, cwd: repoRoot)

        // Already-installed copies are pinned by version, so a plain install
        // is a no-op after the first time; update is what refreshes the cache.
        if isClaude, output.contains("already installed") {
            output = capture(binary, args: ["plugin", "update", "wilhelm-alert@wilhelm-alert-marketplace"], cwd: repoRoot)
        }

        // Codex reports the plugin as enabled but silently skips its hooks
        // until they're approved in the TUI, so say so here rather than
        // letting it look finished.
        if !isClaude {
            say("Installed. Now start `codex` in a terminal and approve the hook review — it won't fire until you do.")
            return
        }

        let firstLine = output
            .split(separator: "\n")
            .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map(String.init) ?? "done"
        say(firstLine.trimmingCharacters(in: .whitespaces))
    }

    // Cursor has no plugin CLI, so this edits ~/.cursor/hooks.json directly —
    // merging into whatever is already there rather than replacing it, since
    // that file is very likely to hold hooks the user cares about.
    private func installCursor() {
        let hooksURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/hooks.json")
        let command = "node \"\(repoRoot)/bin/wilhelm-alert.js\" --source cursor"

        var root: [String: Any] = ["version": 1]
        if let data = try? Data(contentsOf: hooksURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = existing
            if root["version"] == nil { root["version"] = 1 }
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var stopHooks = hooks["stop"] as? [[String: Any]] ?? []
        stopHooks.removeAll { ($0["command"] as? String)?.contains("wilhelm-alert") == true }
        stopHooks.append(["command": command])
        hooks["stop"] = stopHooks
        root["hooks"] = hooks

        do {
            try FileManager.default.createDirectory(
                at: hooksURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .withoutEscapingSlashes]
            )
            try data.write(to: hooksURL, options: .atomic)
            say("Added the stop hook to ~/.cursor/hooks.json — restart Cursor.")
        } catch {
            say("Couldn't write ~/.cursor/hooks.json: \(error.localizedDescription)")
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    // MARK: - helpers

    private func say(_ text: String) {
        status?.stringValue = text
    }

    private func label(_ text: String, size: CGFloat, bold: Bool = false, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = bold
            ? .systemFont(ofSize: size, weight: .semibold)
            : .systemFont(ofSize: size)
        if secondary { field.textColor = .secondaryLabelColor }
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    private func readConfiguredMode() -> String {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return "light" }
        for line in text.split(separator: "\n") where line.hasPrefix("mode=") {
            return String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }
        return "light"
    }

    private func writeConfiguredMode(_ mode: String) {
        let directory = configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? "mode=\(mode)\n".write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func which(_ tool: String) -> String? {
        let output = capture("/bin/sh", args: ["-lc", "command -v \(tool)"], cwd: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    @discardableResult
    private func capture(_ path: String, args: [String], cwd: String?) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return "failed to run \(path)" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func run(_ path: String, args: [String], env: [String: String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        var environment = ProcessInfo.processInfo.environment
        env.forEach { environment[$0.key] = $0.value }
        process.environment = environment
        try? process.run()
    }
}

// NSApplication.delegate is a weak reference, so the controller has to be
// held somewhere that outlives this scope.
var retainedController: AnyObject?

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let controller = Controller()
    retainedController = controller
    app.delegate = controller
    app.run()
}
