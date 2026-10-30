import XCTest
import Foundation

// MARK: - 核心逻辑单元测试
//
// 这些用例只覆盖 Sources/Core 里的纯函数（外加 Models.swift 的命名逻辑），
// 测试 target 不挂 App 宿主，所以不会启动菜单栏 App，能在 CI 上无头运行：
//
//   xcodebuild test -project iXcode.xcodeproj -scheme iXcode -destination 'platform=macOS'
//
// 加新用例的原则：只测「输入 → 输出」确定的逻辑；碰 NSWorkspace / simctl / UserDefaults 的不要放这里。

final class CoreLogicTests: XCTestCase {

    // MARK: 版本比较

    func testVersionIsNewer() {
        XCTAssertTrue(VersionCompare.isNewer("4.10", than: "4.9"), "按段比较，4.10 要大于 4.9")
        XCTAssertTrue(VersionCompare.isNewer("5", than: "4.99"))
        XCTAssertTrue(VersionCompare.isNewer("4.6.1", than: "4.6"))
        XCTAssertTrue(VersionCompare.isNewer("v4.6", than: "4.5"), "v 前缀要能剥掉")
        XCTAssertFalse(VersionCompare.isNewer("4.5", than: "4.5"))
        XCTAssertFalse(VersionCompare.isNewer("4.5", than: "4.5.0"), "缺位按 0 补，不算更新")
        XCTAssertFalse(VersionCompare.isNewer("4.4", than: "4.5"))
    }

    func testVersionParse() {
        XCTAssertEqual(VersionCompare.parse("v4.10.2"), [4, 10, 2])
        XCTAssertEqual(VersionCompare.parse(" 4.6 "), [4, 6])
        XCTAssertEqual(VersionCompare.parse("4.x.1"), [4, 0, 1], "非数字段按 0 处理")
    }

    // MARK: Release 资产挑选

    func testPreferredAssetPicksDMGFirst() {
        let names = ["iXcode-v4.6.zip", "iXcode-v4.6.dmg", "iXcode-v4.6.sha256"]
        XCTAssertEqual(ReleaseAssets.preferredName(from: names), "iXcode-v4.6.dmg")
    }

    func testPreferredAssetFallsBackToZip() {
        XCTAssertEqual(ReleaseAssets.preferredName(from: ["iXcode-v4.6.zip"]), "iXcode-v4.6.zip")
        XCTAssertNil(ReleaseAssets.preferredName(from: ["notes.txt"]))
        XCTAssertNil(ReleaseAssets.preferredName(from: []))
    }

    func testPreferredAssetURLMatchesName() {
        let assets: [[String: Any]] = [
            ["name": "iXcode-v4.6.zip", "browser_download_url": "https://example.com/a.zip"],
            ["name": "iXcode-v4.6.dmg", "browser_download_url": "https://example.com/a.dmg"],
        ]
        XCTAssertEqual(ReleaseAssets.preferredURL(in: assets), "https://example.com/a.dmg")
    }

    func testFirstTagInAtom() {
        let xml = """
        <feed><entry><link href="https://github.com/myafer/iXcode/releases/tag/v4.6"/></entry></feed>
        """
        XCTAssertEqual(ReleaseAssets.firstTag(inAtom: xml), "v4.6")
        XCTAssertNil(ReleaseAssets.firstTag(inAtom: "<feed></feed>"))
    }

    // MARK: 文本解析

    func testFirstInteger() {
        XCTAssertEqual(TextParsing.firstInteger(in: "iPhone 17 Pro Max"), 17)
        XCTAssertEqual(TextParsing.firstInteger(in: "iPhone SE"), 0)
        XCTAssertEqual(TextParsing.firstInteger(in: "iPhone 16e"), 16)
    }

    func testFirstVersion() {
        XCTAssertEqual(TextParsing.firstVersion(in: "iOS 26.3 (23N123)"), 26.3, accuracy: 0.0001)
        XCTAssertEqual(TextParsing.firstVersion(in: "no version"), 0, accuracy: 0.0001)
    }

