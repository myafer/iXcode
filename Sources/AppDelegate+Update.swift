import AppKit
import UserNotifications

/// 更新流程的轻量错误类型（Result 需要 Error）
struct UpdateError: LocalizedError, CustomStringConvertible {
    let message: String
    var errorDescription: String? { message }
    var description: String { message }
}

extension AppDelegate {

    // MARK: - 自动更新（GitHub Releases）

    /// 所有网络 / 解压工作都在这个后台串行队列上跑。
    /// ⚠️ curl 是同步 Process，绝不能在主线程调用，否则菜单栏会直接转圈。
    static let netQueue = DispatchQueue(label: "com.afer.ixcode.net", qos: .utility)

    static let repoName = "myafer/iXcode"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 语义化版本比较：a > b 返回 true（实现见 Core/VersionCompare，带单元测试）
    static func isNewer(_ a: String, than b: String) -> Bool {
        VersionCompare.isNewer(a, than: b)
    }

    // MARK: - 网络层
    //
    // 不用 URLSession：它会跟随 macOS 系统代理，而不少公司/本地代理对 api.github.com
    // 直接返回 403（github.com 反而必须走代理），connectionProxyDictionary 也管不住它。
    // 这里统一用 /usr/bin/curl，直连/代理两种模式显式指定，行为可预期。

