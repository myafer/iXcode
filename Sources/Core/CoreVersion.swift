import Foundation

// MARK: - 语义化版本比较
//
// 纯函数、无副作用，被 App 与单元测试共同编译（Tests/CoreLogicTests.swift）。
// ⚠️ 这里只许放 Foundation 级别的纯逻辑：不要 import AppKit、不要读 Settings/UserDefaults，
//    否则测试 target 会连带把整个 App 状态拖进去。

enum VersionCompare {

    /// 语义化版本比较：a 比 b 新返回 true
    /// 支持的写法："4.5"、"4.10.2"、"v4.6"（v 前缀请先剥掉）、缺位按 0 补（"4.5" == "4.5.0"）
    static func isNewer(_ a: String, than b: String) -> Bool {
        let av = parse(a)
        let bv = parse(b)
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// 把 "v4.10.2" 拆成 [4, 10, 2]；非数字段按 0 处理
    static func parse(_ version: String) -> [Int] {
        var s = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s.split(separator: ".").map { Int($0) ?? 0 }
    }
}
