import AppKit

// MARK: - 工程动作（打开 / 置顶 / 搜索）

extension AppDelegate {

    /// 点按工程行的分发：
    /// ⌘ 复制路径 / ⌃ 置顶切换 / ⇧ 终端打开 / ⌥ 或文件已丢失 → Finder 显示 / 其余 → Xcode
    func handleClick(project: RecentProject, event: NSEvent) {
        let flags = event.modifierFlags

        if flags.contains(.command) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(project.path, forType: .string)
            return
        }

        if flags.contains(.control) {
            togglePin(project)
            return
        }

        if flags.contains(.shift) {
            TerminalLauncher.open(directory: project.directory)
            return
        }

        if flags.contains(.option) || !project.exists {
            revealInFinder(path: project.path)
            return
        }

        openInXcode(project.path)
    }

    func openInXcode(_ path: String) {
        let url = URL(fileURLWithPath: path)
        let xcode = URL(fileURLWithPath: "/Applications/Xcode.app")
        guard FileManager.default.fileExists(atPath: xcode.path) else {
            NSWorkspace.shared.open(url)   // 没装 Xcode 就交给系统默认
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: xcode,
                                configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// 在 Finder 中选中该文件（不打开）
    func revealInFinder(path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: (path as NSString).deletingLastPathComponent)
    }

    // MARK: 置顶

    /// 切换置顶状态并立即刷新（菜单开着就原地重建，否则下次打开生效）
    func togglePin(_ project: RecentProject) {
        Settings.pinnedPaths = ProjectPinning.toggled(Settings.pinnedPaths, path: project.path)
        if menuIsOpen, let menu = statusItem.menu {
            rebuild(menu: menu)
        }
    }

    // MARK: 搜索

    @objc func showProjectSearch() {
        if searchController == nil {
            searchController = ProjectSearchController(owner: self)
        }
        searchController?.show(projects: allProjects)
        refreshProjectsAsync()   // 顺手在后台更新一次全量列表
    }
}
