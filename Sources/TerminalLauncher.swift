import AppKit

// MARK: - 终端 App 选择（⇧ 点工程时用哪个终端打开目录）

struct TerminalApp {
    let bundleID: String
    let name: String
}

enum TerminalLauncher {

    /// 常见终端（顺序即「自动」模式的优先级：iTerm2 优先，其次系统终端）
    static let known: [TerminalApp] = [
        TerminalApp(bundleID: "com.googlecode.iterm2", name: "iTerm2"),
        TerminalApp(bundleID: "com.apple.Terminal", name: "Terminal"),
        TerminalApp(bundleID: "dev.warp.Warp-Stable", name: "Warp"),
        TerminalApp(bundleID: "com.mitchellh.ghostty", name: "Ghostty"),
        TerminalApp(bundleID: "net.kovidgoyal.kitty", name: "kitty"),
        TerminalApp(bundleID: "com.github.wez.wezterm", name: "WezTerm"),
        TerminalApp(bundleID: "io.alacritty", name: "Alacritty"),
        TerminalApp(bundleID: "co.zeit.hyper", name: "Hyper"),
    ]

    /// 本机已安装的终端（按 known 的顺序）
    static func installed() -> [TerminalApp] {
        known.filter { appURL(bundleID: $0.bundleID) != nil }
    }

    static func appURL(bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// 当前生效的终端：设置里指定且仍安装 → 用它；否则自动挑一个；都没有 → nil（交给系统 open）
    static func resolved() -> TerminalApp? {
        let installedApps = installed()
        let want = Settings.terminalApp
        if want != "auto", let hit = installedApps.first(where: { $0.bundleID == want }) {
            return hit
        }
        return installedApps.first   // known 里 iTerm2 排在前面
    }

    /// 用选定的终端在指定目录打开
    static func open(directory: String) {
        let dirURL = URL(fileURLWithPath: directory)
        if let app = resolved(), let url = appURL(bundleID: app.bundleID) {
            NSWorkspace.shared.open([dirURL], withApplicationAt: url,
                                    configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if error != nil { fallback(directory: directory) }
            }
        } else {
            fallback(directory: directory)
        }
    }

    /// 兜底：`open -a Terminal <dir>`
    private static func fallback(directory: String) {
        DispatchQueue.main.async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", "Terminal", directory]
            try? p.run()
        }
    }
}
