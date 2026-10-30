import Foundation
import ServiceManagement

// MARK: - 设置存取

enum Settings {
    static let d = UserDefaults.standard

    /// 4.1 起 bundle id 由 com.jojo.ixcode 改为 com.afer.ixcode，UserDefaults 域随之变化。
    /// 首次启动时把老域里的设置搬过来，避免升级后设置全丢（只搬一次，新域已有值就不动）。
    private static var didMigrate = false
    private static let legacyDomain = "com.jojo.ixcode"
    private static let migratedKeys = [
        "maxItems", "language", "showCleanDD", "showSims", "showProductFolders", "showInDock",
        "autoCheckUpdates", "showOpenDD", "showProvisioning", "pinnedPaths", "terminalApp",
    ]

    static func migrateLegacyDefaultsIfNeeded() {
        guard !didMigrate else { return }
        didMigrate = true
        // 新域已有任意一个键 = 不是首次运行，说明本来就是新装的，不用搬
        guard !migratedKeys.contains(where: { d.object(forKey: $0) != nil }) else { return }
        guard let legacy = UserDefaults(suiteName: legacyDomain) else { return }
        var copied = 0
        for key in migratedKeys where d.object(forKey: key) == nil {
            if let value = legacy.object(forKey: key) {
                d.set(value, forKey: key)
                copied += 1
            }
        }
        if copied > 0 {
            NSLog("[iXcode] migrated \(copied) setting(s) from \(legacyDomain)")
        }
    }

    static var maxItems: Int {
        get { d.object(forKey: "maxItems") as? Int ?? 15 }
        set { d.set(newValue, forKey: "maxItems") }
    }

    /// "auto" | "zh-Hans" | "en"
    static var language: String {
        get { d.string(forKey: "language") ?? "auto" }
        set { d.set(newValue, forKey: "language") }
    }

    /// 开机自启：已启用或等待用户在系统设置里批准，都算「开着」
    static var launchAtLogin: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    static var showCleanDD: Bool {
        get { d.object(forKey: "showCleanDD") as? Bool ?? true }
        set { d.set(newValue, forKey: "showCleanDD") }
    }

    static var showSims: Bool {
        get { d.object(forKey: "showSims") as? Bool ?? true }
        set { d.set(newValue, forKey: "showSims") }
    }

    static var showProductFolders: Bool {
        get { d.object(forKey: "showProductFolders") as? Bool ?? true }
        set { d.set(newValue, forKey: "showProductFolders") }
    }

    /// 在 Dock 栏显示图标（默认隐藏，仅菜单栏常驻）
    static var showInDock: Bool {
        get { d.bool(forKey: "showInDock") }
        set { d.set(newValue, forKey: "showInDock") }
    }

    /// 启动时自动检查更新（关闭后仍可手动点「检查更新」）
    static var autoCheckUpdates: Bool {
        get { d.object(forKey: "autoCheckUpdates") as? Bool ?? true }
        set { d.set(newValue, forKey: "autoCheckUpdates") }
    }

    /// 显示「打开 DerivedData 文件夹」菜单项
    static var showOpenDD: Bool {
        get { d.object(forKey: "showOpenDD") as? Bool ?? true }
        set { d.set(newValue, forKey: "showOpenDD") }
    }

    /// 显示「打开描述文件文件夹」菜单项
    static var showProvisioning: Bool {
        get { d.object(forKey: "showProvisioning") as? Bool ?? true }
        set { d.set(newValue, forKey: "showProvisioning") }
    }

    /// 置顶的工程路径（顺序即展示顺序，存在最前面）
    static var pinnedPaths: [String] {
        get { d.stringArray(forKey: "pinnedPaths") ?? [] }
        set { d.set(newValue, forKey: "pinnedPaths") }
    }

    /// ⇧ 打开工程时用的终端：`auto` 或终端 App 的 bundle id
    static var terminalApp: String {
        get { d.string(forKey: "terminalApp") ?? "auto" }
        set { d.set(newValue, forKey: "terminalApp") }
    }
}
