import AppKit
import UserNotifications

// MARK: - 状态栏控制器（生命周期 / 缓存刷新）
//
// 代码按职责拆在多个 extension 文件里，新增功能请放进对应文件，别再往这个文件里堆：
//   AppDelegate+Menu.swift       菜单构建（状态栏菜单 / Dock 菜单）
//   AppDelegate+Projects.swift   工程打开动作、置顶、搜索窗口
//   AppDelegate+Folders.swift    快捷目录、清理 DerivedData
//   AppDelegate+Simulator.swift  模拟器与模拟器 App 操作
//   AppDelegate+Settings.swift   设置面板（通用 / 关于）
//   AppDelegate+Update.swift     自动更新（网络 / 下载 / 安装）
//
// ⚠️ extension 不能放「实例」存储属性，所以所有状态都声明在这个类里；
//    跨文件访问的成员不要写 private，方法同理。

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {

    // MARK: 状态栏

    var statusItem: NSStatusItem!

    // MARK: 设置面板

    var settingsWindow: NSWindow?
    /// 语言切换重建窗口时，记录要停留在哪个 tab
    var pendingSettingsTab: Int?
    var maxItemsLabel: NSTextField?
    /// 工程搜索面板（懒加载）
    var searchController: ProjectSearchController?

    // MARK: 异步缓存（主线程只读缓存，扫描/查询一律后台做）

    var cachedDDSize: Int64 = -1
    var cachedSimulators: [SimulatorDevice] = []
    var refreshing = false
    var menuIsOpen = false
    var deviceMenuProviders: [DeviceMenuProvider] = []

    /// 菜单里显示的工程（未应用置顶排序）
    var cachedProjects: [RecentProject] = []
    /// 全量工程（搜索窗口用，不受 maxItems 限制）
    var allProjects: [RecentProject] = []
    var scanningProjects = false
    var lastCacheRefresh = Date.distantPast
    var lastDDSizeRefresh = Date.distantPast

    // MARK: 自动更新状态

    enum UpdateState {
        case idle
        case checking
        case downloading
        case ready(version: String, appPath: String)
        case upToDate
        case failed
    }

    var updateState: UpdateState = .idle {
        didSet {
            if Thread.isMainThread { refreshUpdateUI() }
            else { DispatchQueue.main.async { self.refreshUpdateUI() } }
        }
    }
    /// 上次更新失败的具体原因（显示在设置面板里，方便排查）
    var updateErrorMessage: String = ""
    var updateStatusLabel: NSTextField?
    var installUpdateBtn: NSButton?

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.migrateLegacyDefaultsIfNeeded()   // 改过 bundle id，先把老域设置搬过来
        UNUserNotificationCenter.current().delegate = self
        installMainMenu()   // 主菜单只为了注册 ⌘, / ⌘F / ⌘Q（状态栏菜单里的快捷键只在展开时有效）

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "hammer", accessibilityDescription: "iXcode") {
                button.image = img
            } else {
                button.title = "🔨"
            }
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        rebuild(menu: menu)

        // 后台预热：工程列表 + 体积/模拟器缓存（主线程不做任何磁盘/进程操作）
        refreshProjectsAsync()
        refreshCachesAsync(force: true)

        // 启动 3 秒后静默检查更新，有新版自动下载（可在设置里关闭；内部已切到后台队列）
        if Settings.autoCheckUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.checkForUpdates(silent: true)
            }
        }

        // 调试辅助：`defaults write com.afer.ixcode IXCODE_DEBUG -string search|settings` 后启动，
        // 会直接打开对应面板（UI 验证用；临时设置，用完 `defaults delete` 掉即可）
        switch Settings.d.string(forKey: "IXCODE_DEBUG") {
        case "search":
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.showProjectSearch()
            }
        case "settings":
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.showSettings()
            }
        default:
            break
        }
    }

    /// 真正的主菜单（Dock 模式时菜单栏可见；accessory 模式下不显示，但快捷键照样注册）。
    /// 状态栏菜单上的 keyEquivalent 只有菜单展开时才响应，所以 ⌘, / ⌘F / ⌘Q 必须挂在这里。
    func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()

        let about = NSMenuItem(title: L10n.tr("aboutMenu"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())

        let search = NSMenuItem(title: L10n.tr("searchProjects"), action: #selector(showProjectSearch), keyEquivalent: "f")
        search.target = self
        appMenu.addItem(search)
        appMenu.addItem(.separator())

        let settings = NSMenuItem(title: L10n.tr("settings"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: L10n.tr("quit"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)

        appItem.submenu = appMenu
        main.addItem(appItem)
        NSApp.mainMenu = main
    }

    /// Dock 图标右键 / 长按菜单（仅在 Dock 显示时有效）
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard Settings.showInDock else { return nil }
        refreshProjectsAsync()
        refreshCachesAsync()  // 后台补刷新缓存，下次打开更新
        return buildDockMenu()
    }

    /// Dock 模式下点击图标：打开设置面板
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        rebuild(menu: menu)
        refreshProjectsAsync()
        refreshCachesAsync()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
    }

    // MARK: - 后台刷新

    /// 后台扫描 DerivedData，主线程只做一次换缓存 + 重建菜单
    func refreshProjectsAsync() {
        guard !scanningProjects else { return }
        scanningProjects = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // 一次扫全量：菜单取前 maxItems，搜索窗口用全量，避免打开搜索时再扫一次盘
            let all = RecentsScanner.scan(limit: 500)
            let limited = Array(all.prefix(Settings.maxItems))
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanningProjects = false
                guard all.map(\.path) != self.allProjects.map(\.path) else { return }
                self.allProjects = all
                self.cachedProjects = limited
                self.searchController?.update(projects: all)
                if self.menuIsOpen, let menu = self.statusItem.menu {
                    self.rebuild(menu: menu)
                }
            }
        }
    }

    /// 后台刷新体积 / 模拟器缓存，完成后若菜单还开着则重建一次
    /// - Parameter force: 忽略节流（启动时预热用）
    func refreshCachesAsync(force: Bool = false) {
        // 节流：1.5 秒内不重复触发，避免反复开关菜单堆积 I/O
        let now = Date()
        if !force, now.timeIntervalSince(lastCacheRefresh) < 1.5 { return }
        guard !refreshing else { return }
        refreshing = true
        lastCacheRefresh = now
        // DerivedData 体积遍历整棵树，开销大：60 秒内的结果直接复用
        let needDDSize = force || now.timeIntervalSince(lastDDSizeRefresh) > 60
        if needDDSize { lastDDSizeRefresh = now }
        let prevSize = cachedDDSize   // 主线程取快照，后台不要再去读这个属性
        let wantSims = Settings.showSims

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let size = needDDSize ? RecentsScanner.derivedDataSize() : prevSize
            let sims = wantSims ? RecentsScanner.listSimulators() : []
            DispatchQueue.main.async {
                self.refreshing = false
                let sizeChanged = size != self.cachedDDSize
                let simsChanged = sims.map(\.udid) != self.cachedSimulators.map(\.udid)
                    || sims.map(\.booted) != self.cachedSimulators.map(\.booted)
                self.cachedDDSize = size
                self.cachedSimulators = sims
                if (sizeChanged || simsChanged), self.menuIsOpen, let menu = self.statusItem.menu {
                    self.rebuild(menu: menu)
                }
            }
        }
    }

    // MARK: - 通知

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// 通知授权结果（第一次请求后缓存，避免每条通知都走一遍 requestAuthorization）
    private var notificationGranted: Bool?

    func notify(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "iXcode"
        content.body = message

        func post() {
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            )
        }

        switch notificationGranted {
        case .some(true):
            post()
        case .some(false):
            return            // 用户已拒绝，不再反复请求（系统也不会再弹框）
        case .none:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { [weak self] granted, _ in
                DispatchQueue.main.async { self?.notificationGranted = granted }
                guard granted else { return }
                post()
            }
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}