    /// 读取 macOS 系统代理（scutil --proxy），没有则返回 nil
    static func systemProxy() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        p.arguments = ["--proxy"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        func value(_ key: String) -> String? {
            for raw in text.split(separator: "\n") {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard line.hasPrefix(key) else { continue }
                let parts = line.split(separator: ":", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                guard parts.count == 2, parts[1] != "0", !parts[1].isEmpty else { continue }
                return parts[1]
            }
            return nil
        }
        if let host = value("HTTPProxy"), let port = value("HTTPPort") {
            return "http://\(host):\(port)"
        }
        if let host = value("SOCKSProxy"), let port = value("SOCKSPort") {
            return "socks5h://\(host):\(port)"
        }
        return nil
    }

    struct CurlResult {
        let status: Int32
        let httpCode: Int
        let body: Data
        let error: String
        var ok: Bool { status == 0 && (200..<300).contains(httpCode) }
        var failureReason: String {
            if status != 0 {
                return error.isEmpty ? "curl \(status)" : error
            }
            return "HTTP \(httpCode)"
        }
    }

    /// 跑一次 curl：响应体写入文件（默认临时文件），状态码单独取，避免混流
    static func curl(_ url: String, proxy: String?, to dest: URL? = nil, timeout: Int = 30) -> CurlResult {
        let target = dest ?? URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ixcode-curl-\(UUID().uuidString)")
        var args = [
            "-sS", "-L",
            "--connect-timeout", "10",
            "--max-time", "\(timeout)",
            "--retry", "3", "--retry-delay", "1", "--retry-all-errors",
            "-A", "iXcode",
            "-o", target.path,
            "-w", "%{http_code}",
        ]
        if let proxy {
            args += ["-x", proxy]
        } else {
            args += ["--noproxy", "*"]   // 强制直连
        }
        args.append(url)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        p.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do {
            try p.run()
        } catch {
            return CurlResult(status: -1, httpCode: 0, body: Data(), error: error.localizedDescription)
        }
        let codeData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        let code = Int(String(data: codeData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        let body = dest == nil ? (try? Data(contentsOf: target)) ?? Data() : Data()
        if dest == nil { try? FileManager.default.removeItem(at: target) }

        return CurlResult(
            status: p.terminationStatus,
            httpCode: code,
            body: body,
            error: String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    /// 依次尝试（直连 / 系统代理）两条通道，返回第一个成功的响应
    static func fetch(_ url: String, directFirst: Bool, timeout: Int = 30,
                      completion: @escaping (Result<Data, UpdateError>) -> Void) {
        var modes: [String?] = []
        let proxy = systemProxy()
        if let proxy {
            modes = directFirst ? [nil, proxy] : [proxy, nil]
        } else {
            modes = [nil]
        }

        var errors: [String] = []
        func attempt(_ i: Int) {
            guard i < modes.count else {
                completion(.failure(UpdateError(message: errors.joined(separator: " / "))))
                return
            }
            let mode = modes[i]
            let r = curl(url, proxy: mode, timeout: timeout)
            NSLog("[iXcode] GET \(url) via \(mode ?? "direct") -> status=\(r.status) http=\(r.httpCode)")
            if r.ok {
                completion(.success(r.body))
                return
            }
            errors.append("\(mode == nil ? "direct" : "proxy"): \(r.failureReason)")
            attempt(i + 1)
        }
        attempt(0)
    }

    // MARK: - 检查更新

    @objc func checkUpdatesClicked() {
        checkForUpdates(silent: false)
    }

    func checkForUpdates(silent: Bool) {
        if silent && !Settings.autoCheckUpdates { return }   // 用户关了自动检查，启动时不再偷偷跑
        if case .ready = updateState { return }  // 已下载待安装，不用重复检查
        if case .downloading = updateState { return }
        updateErrorMessage = ""
        updateState = .checking

        Self.netQueue.async { [weak self] in
            guard let self else { return }
            Self.fetch("https://api.github.com/repos/\(Self.repoName)/releases/latest", directFirst: true) { result in
                guard case let .success(data) = result else {
                    var apiError = "unknown"
                    if case let .failure(e) = result { apiError = e.message }
                    // API 被限流（403）或不通时，改用不消耗配额的 releases.atom 兜底
                    self.fallbackViaAtom(silent: silent, apiError: apiError)
                    return
                }
                guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    self.fallbackViaAtom(silent: silent, apiError: "bad json")
                    return
                }
                let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                let assets = json["assets"] as? [[String: Any]] ?? []
                // 发布包优先 dmg（也能用 zip 兜底兼容老版本）
                let downloadURL = Self.preferredAssetURL(in: assets)
                guard Self.isNewer(version, than: Self.currentVersion), let downloadURL else {
                    DispatchQueue.main.async { self.updateState = silent ? .idle : .upToDate }
                    return
                }
                DispatchQueue.main.async {
                    self.updateState = .downloading
                    self.downloadUpdate(from: downloadURL, version: version)
                }
            }
        }
    }

    /// 从资产列表里挑更新包：dmg 优先，zip 兜底（实现见 Core/ReleaseAssets，带单元测试）
    static func preferredAssetURL(in assets: [[String: Any]]) -> String? {
        ReleaseAssets.preferredURL(in: assets)
    }

    /// 从 releases.atom 里取最新 tag（不消耗 GitHub API 配额，抗 403 限流）
    static func firstTagInAtom(_ xml: String) -> String? {
        ReleaseAssets.firstTag(inAtom: xml)
    }

    /// API 检查失败时的兜底路径（github.com 常需代理，所以代理优先）
    private func fallbackViaAtom(silent: Bool, apiError: String) {
        let url = "https://github.com/\(Self.repoName)/releases.atom"
        Self.fetch(url, directFirst: false) { [weak self] result in
            guard let self else { return }
            guard case let .success(data) = result,
                  let xml = String(data: data, encoding: .utf8),
                  let tag = Self.firstTagInAtom(xml) else {
                var detail = apiError
                if case let .failure(e) = result { detail += " / atom: \(e.message)" }
                DispatchQueue.main.async {
                    self.updateErrorMessage = detail
                    self.updateState = silent ? .idle : .failed
                }
                return
            }
            let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            guard Self.isNewer(version, than: Self.currentVersion) else {
                DispatchQueue.main.async { self.updateState = silent ? .idle : .upToDate }
                return
            }
            // 资产名遵循发布流水线约定：iXcode-<tag>.dmg
            let dl = "https://github.com/\(Self.repoName)/releases/download/\(tag)/iXcode-\(tag).dmg"
            NSLog("[iXcode] update via atom fallback: \(tag)")
            DispatchQueue.main.async {
                self.updateState = .downloading
                self.downloadUpdate(from: dl, version: version)
            }
        }
    }

    // MARK: - 下载与安装

    private func downloadUpdate(from urlString: String, version: String) {
        Self.netQueue.async { [weak self] in
            guard let self else { return }
            let ext = (urlString as NSString).pathExtension.isEmpty ? "dmg" : (urlString as NSString).pathExtension
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("iXcode-update-\(version)", isDirectory: true)
            let fileURL = tmpDir.appendingPathComponent("iXcode-\(version).\(ext)")
            try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: fileURL)

            // github.com 在多数网络下必须走代理，所以下载代理优先，失败再直连
            let proxy = Self.systemProxy()
            let modes: [String?] = proxy == nil ? [nil] : [proxy, nil]
            var errors: [String] = []

            func attempt(_ i: Int) {
                guard i < modes.count else {
                    let detail = errors.joined(separator: " / ")
                    DispatchQueue.main.async {
                        self.updateErrorMessage = detail
                        self.updateState = .failed
                    }
                    return
                }
                let mode = modes[i]
                let r = Self.curl(urlString, proxy: mode, to: fileURL, timeout: 180)
                NSLog("[iXcode] download via \(mode ?? "direct") -> status=\(r.status) http=\(r.httpCode)")
                let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? Int ?? 0
                if r.ok, size > 0 {
                    self.prepareApp(from: fileURL, tmpDir: tmpDir, version: version)
                    return
                }
                errors.append("\(mode == nil ? "direct" : "proxy"): \(r.failureReason)")
                attempt(i + 1)
            }
            attempt(0)
        }
    }

    /// 跑一个短命子进程，拿退出码和 stderr（供 hdiutil / ditto / unzip 共用）
    @discardableResult
    static func runProcess(_ tool: String, _ args: [String]) -> (status: Int32, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let errPipe = Pipe()
        p.standardError = errPipe
        p.standardOutput = Pipe()
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let err = String(data: errData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (p.terminationStatus, err)
    }

    /// 校验解出来的包能不能用：bundle id 必须和当前 App 一致（防错包/半截包）
    static func validateApp(at path: String, expectedVersion: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return "app missing" }
        guard let b = Bundle(path: path) else { return "unreadable bundle" }
        if let id = b.bundleIdentifier, id != Bundle.main.bundleIdentifier {
            return "bundle id mismatch: \(id)"
        }
        let v = b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard !v.isEmpty else { return "no CFBundleShortVersionString" }
        if v != expectedVersion { NSLog("[iXcode] version in package \(v) != release \(expectedVersion)") }
        return nil
    }

    /// 在目录里找 iXcode.app（不递归太深，dmg 根目录一层就够）
    static func findAppBundle(in dir: URL) -> URL? {
        let fm = FileManager.default
        if let names = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            if let hit = names.first(where: { $0.lastPathComponent == "iXcode.app" }) { return hit }
        }
        guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return nil
        }
        for case let f as URL in e where f.lastPathComponent == "iXcode.app" { return f }
        return nil
    }

    /// 按扩展名分派：dmg 挂载提取 / zip 解压
    private func prepareApp(from fileURL: URL, tmpDir: URL, version: String) {
        if fileURL.pathExtension.lowercased() == "dmg" {
            mountAndExtract(dmg: fileURL, tmpDir: tmpDir, version: version)
        } else {
            unzipAndPrepare(zipURL: fileURL, tmpDir: tmpDir, version: version)
        }
    }

    /// 挂载 dmg → 把里面的 iXcode.app 拷贝到临时目录 → 卸载
    private func mountAndExtract(dmg: URL, tmpDir: URL, version: String) {
        let mountPoint = tmpDir.appendingPathComponent("mnt", isDirectory: true)
        try? FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        let attach = Self.runProcess("/usr/bin/hdiutil", [
            "attach", dmg.path, "-nobrowse", "-noverify", "-readonly", "-quiet",
            "-mountpoint", mountPoint.path,
        ])
        guard attach.status == 0 else {
            DispatchQueue.main.async {
                self.updateErrorMessage = "hdiutil attach \(attach.status): \(attach.err)"
                self.updateState = .failed
            }
            return
        }

        var failure: String?
        var appPath: String?
        if let src = Self.findAppBundle(in: mountPoint) {
            let dst = tmpDir.appendingPathComponent("iXcode.app")
            try? FileManager.default.removeItem(at: dst)
            // ditto 保留符号链接与权限，比 cp -R 可靠
            let copy = Self.runProcess("/usr/bin/ditto", [src.path, dst.path])
            if copy.status != 0 {
                failure = "ditto \(copy.status): \(copy.err)"
            } else if let err = Self.validateApp(at: dst.path, expectedVersion: version) {
                failure = err
            } else {
                appPath = dst.path
            }
        } else {
            failure = "app not found in dmg"
        }

        _ = Self.runProcess("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet", "-force"])
        try? FileManager.default.removeItem(at: mountPoint)
        try? FileManager.default.removeItem(at: dmg)

        DispatchQueue.main.async {
            if let p = appPath {
                self.updateState = .ready(version: version, appPath: p)
                self.notify(message: L10n.tr("newVersionReady", version))
            } else {
                self.updateErrorMessage = failure ?? "unknown"
                self.updateState = .failed
            }
        }
    }