    // MARK: 体积格式化

    func testByteFormat() {
        XCTAssertTrue(ByteFormat.size(1024 * 1024).contains("MB"))
        XCTAssertFalse(ByteFormat.size(0).isEmpty)
    }

    // MARK: 置顶排序

    private func project(_ path: String, minute: Int) -> RecentProject {
        RecentProject(path: path, date: Date(timeIntervalSince1970: Double(minute) * 60))
    }

    func testPinnedProjectsGoFirstInPinOrder() {
        let list = [
            project("/tmp/a.xcodeproj", minute: 30),
            project("/tmp/b.xcodeproj", minute: 20),
            project("/tmp/c.xcodeproj", minute: 10),
        ]
        let order = ProjectPinning.ordered(list, pinned: ["/tmp/c.xcodeproj", "/tmp/a.xcodeproj"])
        XCTAssertEqual(order.map(\.path), ["/tmp/c.xcodeproj", "/tmp/a.xcodeproj", "/tmp/b.xcodeproj"])
    }

    func testPinnedIgnoresUnknownAndDuplicatePaths() {
        let list = [project("/tmp/a.xcodeproj", minute: 1)]
        let order = ProjectPinning.ordered(list, pinned: ["/tmp/gone.xcodeproj", "/tmp/a.xcodeproj", "/tmp/a.xcodeproj"])
        XCTAssertEqual(order.map(\.path), ["/tmp/a.xcodeproj"])
    }

    func testTogglePin() {
        XCTAssertEqual(ProjectPinning.toggled([], path: "/tmp/a"), ["/tmp/a"])
        XCTAssertEqual(ProjectPinning.toggled(["/tmp/a"], path: "/tmp/a"), [])
        XCTAssertEqual(ProjectPinning.toggled(["/tmp/a"], path: "/tmp/b"), ["/tmp/b", "/tmp/a"],
                       "新置顶的排最前")
    }

    // MARK: 工程命名

    func testFlutterRunnerUsesRepoName() {
        // Flutter 的 iOS 壳都叫 Runner，得用仓库目录名区分
        let p = RecentProject(path: "/Users/x/code/echo_2/ios/Runner.xcworkspace", date: Date())
        XCTAssertEqual(p.displayName, "echo_2")
    }

    func testNormalProjectKeepsName() {
        let p = RecentProject(path: "/Users/x/code/MyApp/MyApp.xcodeproj", date: Date())
        XCTAssertEqual(p.displayName, "MyApp")
    }

    func testDetailPathShortensHome() {
        let home = NSHomeDirectory()
        let p = RecentProject(path: home + "/code/Foo/Foo.xcodeproj", date: Date())
        XCTAssertEqual(p.detailPath, "~/code/Foo/Foo.xcodeproj")

        let outside = RecentProject(path: "/Volumes/Data/Foo.xcodeproj", date: Date())
        XCTAssertEqual(outside.detailPath, "/Volumes/Data/Foo.xcodeproj")
    }

    // MARK: 多语言字典一致性（直接读源码，防止漏翻/拼错 key）

    func testLocalizationKeysAreSymmetric() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // 仓库根
        let source = try String(contentsOf: root.appendingPathComponent("Sources/L10n.swift"), encoding: .utf8)
        guard let split = source.range(of: "static let en") else {
            return XCTFail("L10n.swift 结构变了：找不到 `static let en`")
        }
        func keys(in block: Substring) -> [String] {
            block.split(separator: "\n").compactMap { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("\""), let end = t.range(of: "\":") else { return nil }
                return String(t[t.startIndex..<end.lowerBound].dropFirst())
            }
        }
        let zh = keys(in: source[..<split.lowerBound])
        let en = keys(in: source[split.lowerBound...])
        XCTAssertFalse(zh.isEmpty)
        XCTAssertEqual(Set(zh).count, zh.count, "中文块有重复 key")
        XCTAssertEqual(Set(en).count, en.count, "英文块有重复 key")
        XCTAssertEqual(Set(zh), Set(en), "中英 key 集合必须一致")
    }
}
