import AppKit

// MARK: - 扫描 / 系统查询

enum RecentsScanner {
    /// 扫描 DerivedData 得到最近的工程列表
    /// - Parameter limit: 最多返回多少条；nil = 用设置里的 maxItems（搜索窗口会传更大的值）
    static func scan(limit: Int? = nil) -> [RecentProject] {
        let derivedDataURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: derivedDataURL, includingPropertiesForKeys: nil
        ) else { return [] }

        // 按 WorkspacePath 去重，保留最近访问的一条
        var best: [String: RecentProject] = [:]

        for entry in entries {
            let infoURL = entry.appendingPathComponent("info.plist")
            guard let data = try? Data(contentsOf: infoURL),
                  let plist = try? PropertyListSerialization.propertyList(
                      from: data, options: [], format: nil
                  ) as? [String: Any],
                  let path = plist["WorkspacePath"] as? String
            else { continue }

            var date = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if let d = plist["LastAccessedDate"] as? Date { date = d }

            let project = RecentProject(path: path, date: date)
            if let old = best[path], old.date >= project.date { continue }
            best[path] = project
        }

        return best.values
            .sorted { $0.date > $1.date }
            .prefix(limit ?? Settings.maxItems)
            .map { $0 }
    }

    /// 描述文件目录（优先 Xcode UserData，其次 MobileDevice）
    static var provisioningProfilesURL: URL {
        let candidates = [
            NSHomeDirectory() + "/Library/Developer/Xcode/UserData/Provisioning Profiles",
            NSHomeDirectory() + "/Library/MobileDevice/Provisioning Profiles",
        ]
        for c in candidates where FileManager.default.fileExists(atPath: c) {
            return URL(fileURLWithPath: c)
        }
        return URL(fileURLWithPath: candidates[0])
    }

    static var derivedDataURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
    }

    /// 最近一次打包的 .xcarchive（用 Xcode 打开它会直接弹出 Organizer 并选中它）
    /// 目录结构：Archives/<yyyy-MM-dd>/<name>.xcarchive，只做两层浅遍历，开销极小
    static func latestArchiveURL() -> URL? {
        let archivesURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Developer/Xcode/Archives")
        let fm = FileManager.default
        guard let dayDirs = try? fm.contentsOfDirectory(
            at: archivesURL, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }

        var latest: (url: URL, date: Date)? = nil
        for day in dayDirs {
            guard let archives = try? fm.contentsOfDirectory(
                at: day, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }
            for a in archives where a.pathExtension == "xcarchive" {
                let date = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                if latest == nil || date > latest!.date { latest = (a, date) }
            }
        }
        return latest?.url
    }

    // MARK: DerivedData 体积

    static func derivedDataSize() -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: derivedDataURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let vals = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               vals.isRegularFile == true {
                total += Int64(vals.fileSize ?? 0)
            }
        }
        return total
    }

    /// 人类可读体积（实现见 Core/ByteFormat，这里保留调用入口给旧代码用）
    static func formatSize(_ bytes: Int64) -> String {
        ByteFormat.size(bytes)
    }

    // MARK: 模拟器

    static func listSimulators() -> [SimulatorDevice] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "available"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        let regex = try? NSRegularExpression(pattern:
            #"^\s+(.+?) \(([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\) \(([^)]+)\)"#)
        guard let regex else { return [] }

        var runtime = ""
        var result: [SimulatorDevice] = []
        for line in output.split(separator: "\n") {
            let s = String(line)
            if s.hasPrefix("-- ") {
                runtime = s.trimmingCharacters(in: CharacterSet(charactersIn: "- "))
                continue
            }
            guard runtime.hasPrefix("iOS"),
                  let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let nameRange = Range(m.range(at: 1), in: s),
                  let udidRange = Range(m.range(at: 2), in: s),
                  let stateRange = Range(m.range(at: 3), in: s)
            else { continue }
            let udid = String(s[udidRange])
            let booted = s[stateRange] == "Booted"
            // 「打开过」判定：正在运行，或 data/Containers 存在（首次启动才会生成）
            let dataDir = NSHomeDirectory() + "/Library/Developer/CoreSimulator/Devices/\(udid)/data"
            let used = booted || FileManager.default.fileExists(atPath: dataDir + "/Containers")
            result.append(SimulatorDevice(
                name: String(s[nameRange]),
                udid: udid,
                runtime: runtime,
                booted: booted,
                used: used
            ))
        }
        // 只显示打开过的模拟器，从未启动过的不列出
        return result.filter { $0.used }
    }

    static func launch(simulator: SimulatorDevice) {
        if !simulator.booted {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["simctl", "boot", simulator.udid]
            try? process.run()
        }
        let simulatorApp = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app")
        if FileManager.default.fileExists(atPath: simulatorApp.path) {
            NSWorkspace.shared.open(simulatorApp)
        } else {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", "Simulator"]
            try? p.run()
        }
    }

    // MARK: simctl 封装

    static func run(_ args: [String]) -> (output: String?, code: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return (nil, -1) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(data: data, encoding: .utf8), process.terminationStatus)
    }

    /// 列出模拟器上的用户应用
    static func listApps(udid: String) -> [SimApp] {
        guard let output = run(["simctl", "listapps", udid]).output,
              let data = output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ) as? [String: [String: Any]]
        else { return [] }

        var apps: [SimApp] = []
        for (bundleID, info) in plist {
            guard (info["ApplicationType"] as? String) == "User" else { continue }
            let name = (info["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String) ?? bundleID
            let version = (info["CFBundleShortVersionString"] as? String) ?? ""
            let build = (info["CFBundleVersion"] as? String) ?? ""
            let dataPath = (info["DataContainer"] as? String).flatMap(URL.init(string:))?.path
            let bundlePath = (info["Bundle"] as? String).flatMap(URL.init(string:))?.path
            apps.append(SimApp(name: name, bundleID: bundleID, version: version, build: build,
                               dataPath: dataPath, bundlePath: bundlePath))
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// 从模拟器 .app 包读取真实 App 图标（NSWorkspace.icon 对模拟器包会返回"禁止"占位图）
    /// ⚠️ 会读盘 + 解码 PNG，不要在菜单填充的主线程里对每个应用调用，走 `loadAppIcon`。
    static func appIcon(fromBundlePath bundlePath: String) -> NSImage? {
        let fm = FileManager.default
        let infoURL = URL(fileURLWithPath: bundlePath).appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = (try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil)) as? [String: Any]
        else { return nil }

        // 收集候选图标名：CFBundleIcons → CFBundleIconFiles → CFBundleIconFile
        var names: [String] = []
        if let primary = (plist["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            names.append(contentsOf: files)
        }
        if let files = plist["CFBundleIconFiles"] as? [String] { names.append(contentsOf: files) }
        if let file = plist["CFBundleIconFile"] as? String { names.append(file) }

        var best: NSImage? = nil
        var bestW = 0
        for raw in names {
            let base = (raw as NSString).deletingPathExtension
            for candidate in ["\(base)@3x.png", "\(base)@2x.png", "\(base).png", base] {
                let p = URL(fileURLWithPath: bundlePath).appendingPathComponent(candidate).path
                guard fm.fileExists(atPath: p), let img = NSImage(contentsOfFile: p) else { continue }
                if Int(img.size.width) > bestW { bestW = Int(img.size.width); best = img }
                break
            }
        }

        // 兜底：包根目录下找最大的 *icon*.png
        if best == nil, let entries = try? fm.contentsOfDirectory(atPath: bundlePath) {
            for e in entries where e.lowercased().contains("icon") && e.hasSuffix(".png") {
                let p = URL(fileURLWithPath: bundlePath).appendingPathComponent(e).path
                if let img = NSImage(contentsOfFile: p), Int(img.size.width) > bestW {
                    bestW = Int(img.size.width); best = img
                }
            }
        }
        return best
    }

    // MARK: 图标缓存（跨线程安全）

    private static var iconCache: [String: NSImage] = [:]
    private static let iconCacheLock = NSLock()

    static func cachedAppIcon(bundlePath: String) -> NSImage? {
        iconCacheLock.lock()
        defer { iconCacheLock.unlock() }
        return iconCache[bundlePath]
    }

    /// 带缓存的图标读取；可在后台线程调用
    static func loadAppIcon(bundlePath: String) -> NSImage? {
        if let hit = cachedAppIcon(bundlePath: bundlePath) { return hit }
        var img = appIcon(fromBundlePath: bundlePath)
        if img == nil, FileManager.default.fileExists(atPath: bundlePath) {
            img = NSWorkspace.shared.icon(forFile: bundlePath)
        }
        if let img {
            iconCacheLock.lock()
            iconCache[bundlePath] = img
            iconCacheLock.unlock()
        }
        return img
    }

    /// 新建一台最新款 iPhone 模拟器并启动，返回设备名
    static func createIPhoneSimulator() -> String? {
        guard let dtOutput = run(["simctl", "list", "devicetypes"]).output,
              let rtOutput = run(["simctl", "list", "runtimes"]).output else { return nil }

        // 选名字里版本号最大的 iPhone 机型
        let devTypes = dtOutput.split(separator: "\n").filter { $0.contains("iPhone") }
        var bestType: (name: String, id: String)? = nil
        var bestNum = -1
        for line in devTypes {
            guard let open = line.lastIndex(of: "(") else { continue }
            let id = String(line[line.index(after: open)..<line.index(before: line.endIndex)])
            let name = String(line[..<open]).trimmingCharacters(in: .whitespaces)
            let num = Self.firstInteger(in: name)
            if num >= bestNum {
                bestNum = num
                bestType = (name, id)
            }
        }
        // 选版本号最高的 iOS runtime
        var bestRuntime: String? = nil
        var bestVersion = 0.0
        for line in rtOutput.split(separator: "\n") where line.contains("SimRuntime.iOS") {
            guard let id = line.split(separator: " - ").last.map(String.init) else { continue }
            let ver = Self.firstVersion(in: String(line))
            if ver >= bestVersion {
                bestVersion = ver
                bestRuntime = id
            }
        }
        guard let type = bestType, let runtime = bestRuntime else { return nil }

        let name = "\(type.name) (iXcode)"
        let (output, code) = run(["simctl", "create", name, type.id, runtime])
        guard code == 0, let udid = output?.trimmingCharacters(in: .whitespacesAndNewlines), !udid.isEmpty else {
            return nil
        }
        run(["simctl", "boot", udid])
        return name
    }

    /// 提取字符串里第一个整数（"iPhone 17 Pro Max" → 17）
    static func firstInteger(in s: String) -> Int {
        TextParsing.firstInteger(in: s)
    }

    /// 提取第一个小数版本号（"iOS 26.3 (...)" → 26.3）
    static func firstVersion(in s: String) -> Double {
        TextParsing.firstVersion(in: s)
    }
}
