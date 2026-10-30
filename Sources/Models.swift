import Foundation

// MARK: - 数据模型

struct RecentProject {
    let path: String   // .xcworkspace / .xcodeproj 完整路径
    let date: Date     // LastAccessedDate

    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    /// 显示名：Flutter 工程的 workspace 都叫 Runner，取仓库目录名
    var displayName: String {
        let url = URL(fileURLWithPath: path)
        let docName = url.deletingPathExtension().lastPathComponent
        if docName == "Runner" {
            let parent = url.deletingLastPathComponent()           // .../ios
            let repoName = parent.deletingLastPathComponent().lastPathComponent  // .../echo_2
            if repoName != "ios" && !repoName.isEmpty {
                return repoName
            }
        }
        return docName
    }

    /// 次要信息：相对 ~ 的路径
    var detailPath: String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    var relativeTime: String {
        let fmt = RelativeDateTimeFormatter()
        fmt.locale = Locale.current
        return fmt.localizedString(for: date, relativeTo: Date())
    }

    var directory: String { (path as NSString).deletingLastPathComponent }
}

struct SimulatorDevice {
    let name: String
    let udid: String
    let runtime: String
    let booted: Bool
    var used: Bool = false   // 是否打开过（data/Containers 存在或正在运行）
}

struct SimApp {
    let name: String
    let bundleID: String
    let version: String      // CFBundleShortVersionString，如 "2.0.0"
    let build: String        // CFBundleVersion，如 "1"
    let dataPath: String?
    let bundlePath: String?

    /// "周周学 - 2.0.0(1)" 样式的标题
    var displayTitle: String {
        if version.isEmpty { return name }
        return build.isEmpty ? "\(name) - \(version)" : "\(name) - \(version)(\(build))"
    }
}
