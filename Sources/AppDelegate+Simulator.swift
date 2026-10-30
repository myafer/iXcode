import AppKit

// MARK: - 模拟器（子菜单 / 设备操作 / 模拟器 App 操作）

extension AppDelegate {

    /// simctl 变更类操作串行后台队列（erase / delete 可能耗时数十秒，不能占主线程）
    static let simctlQueue = DispatchQueue(label: "com.afer.ixcode.simctl", qos: .userInitiated)
    static let fieldSeparator = "\u{1F}"

    /// 「模拟器」菜单项（子菜单懒加载：每台设备一个子菜单，点开才查应用列表）
    func simulatorMenuItem() -> NSMenuItem {
        let simItem = NSMenuItem(title: L10n.tr("simulators"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false

        if cachedSimulators.isEmpty && !refreshing {
            let none = NSMenuItem(title: L10n.tr("noSim"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            sub.addItem(none)
            simItem.submenu = sub
            return simItem
        }

        // 运行中的排上面，未运行的排下面，中间分隔
        let bootedSims = cachedSimulators.filter(\.booted)
        let idleSims = cachedSimulators.filter { !$0.booted }
        deviceMenuProviders.removeAll()
        for (index, sim) in (bootedSims + idleSims).enumerated() {
            if index == bootedSims.count && !bootedSims.isEmpty && !idleSims.isEmpty {
                sub.addItem(.separator())
            }
            let title = sim.booted
                ? "🟢 \(sim.name) · \(sim.runtime)"
                : "　 \(sim.name) · \(sim.runtime)"
            let devItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")

            let devSub = NSMenu()
            devSub.autoenablesItems = false
            let provider = DeviceMenuProvider(sim: sim, owner: self)
            devSub.delegate = provider
            deviceMenuProviders.append(provider)
            devItem.submenu = devSub
            sub.addItem(devItem)
        }

        sub.addItem(.separator())
        sub.addItem(actionItem(L10n.tr("openSimApp"), #selector(openSimulatorApp(_:))))
        sub.addItem(actionItem(L10n.tr("shutdownAll"), #selector(simShutdownAll(_:))))
        sub.addItem(actionItem(L10n.tr("createSim"), #selector(simCreate(_:))))
        sub.addItem(actionItem(L10n.tr("deleteUnavailable"), #selector(simDeleteUnavailable(_:))))
        simItem.submenu = sub
        return simItem
    }

    /// 后台执行 simctl，完成后回主线程通知
    func runSimctl(_ args: [String], done: (() -> Void)? = nil) {
        Self.simctlQueue.async {
            RecentsScanner.run(args)
            DispatchQueue.main.async { done?() }
        }
    }

    func fields(_ obj: Any?) -> [String] {
        (obj as? String)?.components(separatedBy: Self.fieldSeparator) ?? []
    }

    func confirm(title: String, body: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: L10n.tr("cancel"))
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 设备子菜单「设备操作」段（启动/关机、数据目录、抹掉、删除）
    func addSimActionItems(to menu: NSMenu, sim: SimulatorDevice) {
        let power = actionItem(L10n.tr(sim.booted ? "simShutdown" : "simBoot"), #selector(simTogglePower(_:)))
        power.representedObject = sim.udid
        menu.addItem(power)

        let data = actionItem(L10n.tr("simData"), #selector(simOpenData(_:)))
        data.representedObject = sim.udid
        menu.addItem(data)

        let erase = actionItem(L10n.tr("simErase"), #selector(simErase(_:)))
        erase.representedObject = "\(sim.udid)\(Self.fieldSeparator)\(sim.name)"
        menu.addItem(erase)

        let delete = actionItem(L10n.tr("simDelete"), #selector(simDelete(_:)))
        delete.representedObject = "\(sim.udid)\(Self.fieldSeparator)\(sim.name)"
        menu.addItem(delete)
    }

    /// 模拟器 App 子菜单（启动 / 沙盒 / Bundle / 卸载）
    func buildAppActionsMenu(_ menu: NSMenu, payload: String) {
        menu.autoenablesItems = false
        let f = payload.components(separatedBy: Self.fieldSeparator)
        guard f.count >= 5 else { return }
        let dataPath = f[3], bundlePath = f[4]

        let launch = actionItem(L10n.tr("launchApp"), #selector(appLaunch(_:)))
        launch.representedObject = payload
        menu.addItem(launch)

        if !dataPath.isEmpty {
            let sandbox = actionItem(L10n.tr("openSandbox"), #selector(appOpenData(_:)))
            sandbox.representedObject = dataPath
            menu.addItem(sandbox)
        }

        if !bundlePath.isEmpty {
            let bundle = actionItem(L10n.tr("openAppBundle"), #selector(appOpenBundle(_:)))
            bundle.representedObject = bundlePath
            menu.addItem(bundle)
        }

        menu.addItem(.separator())

        let uninstall = actionItem(L10n.tr("uninstallApp"), #selector(appUninstall(_:)))
        uninstall.representedObject = payload
        menu.addItem(uninstall)
    }

    // MARK: 设备操作

    @objc func simTogglePower(_ sender: NSMenuItem) {
        guard let udid = sender.representedObject as? String,
              let sim = cachedSimulators.first(where: { $0.udid == udid }) else { return }
        if sim.booted {
            runSimctl(["simctl", "shutdown", udid]) { [weak self] in self?.refreshCachesAsync(force: true) }
        } else {
            RecentsScanner.launch(simulator: sim)
            refreshCachesAsync(force: true)
        }
    }

    @objc func simOpenData(_ sender: NSMenuItem) {
        guard let udid = sender.representedObject as? String else { return }
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(udid)/data")
        NSWorkspace.shared.open(url)
    }

    @objc func simErase(_ sender: NSMenuItem) {
        let f = fields(sender.representedObject)
        guard f.count >= 2 else { return }
        guard confirm(title: L10n.tr("eraseConfirmTitle"),
                      body: L10n.tr("eraseConfirmBody", f[1]),
                      button: L10n.tr("clean")) else { return }
        let udid = f[0], name = f[1]
        Self.simctlQueue.async { [weak self] in
            RecentsScanner.run(["simctl", "shutdown", udid])
            RecentsScanner.run(["simctl", "erase", udid])
            DispatchQueue.main.async {
                DeviceMenuProvider.invalidate(udid: udid)
                self?.notify(message: L10n.tr("eraseDone", name))
                self?.refreshCachesAsync(force: true)
            }
        }
    }

    @objc func simDelete(_ sender: NSMenuItem) {
        let f = fields(sender.representedObject)
        guard f.count >= 2 else { return }
        guard confirm(title: L10n.tr("deleteConfirmTitle"),
                      body: L10n.tr("deleteConfirmBody", f[1]),
                      button: L10n.tr("clean")) else { return }
        let udid = f[0], name = f[1]
        Self.simctlQueue.async { [weak self] in
            RecentsScanner.run(["simctl", "shutdown", udid])
            RecentsScanner.run(["simctl", "delete", udid])
            DispatchQueue.main.async {
                DeviceMenuProvider.invalidate(udid: udid)
                self?.notify(message: L10n.tr("deleteDone", name))
                self?.refreshCachesAsync(force: true)
            }
        }
    }

    @objc func simShutdownAll(_ sender: NSMenuItem) {
        runSimctl(["simctl", "shutdown", "all"]) { [weak self] in
            self?.refreshCachesAsync(force: true)
        }
    }

    @objc func simDeleteUnavailable(_ sender: NSMenuItem) {
        guard confirm(title: L10n.tr("deleteUnavailable"),
                      body: L10n.tr("deleteConfirmBody", L10n.tr("deleteUnavailable")),
                      button: L10n.tr("clean")) else { return }
        runSimctl(["simctl", "delete", "unavailable"]) { [weak self] in
            self?.refreshCachesAsync(force: true)
        }
    }

    @objc func simCreate(_ sender: NSMenuItem) {
        Self.simctlQueue.async { [weak self] in
            let name = RecentsScanner.createIPhoneSimulator()
            DispatchQueue.main.async {
                if let name { self?.notify(message: name) }
                self?.refreshCachesAsync(force: true)
            }
        }
    }

    @objc func openSimulatorApp(_ sender: NSMenuItem) {
        RecentsScanner.launch(simulator: SimulatorDevice(name: "", udid: "", runtime: "", booted: true))
    }

    // MARK: 模拟器 App 操作

    @objc func appLaunch(_ sender: NSMenuItem) {
        let f = fields(sender.representedObject)
        guard f.count >= 3 else { return }
        runSimctl(["simctl", "launch", f[0], f[2]])
    }

    @objc func appOpenData(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String,
              FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc func appOpenBundle(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String,
              FileManager.default.fileExists(atPath: path) else { return }
        // 在 Finder 中显示该目录（而不是打开/启动 App）
        revealInFinder(path: path)
    }

    @objc func appUninstall(_ sender: NSMenuItem) {
        let f = fields(sender.representedObject)
        guard f.count >= 3 else { return }
        guard confirm(title: L10n.tr("uninstallConfirmTitle"),
                      body: L10n.tr("uninstallConfirmBody", f[1]),
                      button: L10n.tr("uninstallApp")) else { return }
        let udid = f[0], bundleID = f[2]
        Self.simctlQueue.async {
            RecentsScanner.run(["simctl", "uninstall", udid, bundleID])
            DispatchQueue.main.async {
                DeviceMenuProvider.invalidate(udid: udid)
            }
        }
    }
}