    private func unzipAndPrepare(zipURL: URL, tmpDir: URL, version: String) {
        let r = Self.runProcess("/usr/bin/unzip", ["-o", "-q", zipURL.path, "-d", tmpDir.path])
        guard r.status == 0 else {
            DispatchQueue.main.async {
                self.updateErrorMessage = r.err.isEmpty
                    ? "unzip exit \(r.status) (下载可能不完整)"
                    : "unzip: \(r.err)"
                self.updateState = .failed
            }
            return
        }
        let newApp = Self.findAppBundle(in: tmpDir)
        let invalid = newApp.flatMap { Self.validateApp(at: $0.path, expectedVersion: version) }
        DispatchQueue.main.async {
            if let app = newApp, invalid == nil {
                self.updateState = .ready(version: version, appPath: app.path)
                self.notify(message: L10n.tr("newVersionReady", version))
            } else {
                self.updateErrorMessage = invalid ?? "app not found in zip"
                self.updateState = .failed
            }
        }
    }

    /// 用新包替换当前 App 并重启。
    /// 关键点：先把新包旁路拷成 `<app>.new`，再两步换位；任何一步失败都回滚到原 App，
    /// 避免旧实现里「先 rm -rf 再 cp」在中途失败后 App 直接消失。
    @objc func installUpdateAndRestart() {
        guard case let .ready(_, appPath) = updateState else { return }
        let dst = Bundle.main.bundleURL.path
        let staged = dst + ".new"
        let backup = dst + ".old"
        let logPath = NSTemporaryDirectory() + "ixcode-install.log"
        let script = """
        #!/bin/bash
        exec >> "\(logPath)" 2>&1
        echo "--- $(date)  \(appPath) -> \(dst)"
        sleep 0.8
        rm -rf "\(staged)" "\(backup)"
        if ! /usr/bin/ditto "\(appPath)" "\(staged)"; then
            echo "ditto failed, keeping current app"
            /usr/bin/open "\(dst)"
            exit 1
        fi
        /usr/bin/xattr -dr com.apple.quarantine "\(staged)" 2>/dev/null
        if ! /bin/mv "\(dst)" "\(backup)"; then
            echo "move current aside failed"
            rm -rf "\(staged)"
            /usr/bin/open "\(dst)"
            exit 1
        fi
        if ! /bin/mv "\(staged)" "\(dst)"; then
            echo "swap failed, rolling back"
            /bin/mv "\(backup)" "\(dst)"
            /usr/bin/open "\(dst)"
            exit 1
        fi
        /usr/bin/open "\(dst)"
        rm -rf "\(backup)" "\(appPath)"
        echo "done"
        """
        try? FileManager.default.removeItem(atPath: staged)
        try? FileManager.default.removeItem(atPath: backup)
        let scriptPath = NSTemporaryDirectory() + "ixcode-install.sh"
        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [scriptPath]
            try p.run()
        } catch {
            updateErrorMessage = error.localizedDescription
            updateState = .failed
            return
        }
        exit(0)
    }

    /// 设置面板「关于」区的更新 UI 刷新
    func refreshUpdateUI() {
        guard let label = updateStatusLabel else { return }
        switch updateState {
        case .idle:
            label.stringValue = ""
            label.toolTip = nil
            installUpdateBtn?.isHidden = true
        case .checking:
            label.stringValue = L10n.tr("checkingUpdates")
            label.toolTip = nil
            installUpdateBtn?.isHidden = true
        case .downloading:
            label.stringValue = L10n.tr("downloadingUpdate")
            label.toolTip = nil
            installUpdateBtn?.isHidden = true
        case .upToDate:
            label.stringValue = L10n.tr("upToDate")
            label.toolTip = "v\(Self.currentVersion)"
            installUpdateBtn?.isHidden = true
        case .failed:
            let base = L10n.tr("updateFailed")
            let msg = updateErrorMessage.count > 42
                ? String(updateErrorMessage.prefix(42)) + "…"
                : updateErrorMessage
            label.stringValue = updateErrorMessage.isEmpty ? base : "\(base) · \(msg)"
            label.toolTip = updateErrorMessage
            installUpdateBtn?.isHidden = true
        case .ready(let version, _):
            label.stringValue = "v\(version) ✓"
            label.toolTip = nil
            installUpdateBtn?.title = L10n.tr("readyInstall")
            installUpdateBtn?.isHidden = false
        }
    }

    @objc func openRepoPage() {
        NSWorkspace.shared.open(URL(string: "https://github.com/\(Self.repoName)")!)
    }

    @objc func openLicensePage() {
        NSWorkspace.shared.open(URL(string: "https://github.com/\(Self.repoName)/blob/main/LICENSE")!)
    }
}
