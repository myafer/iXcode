import Foundation

// MARK: - 文本 / 资产解析
//
// 纯函数，App 与单元测试共用。

enum TextParsing {

    /// 提取字符串里第一个整数（"iPhone 17 Pro Max" → 17）
    static func firstInteger(in s: String) -> Int {
        var digits = ""
        for ch in s {
            if ch.isNumber { digits.append(ch) }
            else if !digits.isEmpty { break }
        }
        return Int(digits) ?? 0
    }

    /// 提取第一个小数版本号（"iOS 26.3 (...)" → 26.3）
    static func firstVersion(in s: String) -> Double {
        var digits = ""
        for ch in s {
            if ch.isNumber || (ch == "." && !digits.isEmpty) { digits.append(ch) }
            else if !digits.isEmpty { break }
        }
        return Double(digits) ?? 0
    }
}

// MARK: - Release 资产挑选

enum ReleaseAssets {

    /// 更新包优先级：dmg > zip（dmg 是主分发格式，zip 只是给旧版本自动更新兜底）
    static let preference = [".dmg", ".zip"]

    /// 从资产名列表里挑一个，返回原名；都不匹配返回 nil
    static func preferredName(from names: [String]) -> String? {
        for ext in preference {
            if let hit = names.first(where: { $0.lowercased().hasSuffix(ext) }) {
                return hit
            }
        }
        return nil
    }

    /// 从 GitHub release JSON 的 assets 数组里挑下载地址
    static func preferredURL(in assets: [[String: Any]]) -> String? {
        let names = assets.compactMap { $0["name"] as? String }
        guard let pick = preferredName(from: names) else { return nil }
        return assets.first { ($0["name"] as? String) == pick }?["browser_download_url"] as? String
    }

    /// 从 releases.atom 里取最新 tag（不消耗 GitHub API 配额，抗 403 限流）
    static func firstTag(inAtom xml: String) -> String? {
        let marker = "/releases/tag/"
        guard let r = xml.range(of: marker) else { return nil }
        let tag = xml[r.upperBound...].prefix { $0 != "\"" && $0 != "<" && $0 != "'" }
        return tag.isEmpty ? nil : String(tag)
    }
}
