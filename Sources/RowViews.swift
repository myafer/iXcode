import AppKit

// MARK: - 置顶标记（SF Symbol 小图钉，取代原来的 📌 emoji）

enum PinMark {
    /// 模板图钉图标：isTemplate 让系统按亮/暗色自动上色，尺寸跟随字号
    static func image(pointSize: CGFloat = 10) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        guard let base = NSImage(systemSymbolName: "pin.fill",
                                 accessibilityDescription: L10n.tr("pin")) else { return nil }
        let img = base.withSymbolConfiguration(cfg) ?? base
        img.isTemplate = true
        return img
    }

    /// 固定宽度的槽位，给没置顶的行也留出位置，保证所有行名字左对齐
    static let slotWidth: CGFloat = 11
}

// MARK: - 菜单行视图（双行：名字 + 路径/时间）

final class ProjectRowView: NSView {
    private let project: RecentProject
    private let pinned: Bool
    private let onClick: (RecentProject, NSEvent) -> Void
    private let onTogglePin: (RecentProject) -> Void

    init(project: RecentProject,
         pinned: Bool,
         onClick: @escaping (RecentProject, NSEvent) -> Void,
         onTogglePin: @escaping (RecentProject) -> Void) {
        self.project = project
        self.pinned = pinned
        self.onClick = onClick
        self.onTogglePin = onTogglePin
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 40))
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true

        let name = NSTextField(labelWithString: project.displayName)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        name.textColor = project.exists ? .labelColor : .tertiaryLabelColor
        name.lineBreakMode = .byTruncatingTail
        name.setContentHuggingPriority(.defaultLow, for: .horizontal)
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let pinSlot = NSView()
        pinSlot.translatesAutoresizingMaskIntoConstraints = false
        pinSlot.widthAnchor.constraint(equalToConstant: PinMark.slotWidth).isActive = true
        pinSlot.heightAnchor.constraint(equalToConstant: 12).isActive = true
        if pinned, let pinImage = PinMark.image(pointSize: 10) {
            let pinView = NSImageView()
            pinView.image = pinImage
            pinView.contentTintColor = .tertiaryLabelColor
            pinView.translatesAutoresizingMaskIntoConstraints = false
            pinSlot.addSubview(pinView)
            NSLayoutConstraint.activate([
                pinView.centerXAnchor.constraint(equalTo: pinSlot.centerXAnchor),
                pinView.centerYAnchor.constraint(equalTo: pinSlot.centerYAnchor),
            ])
        }

        let time = NSTextField(labelWithString: project.exists ? project.relativeTime : L10n.tr("missing"))
        time.font = .systemFont(ofSize: 11)
        time.textColor = .secondaryLabelColor
        time.alignment = .right
        time.setContentHuggingPriority(.required, for: .horizontal)

        let pathLabel = NSTextField(labelWithString: project.detailPath)
        pathLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingHead
        pathLabel.cell?.truncatesLastVisibleLine = true

        let nameRow = NSStackView(views: [pinSlot, name])
        nameRow.orientation = .horizontal
        nameRow.alignment = .centerY
        nameRow.spacing = 4
        nameRow.translatesAutoresizingMaskIntoConstraints = false
        nameRow.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let topRow = NSStackView(views: [nameRow, time])
        topRow.translatesAutoresizingMaskIntoConstraints = false
        topRow.distribution = .fill

        let col = NSStackView(views: [topRow, pathLabel])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 2
        col.translatesAutoresizingMaskIntoConstraints = false
        addSubview(col)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 420),
            heightAnchor.constraint(equalToConstant: 40),
            col.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            col.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            col.centerYAnchor.constraint(equalTo: centerYAnchor),
            topRow.widthAnchor.constraint(equalTo: col.widthAnchor),
        ])
    }

    override func mouseUp(with event: NSEvent) {
        onClick(project, event)
    }

    // MARK: 右键菜单（置顶 / Finder / 拷贝路径）

    override func rightMouseDown(with event: NSEvent) {
        // ⌃+左键 = 直接切换置顶（菜单底部提示里写的就是这个），不弹菜单
        if event.modifierFlags.contains(.control) {
            onTogglePin(project)
            return
        }
        let menu = NSMenu()
        let pin = NSMenuItem(title: L10n.tr(pinned ? "unpin" : "pin"), action: #selector(ctxTogglePin), keyEquivalent: "")
        pin.target = self
        menu.addItem(pin)
        menu.addItem(.separator())

        let reveal = NSMenuItem(title: L10n.tr("revealInFinder"), action: #selector(ctxReveal), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        let copy = NSMenuItem(title: L10n.tr("copyPath"), action: #selector(ctxCopyPath), keyEquivalent: "")
        copy.target = self
        menu.addItem(copy)

        menu.popUp(positioning: nil, at: NSPoint(x: 14, y: bounds.maxY), in: self)
    }

    @objc private func ctxTogglePin() {
        onTogglePin(project)
    }

    @objc private func ctxReveal() {
        NSWorkspace.shared.selectFile(project.path, inFileViewerRootedAtPath: project.directory)
    }

    @objc private func ctxCopyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(project.path, forType: .string)
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.15).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self
        ))
    }
}

