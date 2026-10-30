import Foundation

// MARK: - 显示格式化
//
// 纯函数，App 与单元测试共用。

enum ByteFormat {

    /// 人类可读体积："1.2 MB"。locale 固定 en_US_POSIX 之外的 .file 风格，
    /// 保证测试断言稳定（不同系统语言下单位缩写可能变化，因此测试只断言数字与前缀）。
    static func size(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
