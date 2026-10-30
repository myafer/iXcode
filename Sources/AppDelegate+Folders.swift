import AppKit

// MARK: - 快捷目录 / 清理 DerivedData

extension AppDelegate {

    /// 「Archives / DeviceSupport」两个入口（状态栏菜单用）
    func populateFolderSection(_ menu: NSMenu) {
        guard Settings.showProductFolders else { return }
        menu.addItem(.separator())
        menu.addItem(actionItem(L10n.tr("openArchives"), #selector(openArchives)))
        menu.addItem(actionItem(L10n.tr("openDeviceSupport"), #selector(openDeviceSupport)))
    }

    /// 「清理 DerivedData（大小）」入口（状态栏菜单用）
    func populateCleanSection(_ menu: NSMenu) {
        guard Settings.showCleanDD else { return }
        menu.addItem(.separator())
        let sizeText = cachedDDSize >= 0 ? ByteFormat.size(cachedDDSize) : L10n.tr("calculating")
        menu.addItem(actionItem("\(L10n.tr("cleanDD"))（\(sizeText)）", #selector(cleanDerivedData)))
    }

    @objc func openDerivedData() {
        NSWorkspace.shared.open(RecentsScanner.derivedDataURL)
    }

    @objc func openProvisioningProfiles() {
        NSWorkspace.shared.open(RecentsScanner.provisioningProfilesURL)
    }

    @objc func openDeviceSupport() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport"))
    }

    @objc func openArchives() {
        openXcodeOrganizer()
    }

    /// 直接拉起 Xcode 的 Organizer（Archives 面板），三层兜底：
    /// ① 用 Xcode 打开最近一个 .xcarchive → Organizer 自动弹出并选中（免权限，首选）
    /// ② AppleScript 点菜单 Organizer（需用户授予自动化权限）
    /// ③ Finder 打开 Archives 文件夹
    func openXcodeOrganizer() {
        let archivesURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Developer/Xcode/Archives")
        guard FileManager.default.fileExists(atPath: "/Applications/Xcode.app") else {
            NSWorkspace.shared.open(archivesURL)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // ① 首选：打开最近的 xcarchive（无权限要求）
            if let archive = RecentsScanner.latestArchiveURL() {
                let conf = NSWorkspace.OpenConfiguration()
                conf.createsNewApplicationInstance = false
                NSWorkspace.shared.open([archive], withApplicationAt:
                    URL(fileURLWithPath: "/Applications/Xcode.app"), configuration: conf)
                return
            }

            // ② 没有任何 archive 时退回 AppleScript 点菜单（菜单名同时匹配中英文）
            let script = """
            tell application "Xcode" to activate
            delay 0.5
            tell application "System Events" to tell process "Xcode"
                repeat with mb in menu bar items of menu bar 1
                    try
                        repeat with mi in menu items of menu 1 of mb
                            set n to name of mi
                            if n is not missing value and (n contains "Organizer" or n contains "组织器") then
                                click mi
                                return
                            end if
                        end repeat
                    end try
                end repeat
            end tell
            error "Organizer menu item not found"
            """
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            let errPipe = Pipe()
            p.standardError = errPipe
            p.standardOutput = Pipe()
            var failed = true
            var errMsg = ""
            do {
                try p.run()
                p.waitUntilExit()
                failed = p.terminationStatus != 0
                if failed {
                    errMsg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                                    encoding: .utf8) ?? ""
                }
            } catch {
                errMsg = error.localizedDescription
            }

            // ③ 全部失败：打开文件夹兜底
            DispatchQueue.main.async {
                if failed {
                    NSLog("[iXcode] Organizer script failed: \(errMsg)")
                    NSWorkspace.shared.open(archivesURL)
                    self?.notify(message: L10n.tr("organizerFallback"))
                }
            }
        }
    }

    // MARK: 清理 DerivedData

    @objc func cleanDerivedData() {
        let size = max(cachedDDSize, 0)
        let sizeText = ByteFormat.size(size)
        guard confirm(title: L10n.tr("cleanConfirmTitle"),
                      body: L10n.tr("cleanConfirmBody", sizeText),
                      button: L10n.tr("clean")) else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            let ddURL = RecentsScanner.derivedDataURL
            if let contents = try? fm.contentsOfDirectory(at: ddURL, includingPropertiesForKeys: nil) {
                for c in contents { try? fm.removeItem(at: c) }
            }
            DispatchQueue.main.async {
                self?.cachedDDSize = 0
                self?.notify(message: L10n.tr("cleanDone", sizeText))
                self?.refreshProjectsAsync()   // DerivedData 清空了，工程列表跟着刷新
            }
        }
    }
}
