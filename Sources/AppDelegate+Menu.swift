import AppKit

// MARK: - 菜单构建（状态栏菜单 / Dock 菜单）

extension AppDelegate {

    /// 状态栏菜单：每次打开都整体重建（只读缓存，不做任何磁盘/进程操作）
    func rebuild(menu: NSMenu) {
        menu.removeAllItems()

        let projects = ProjectPinning.ordered(cachedProjects, pinned: Settings.pinnedPaths)
        let pinnedSet = Set(Settings.pinnedPaths)

        // ── 工程列表 ──
        let header = NSMenuItem(title: L10n.tr("header"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if projects.isEmpty {
            let title = scanningProjects ? L10n.tr("appLoading") : L10n.tr("empty")
            let empty = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        for project in projects {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.view = ProjectRowView(
                project: project,
                pinned: pinnedSet.contains(project.path),
                onClick: { [weak self] p, event in
                    menu.cancelTracking()
                    self?.handleClick(project: p, event: event)
                },
                onTogglePin: { [weak self] p in
                    self?.togglePin(p)
                }
            )
            menu.addItem(item)
        }

        // 操作提示：属于工程列表的说明，紧跟在列表底部
        if !projects.isEmpty {
            menu.addItem(hintItem())
        }

        // ── 模拟器 ──
        if Settings.showSims {
            menu.addItem(.separator())
            menu.addItem(simulatorMenuItem())
        }

        // ── 文件夹快捷入口 ──
        populateFolderSection(menu)

        // ── 清理 DerivedData ──
        populateCleanSection(menu)

        // ── 其他入口 ──
        if Settings.showProvisioning || Settings.showOpenDD {
            menu.addItem(.separator())
            if Settings.showProvisioning {
                menu.addItem(actionItem(L10n.tr("openPP"), #selector(openProvisioningProfiles)))
            }
            if Settings.showOpenDD {
                menu.addItem(actionItem(L10n.tr("openDD"), #selector(openDerivedData)))
            }
        }

        // ── 有已下载的新版本：菜单里直接给安装入口，不用先开设置面板 ──
        if case let .ready(version, _) = updateState {
            menu.addItem(.separator())
            menu.addItem(actionItem(L10n.tr("readyInstallVersion", version), #selector(installUpdateAndRestart)))
        }

        menu.addItem(.separator())
        menu.addItem(actionItem(L10n.tr("searchProjects"), #selector(showProjectSearch)))
        menu.addItem(actionItem(L10n.tr("settings"), #selector(showSettings), key: ","))
        menu.addItem(actionItem(L10n.tr("quit"), #selector(quit), key: "q"))
    }

    /// 建一条指向 self 的菜单项（省掉到处重复 target / isEnabled 三行）
    func actionItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = true
        return item
    }

    /// 「点按 = Xcode ⌥ = Finder ⌘ = 复制路径 ⇧ = 终端 ⌃ = 置顶」这行小字，
    /// 只作为工程列表的操作说明，放在列表正下方
    func hintItem() -> NSMenuItem {
        let hint = NSMenuItem(title: L10n.tr("hint"), action: nil, keyEquivalent: "")
        hint.isEnabled = false
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        hint.attributedTitle = NSAttributedString(
            string: L10n.tr("hint"),
            attributes: [.font: NSFont.systemFont(ofSize: 9.5), .paragraphStyle: p,
                         .foregroundColor: NSColor.secondaryLabelColor]
        )
        return hint
    }

    // MARK: Dock 右键菜单（纯文本条目，不用自定义视图：Dock 菜单不支持双行自定义视图）

    func buildDockMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let projects = ProjectPinning.ordered(cachedProjects, pinned: Settings.pinnedPaths)
        let pinnedSet = Set(Settings.pinnedPaths)
        if !projects.isEmpty {
            for project in projects {
                let isPinned = pinnedSet.contains(project.path)
                let item = NSMenuItem(
                    title: "\(project.displayName) · \(project.detailPath)（\(project.relativeTime)）",
                    action: #selector(dockOpenProject(_:)), keyEquivalent: ""
                )
                // 置顶项用模板图钉，非置顶项留等宽透明占位，保证菜单标题缩进一致
                item.image = isPinned
                    ? PinMark.image(pointSize: 11)
                    : NSImage(size: NSSize(width: PinMark.slotWidth + 2, height: 11))
                item.target = self
                item.representedObject = project.path
                item.isEnabled = true
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        if Settings.showSims && !cachedSimulators.isEmpty {
            let bootedSims = cachedSimulators.filter(\.booted)
            let idleSims = cachedSimulators.filter { !$0.booted }
            for (index, sim) in (bootedSims + idleSims).enumerated() {
                if index == bootedSims.count && !bootedSims.isEmpty && !idleSims.isEmpty {
                    menu.addItem(.separator())
                }
                let title = sim.booted
                    ? "🟢 \(sim.name) · \(sim.runtime)"
                    : "　 \(sim.name) · \(sim.runtime)"
                let item = NSMenuItem(title: title, action: #selector(dockLaunchSimulator(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = sim.udid
                item.isEnabled = true
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        if Settings.showCleanDD {
            let sizeText = cachedDDSize >= 0 ? ByteFormat.size(cachedDDSize) : L10n.tr("calculating")
            let clean = NSMenuItem(
                title: "\(L10n.tr("cleanDD"))（\(sizeText)）",
                action: #selector(cleanDerivedData), keyEquivalent: ""
            )
            clean.target = self
            clean.isEnabled = true
            menu.addItem(clean)
            menu.addItem(.separator())
        }

        if Settings.showProvisioning || Settings.showOpenDD {
            if Settings.showProvisioning {
                menu.addItem(actionItem(L10n.tr("openPP"), #selector(openProvisioningProfiles)))
            }
            if Settings.showOpenDD {
                menu.addItem(actionItem(L10n.tr("openDD"), #selector(openDerivedData)))
            }
        }

        if Settings.showProductFolders {
            menu.addItem(actionItem(L10n.tr("openArchives"), #selector(openArchives)))
            menu.addItem(actionItem(L10n.tr("openDeviceSupport"), #selector(openDeviceSupport)))
        }

        menu.addItem(.separator())
        menu.addItem(actionItem(L10n.tr("searchProjects"), #selector(showProjectSearch)))
        menu.addItem(actionItem(L10n.tr("settings"), #selector(showSettings)))
        menu.addItem(actionItem(L10n.tr("quit"), #selector(quit)))

        return menu
    }

    @objc func dockOpenProject(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        if FileManager.default.fileExists(atPath: path) {
            openInXcode(path)
        } else {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: (path as NSString).deletingLastPathComponent)
        }
    }

    @objc func dockLaunchSimulator(_ sender: NSMenuItem) {
        guard let udid = sender.representedObject as? String,
              let sim = cachedSimulators.first(where: { $0.udid == udid }) else { return }
        RecentsScanner.launch(simulator: sim)
    }
}