// MARK: - 模拟器「应用」行视图（iSimulator 风格：圆角白底图标 + 名称·版本 + bundleID）

final class AppRowView: NSView {
    private let app: SimApp

    init(app: SimApp) {
        self.app = app
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 46))
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true

        // 圆角白底图标块
        let tile = NSView(frame: NSRect(x: 0, y: 0, width: 34, height: 34))
        tile.wantsLayer = true
        tile.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        tile.layer?.cornerRadius = 8
        tile.layer?.masksToBounds = true
        tile.layer?.borderWidth = 0.5
        tile.layer?.borderColor = NSColor.separatorColor.cgColor

        let iconView = NSImageView(frame: tile.bounds)
        iconView.autoresizingMask = [.width, .height]
        iconView.imageScaling = .scaleProportionallyUpOrDown

        if let bp = app.bundlePath {
            if let cached = RecentsScanner.cachedAppIcon(bundlePath: bp) {
                iconView.image = cached
            } else {
                // 图标解码会读盘，后台做完再回主线程塞进来，避免子菜单弹出时卡顿
                iconView.image = NSImage(systemSymbolName: "app", accessibilityDescription: nil)
                DispatchQueue.global(qos: .utility).async {
                    guard let img = RecentsScanner.loadAppIcon(bundlePath: bp) else { return }
                    DispatchQueue.main.async { iconView.image = img }
                }
            }
        } else {
            iconView.image = NSImage(systemSymbolName: "app", accessibilityDescription: nil)
        }
        tile.addSubview(iconView)

        let name = NSTextField(labelWithString: app.displayTitle)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.lineBreakMode = .byTruncatingTail
        name.cell?.truncatesLastVisibleLine = true

        let bundle = NSTextField(labelWithString: app.bundleID)
        bundle.font = .systemFont(ofSize: 10.5)
        bundle.textColor = .secondaryLabelColor
        bundle.lineBreakMode = .byTruncatingTail
        bundle.cell?.truncatesLastVisibleLine = true

        let col = NSStackView(views: [name, bundle])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 2
        col.translatesAutoresizingMaskIntoConstraints = false

        let chevron = NSTextField(labelWithString: "›")
        chevron.font = .systemFont(ofSize: 15, weight: .light)
        chevron.textColor = .tertiaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false

        addSubview(tile)
        addSubview(col)
        addSubview(chevron)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 360),
            heightAnchor.constraint(equalToConstant: 46),
            tile.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            tile.centerYAnchor.constraint(equalTo: centerYAnchor),
            tile.widthAnchor.constraint(equalToConstant: 34),
            tile.heightAnchor.constraint(equalToConstant: 34),
            col.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 10),
            col.centerYAnchor.constraint(equalTo: centerYAnchor),
            col.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            col.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
        ])
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.15).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self
        ))
    }
}
