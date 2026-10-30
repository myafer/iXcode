import Foundation

// MARK: - 工程置顶排序
//
// 纯函数，App 与单元测试共用。
// 排序规则：置顶的工程按「置顶顺序」排在最前，其余保持原来的最近访问顺序。

enum ProjectPinning {

    /// - Parameters:
    ///   - projects: 已按最近访问排序的工程
    ///   - pinned: 置顶路径（顺序即展示顺序）
    static func ordered(_ projects: [RecentProject], pinned: [String]) -> [RecentProject] {
        guard !pinned.isEmpty else { return projects }
        let byPath = Dictionary(projects.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [RecentProject] = []
        var seen = Set<String>()
        for path in pinned {
            guard let p = byPath[path], !seen.contains(path) else { continue }
            result.append(p)
            seen.insert(path)
        }
        result.append(contentsOf: projects.filter { !seen.contains($0.path) })
        return result
    }

    /// 切换置顶状态，返回新的置顶数组（新建的置顶排在最前，方便立刻看到）
    static func toggled(_ pinned: [String], path: String) -> [String] {
        if pinned.contains(path) {
            return pinned.filter { $0 != path }
        }
        return [path] + pinned
    }
}
