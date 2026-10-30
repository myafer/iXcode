import AppKit

// MARK: - 设备子菜单懒加载（Application 段平铺应用 + Simulator Action 段）

final class DeviceMenuProvider: NSObject, NSMenuDelegate {
    // 应用列表缓存（udid → apps + 时间戳）。
    // ⚠️ 后台队列负责拉取并写入、主线程负责读取，必须加锁，
    //    否则两个设备的子菜单交替打开时会出现字典并发读写（可能 EXC_BAD_ACCESS）。
    private static var appsCache: [String: (apps: [SimApp], time: Date)] = [:]
    private static let cacheLock = NSLock()
    /// 缓存有效期：过期后先显示旧数据再后台刷新，装了新 App 也能自动跟上
    private static let cacheTTL: TimeInterval = 15

    static func cachedApps(for udid: String) -> (apps: [SimApp], fresh: Bool)? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let hit = appsCache[udid] else { return nil }
        return (hit.apps, Date().timeIntervalSince(hit.time) < cacheTTL)
    }

    static func storeApps(_ apps: [SimApp], for udid: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        appsCache[udid] = (apps, Date())
    }

    static func invalidate(udid: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        appsCache.removeValue(forKey: udid)
    }

    let sim: SimulatorDevice
    weak var owner: AppDelegate?

    init(sim: SimulatorDevice, owner: AppDelegate?) {
        self.sim = sim
        self.owner = owner
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard let cached = Self.cachedApps(for: sim.udid) else {
            buildSkeleton(menu)
            reload(menu)
            return
        }
        fill(menu, apps: cached.apps)
        if !cached.fresh { reload(menu) }   // 旧数据先顶上，后台拉到新的再回填
    }

    /// 后台跑 simctl listapps，回来后原地重建（菜单已关就丢弃结果）
    private func reload(_ menu: NSMenu) {
        let udid = sim.udid
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak menu] in
            let apps = RecentsScanner.listApps(udid: udid)
            Self.storeApps(apps, for: udid)
            DispatchQueue.main.async {
                guard let self, let menu, menu.delegate === self else { return }
                self.fill(menu, apps: apps)
            }
        }
    }

    /// 只搭结构，应用段显示「加载中…」
    private func buildSkeleton(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = NSMenuItem(title: L10n.tr("sectionApps"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let loading = NSMenuItem(title: L10n.tr("appLoading"), action: nil, keyEquivalent: "")
        loading.isEnabled = false
        menu.addItem(loading)

        menu.addItem(.separator())
        addSimActionSection(to: menu)
    }

    private func fill(_ menu: NSMenu, apps: [SimApp]) {
        menu.removeAllItems()

        // ── Application 段：应用平铺，iSimulator 风格行 ──
        let header = NSMenuItem(title: L10n.tr("sectionApps"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if apps.isEmpty {
            let none = NSMenuItem(title: L10n.tr("noApps"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for app in apps {
                let item = NSMenuItem(title: app.displayTitle, action: nil, keyEquivalent: "")
                item.view = AppRowView(app: app)
                let sub = NSMenu()
                sub.autoenablesItems = false
                owner?.buildAppActionsMenu(sub, payload: appPayload(app))
                item.submenu = sub
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // ── Simulator Action 段 ──
        addSimActionSection(to: menu)
    }

    private func addSimActionSection(to menu: NSMenu) {
        let header = NSMenuItem(title: L10n.tr("sectionSimActions"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        owner?.addSimActionItems(to: menu, sim: sim)
    }

    private func appPayload(_ app: SimApp) -> String {
        [sim.udid, app.name, app.bundleID, app.dataPath ?? "", app.bundlePath ?? ""]
            .joined(separator: Self.fieldSep)
    }

    static let fieldSep = "\u{1F}"
}
