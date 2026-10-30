import AppKit
import ServiceManagement

// MARK: - 设置面板（分 tab：通用 / 关于）

/// 用闭包生成 view 的轻量 NSViewController，避免为每个 tab 单开一个类
final class TabHostViewController: NSViewController {
    private let build: () -> NSView
    private let inset: NSEdgeInsets

    init(size: NSSize, inset: NSEdgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20),
         build: @escaping () -> NSView) {
        self.build = build
        self.inset = inset
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = size
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))
        let content = build()
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: inset.top),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: inset.left),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -inset.right),
        ])
        view = root
    }
}

extension AppDelegate {

    private static let settingsWidth: CGFloat = 460
    private static let settingsContentWidth: CGFloat = 460 - 20 * 2

    // MARK: 入口

    @objc func showSettings() {
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar

        let general = NSTabViewItem(viewController: TabHostViewController(size: NSSize(width: Self.settingsWidth, height: 432)) { [weak self] in
            self?.buildGeneralTab() ?? NSView()
        })
        general.label = L10n.tr("tabGeneral")
        general.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)

        let about = NSTabViewItem(viewController: TabHostViewController(size: NSSize(width: Self.settingsWidth, height: 432)) { [weak self] in
            self?.buildAboutTab() ?? NSView()
        })
        about.label = L10n.tr("tabAbout")
        about.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)

        tabs.addTabViewItem(general)
        tabs.addTabViewItem(about)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.settingsWidth, height: 432),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = L10n.tr("settingsTitle")
        window.contentViewController = tabs
        window.setContentSize(NSSize(width: Self.settingsWidth, height: 432))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 语言切换后重建窗口时，回到原来的 tab
        if let keep = pendingSettingsTab, keep < tabs.tabViewItems.count {
            tabs.selectedTabViewItemIndex = keep
            pendingSettingsTab = nil
        }
        settingsWindow = window
        refreshUpdateUI()
    }

    /// 打开设置窗口并直接停在「关于」tab（主菜单的「关于 iXcode」用）
    @objc func showAbout() {
        if let tabs = settingsWindow?.contentViewController as? NSTabViewController {
            tabs.selectedTabViewItemIndex = 1
            settingsWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        pendingSettingsTab = 1
        showSettings()
    }

    /// 语言切换等需要重建窗口时，记住当前 tab
    private var currentSettingsTab: Int {
        (settingsWindow?.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex ?? 0
    }

    // MARK: 通用

    private func buildGeneralTab() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10

        // 语言
        let langPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        [L10n.tr("langAuto"), L10n.tr("langZH"), L10n.tr("langEN")].forEach { langPopup.addItem(withTitle: $0) }
        switch Settings.language {
        case "zh-Hans": langPopup.selectItem(at: 1)
        case "en": langPopup.selectItem(at: 2)
        default: langPopup.selectItem(at: 0)
        }
        langPopup.target = self
        langPopup.action = #selector(languageChanged(_:))
        langPopup.widthAnchor.constraint(equalToConstant: 170).isActive = true

        let langRow = labeledRow(L10n.tr("language"), langPopup)

        // 最大条目
        let maxLabel = NSTextField(labelWithString: "\(Settings.maxItems)")
        maxLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        maxLabel.alignment = .right
        maxLabel.widthAnchor.constraint(equalToConstant: 24).isActive = true
        maxItemsLabel = maxLabel

        let stepper = NSStepper()
        stepper.minValue = 5
        stepper.maxValue = 30
        stepper.increment = 1
        stepper.doubleValue = Double(Settings.maxItems)
        stepper.target = self
        stepper.action = #selector(maxItemsChanged(_:))

        let maxTrailing = NSStackView(views: [maxLabel, stepper])
        maxTrailing.orientation = .horizontal
        maxTrailing.spacing = 6
        let maxRow = labeledRow(L10n.tr("maxItems"), maxTrailing)

        // 菜单内容
        let cleanBtn = checkbox(L10n.tr("showCleanDD"), id: "showCleanDD",
                                value: Settings.showCleanDD, action: #selector(toggleSetting(_:)))
        let simsBtn = checkbox(L10n.tr("showSims"), id: "showSims",
                               value: Settings.showSims, action: #selector(toggleSetting(_:)))
        let foldersBtn = checkbox(L10n.tr("showProductFolders"), id: "showProductFolders",
                                  value: Settings.showProductFolders, action: #selector(toggleSetting(_:)))
        let openDDBtn = checkbox(L10n.tr("showOpenDD"), id: "showOpenDD",
                                 value: Settings.showOpenDD, action: #selector(toggleSetting(_:)))
        let openPPBtn = checkbox(L10n.tr("showProvisioning"), id: "showProvisioning",
                                 value: Settings.showProvisioning, action: #selector(toggleSetting(_:)))

        // 行为
        let loginBtn = checkbox(L10n.tr("launchAtLogin"), id: nil,
                                value: Settings.launchAtLogin, action: #selector(launchAtLoginChanged(_:)))
        let dockBtn = checkbox(L10n.tr("showInDock"), id: nil,
                               value: Settings.showInDock, action: #selector(showInDockChanged(_:)))

        // 终端 App（⇧ 点工程时用哪个终端打开目录）
        let installedTerminals = TerminalLauncher.installed()
        let termPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        termPopup.addItem(withTitle: L10n.tr("termAuto"))
        installedTerminals.forEach { termPopup.addItem(withTitle: $0.name) }
        if let idx = installedTerminals.firstIndex(where: { $0.bundleID == Settings.terminalApp }) {
            termPopup.selectItem(at: idx + 1)
        } else {
            termPopup.selectItem(at: 0)
        }
        termPopup.target = self
        termPopup.action = #selector(terminalChanged(_:))
        termPopup.widthAnchor.constraint(equalToConstant: 170).isActive = true
        let termRow = labeledRow(L10n.tr("terminalApp"), termPopup)

        stack.addArrangedSubview(langRow)
        stack.addArrangedSubview(maxRow)
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(sectionHeader(L10n.tr("labelsSection")))
        stack.addArrangedSubview(cleanBtn)
        stack.addArrangedSubview(simsBtn)
        stack.addArrangedSubview(foldersBtn)
        stack.addArrangedSubview(openDDBtn)
        stack.addArrangedSubview(openPPBtn)
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(sectionHeader(L10n.tr("behaviorSection")))
        stack.addArrangedSubview(loginBtn)
        stack.addArrangedSubview(dockBtn)
        stack.addArrangedSubview(termRow)
        stack.addArrangedSubview(NSView())

        for v in stack.arrangedSubviews { v.translatesAutoresizingMaskIntoConstraints = false }
        return stack
    }

    // MARK: 关于

    private func buildAboutTab() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10

        // 头部：图标 + 名称 / 一句话 / 版本
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 56).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let nameLabel = NSTextField(labelWithString: "iXcode")
        nameLabel.font = .systemFont(ofSize: 15, weight: .semibold)

        let tagline = NSTextField(labelWithString: L10n.tr("aboutTagline"))
        tagline.font = .systemFont(ofSize: 11)
        tagline.textColor = .secondaryLabelColor
        tagline.lineBreakMode = .byTruncatingTail

        let versionLabel = NSTextField(labelWithString: "v\(Self.currentVersion)")
        versionLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        versionLabel.textColor = .secondaryLabelColor

        let titleStack = NSStackView(views: [nameLabel, tagline, versionLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2

        let header = NSStackView(views: [icon, titleStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12

        // 链接：仓库 / 协议
        let repoBtn = linkButton(Self.repoName, action: #selector(openRepoPage),
                                 tip: "https://github.com/\(Self.repoName)")
        let licenseBtn = linkButton(L10n.tr("license"), action: #selector(openLicensePage),
                                    tip: "https://github.com/\(Self.repoName)/blob/main/LICENSE")
        let links = NSStackView(views: [repoBtn, dotSeparator(), licenseBtn])
        links.orientation = .horizontal
        links.spacing = 8

        // 更新
        let autoBtn = checkbox(L10n.tr("autoCheckUpdates"), id: "autoCheckUpdates",
                               value: Settings.autoCheckUpdates, action: #selector(autoCheckChanged(_:)))

        let hint = NSTextField(labelWithString: L10n.tr("autoCheckHint"))
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor

        let checkBtn = NSButton(title: L10n.tr("checkUpdates"), target: self, action: #selector(checkUpdatesClicked))
        checkBtn.bezelStyle = .rounded
        checkBtn.controlSize = .small

        let updateStatus = NSTextField(labelWithString: "")
        updateStatus.font = .systemFont(ofSize: 11)
        updateStatus.textColor = .secondaryLabelColor
        updateStatus.lineBreakMode = .byTruncatingTail
        updateStatusLabel = updateStatus

        let installBtn = NSButton(title: L10n.tr("readyInstall"), target: self, action: #selector(installUpdateAndRestart))
        installBtn.bezelStyle = .rounded
        installBtn.controlSize = .small
        installBtn.isHidden = true
        installUpdateBtn = installBtn

        let updateRow = NSStackView(views: [checkBtn, installBtn, updateStatus, NSView()])
        updateRow.orientation = .horizontal
        updateRow.alignment = .centerY
        updateRow.spacing = 8
        updateRow.widthAnchor.constraint(equalToConstant: Self.settingsContentWidth).isActive = true
        (updateRow.arrangedSubviews.last as? NSView)?.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let copyright = NSTextField(labelWithString: L10n.tr("copyright"))
        copyright.font = .systemFont(ofSize: 10)
        copyright.textColor = .tertiaryLabelColor

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(links)
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(sectionHeader(L10n.tr("updatesSection")))
        stack.addArrangedSubview(autoBtn)
        stack.addArrangedSubview(hint)
        stack.addArrangedSubview(updateRow)
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(copyright)
        stack.addArrangedSubview(NSView())

        for v in stack.arrangedSubviews { v.translatesAutoresizingMaskIntoConstraints = false }
        return stack
    }

    // MARK: 小控件

    private func checkbox(_ title: String, id: String?, value: Bool, action: Selector) -> NSButton {
        let btn = NSButton(checkboxWithTitle: title, target: self, action: action)
        btn.state = value ? .on : .off
        if let id { btn.identifier = NSUserInterfaceItemIdentifier(id) }
        return btn
    }

    private func labeledRow(_ title: String, _ control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.widthAnchor.constraint(equalToConstant: Self.settingsContentWidth).isActive = true
        return row
    }

    private func sectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: Self.settingsContentWidth).isActive = true
        return box
    }

    private func dotSeparator() -> NSTextField {
        let dot = NSTextField(labelWithString: "·")
        dot.textColor = .tertiaryLabelColor
        return dot
    }

    private func linkButton(_ title: String, action: Selector, tip: String) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.contentTintColor = .linkColor
        btn.font = .systemFont(ofSize: 11)
        btn.toolTip = tip
        return btn
    }

    // MARK: 动作

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        switch sender.indexOfSelectedItem {
        case 1: Settings.language = "zh-Hans"
        case 2: Settings.language = "en"
        default: Settings.language = "auto"
        }
        // 语言变了：关掉设置面板，下次打开时按新语言重建（记住当前 tab）
        pendingSettingsTab = currentSettingsTab
        settingsWindow?.close()
        settingsWindow = nil
        installMainMenu()   // 主菜单里的「关于 / 设置 / 退出」也要换语言
        showSettings()
    }

    @objc private func maxItemsChanged(_ sender: NSStepper) {
        Settings.maxItems = Int(sender.doubleValue)
        maxItemsLabel?.stringValue = "\(Settings.maxItems)"
    }

    @objc private func toggleSetting(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        Settings.d.set(sender.state == .on, forKey: key)
    }

    @objc private func autoCheckChanged(_ sender: NSButton) {
        Settings.autoCheckUpdates = sender.state == .on
    }

    @objc private func showInDockChanged(_ sender: NSButton) {
        Settings.showInDock = sender.state == .on
        NSApp.setActivationPolicy(Settings.showInDock ? .regular : .accessory)
    }

    @objc private func terminalChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        let installedTerminals = TerminalLauncher.installed()
        if idx >= 1, idx - 1 < installedTerminals.count {
            Settings.terminalApp = installedTerminals[idx - 1].bundleID
        } else {
            Settings.terminalApp = "auto"
        }
    }

    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            // 注册成功但系统要求用户批准时，状态不是 enabled，别让复选框自己变回未勾选
            sender.state = Settings.launchAtLogin ? .on : .off
            if sender.state == .on, SMAppService.mainApp.status == .requiresApproval {
                notify(message: L10n.tr("loginNeedsApproval"))
            }
        } catch {
            sender.state = Settings.launchAtLogin ? .on : .off
            notify(message: L10n.tr("loginFailed", error.localizedDescription))
        }
    }
}
