# AGENTS.md — AI 协作指南

> 本文档给 AI 编码助手（Claude Code / WorkBuddy / Qoder 等）看，说明本仓库的组织方式、构建流程和约定。改动代码前先读完这份文档。

## 项目是什么

**iXcode** — macOS 菜单栏 App（Swift + AppKit，单 binary，无第三方依赖）。定位：Xcode 效率工具合集——最近工程列表、iOS 模拟器管理（iSimulator 风格）、DerivedData 清理、快捷目录入口、GitHub Releases 自动更新。

## 目录结构（必须遵守）

```
Sources/
  main.swift                  # 入口：NSApplication 启动 + activationPolicy。不放任何业务逻辑
  L10n.swift                  # 全部文案。zh-Hans 和 en 两套字典必须同步加 key（测试会校验键集合对称）
  Settings.swift              # UserDefaults 读写（语言/条目数/模块开关/自启/Dock/置顶/终端）
  Models.swift                # 纯数据模型（RecentProject / SimulatorDevice / SimApp），Foundation-only
  Core/                       # ⭐ 纯逻辑（Foundation-only，App 与测试 target 共同编译）：
                              #   VersionCompare / ByteFormat / TextParsing+ReleaseAssets / ProjectPinning
  RecentsScanner.swift        # 系统查询服务：DerivedData 扫描、simctl 封装、体积计算、App 图标读取
  RowViews.swift              # 自定义菜单行视图（ProjectRowView / AppRowView）
  DeviceMenuProvider.swift    # 模拟器设备子菜单（delegate 懒加载 + appsCache）
  ProjectSearchWindow.swift   # ⌘F 工程搜索面板（搜索框 + 列表，全量数据）
  TerminalLauncher.swift      # ⇧ 终端 App 检测与打开（iTerm/Warp/Ghostty…）
  AppDelegate.swift           # 类声明 + 全部存储属性 + 生命周期 + 缓存刷新（不放具体动作）
  AppDelegate+Menu.swift      # 状态栏菜单 / Dock 菜单构建
  AppDelegate+Projects.swift  # 工程打开动作、置顶、搜索入口
  AppDelegate+Folders.swift   # 快捷目录、Organizer、清理 DerivedData
  AppDelegate+Simulator.swift # 模拟器子菜单与设备/App 操作
  AppDelegate+Update.swift    # 自动更新（GitHub Releases 检查/下载/安装重启）
  AppDelegate+Settings.swift  # 设置面板
Tests/                        # XCTest（只测 Core 纯逻辑 + 模型命名 + L10n 键对称）
Resources/                    # Info.plist + AppIcon.icns（icns 由 iconset 生成，不要手改）
project.yml                   # ⭐ Xcode 工程定义（xcodegen 源），改构建配置/加文件都改这里
iXcode.xcodeproj/             # 由 project.yml 生成，已提交；不要手改 project.pbxproj
scripts/                      # 辅助脚本（图标合成、API 推送）
.github/workflows/            # ci.yml（push 校验构建）/ release.yml（打 v* tag 自动发 Release）
```

## 加新功能的摆放规则

1. **新菜单项/动作**：放到对应的 `AppDelegate+XXX.swift`（菜单构建在 +Menu，动作按领域归文件）；独立新领域新建 extension 文件，并在本文件的目录结构里登记
2. **新数据结构**：放 `Models.swift`，不要在 controller 里定义 struct
3. **新系统查询**（跑命令行工具、读 plist）：放 `RecentsScanner.swift` 的 static 方法，保持 AppDelegate 只做 UI 编排
4. **新自定义视图**：放 `RowViews.swift`
5. **用户可见的任何文字**：必须走 `L10n.tr("key")`，zh-Hans/en 两个字典同时加，禁止硬编码文案
6. **可持久化的用户偏好**：加到 `Settings.swift`，命名布尔开关用 `showXxx` 风格
7. **extension 限制**：Swift extension 不能有存储属性，新存储属性必须加在 `AppDelegate.swift` 的类主体里

## 构建与调试

```bash
make project      # 改 project.yml / 增删源文件后，用 xcodegen 重新生成 iXcode.xcodeproj
make app          # xcodebuild Release 构建 → 产物固定拷贝到 build/iXcode.app（CI 依赖此路径）
make test         # 跑单元测试（纯逻辑 bundle，不启动 App；CI 也会跑）
make install      # 装到 /Applications 并重启（INSTALL_DIR=... 可覆盖）
open iXcode.xcodeproj   # 用 Xcode 打开（可断点调试）
```

### 单元测试（iXcodeTests）

- 测试 target **不挂 App 宿主**（无 TEST_HOST），只编译 `Tests/` + `Sources/Models.swift` + `Sources/Core/`，所以能在 CI 无头运行
- ⚠️ 往 `Sources/Core/` 加文件必须保持 **Foundation-only**：不 import AppKit、不读 Settings/UserDefaults/单例，否则测试 target 编不过
- 需要测试的纯逻辑一律抽到 Core；碰 NSWorkspace / simctl 的集成行为不写单测（UI 验证可用 `defaults write com.afer.ixcode IXCODE_DEBUG -string search|settings` 后启动，直接打开搜索/设置面板）

- **这是标准 Xcode 工程**（`iXcode.xcodeproj`，由 `project.yml` + `xcodegen` 生成，生成的工程已提交仓库，CI 不需要装 xcodegen）
- `project.yml` 是工程的**唯一事实来源**：加文件/改 build settings 改这里再 `make project`，不要手改 `project.pbxproj`（下次生成会被覆盖）
- Info.plist 走 `INFOPLIST_FILE = Resources/Info.plist`（`GENERATE_INFOPLIST_FILE = NO`），**版本号改 `Resources/Info.plist` 两处（ShortVersion + BundleVersion）**，同时把 `project.yml` 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 改成同一个值保持同步（产物以后者不参与，但不要留旧号误导）
- 图标仍是裸 `AppIcon.icns` + `CFBundleIconFile`（没做 Asset Catalog），在 `project.yml` 里以 resource 形式挂进 target
- 签名为 ad-hoc（`CODE_SIGN_IDENTITY = "-"`），无沙盒、无第三方依赖；别引入 SPM 包除非确有必要
- 改完代码 `make app` 必须零 error

## 发版流程（重要）

> 仓库历史已于 1.0.0 合并为**单次提交**（`83027bb` 之前是 2.x–4.x 的 30 个提交，已废弃）；版本号从 1.0.0 重新起算，tag 形如 `vX.Y.Z`。

1. **先更新发布说明**：改 `.github/release-notes.md`（中英双段，release.yml 用 `body_path` 读它，不再自动生成 notes）
2. 版本号：`Resources/Info.plist` 两处 + `project.yml` 两处，改完 `make project`（会重写 pbxproj）
3. `make test && make install` 本地验证，`defaults` 里旧设置不受影响（bundle id 未变）
4. 提交 → 打 tag → 推送：`git tag -a vX.Y.Z -m "..." && git push origin main vX.Y.Z`
5. release.yml 自动构建并发布 GitHub Release，附件 **`iXcode-vX.Y.Z.dmg`（主）+ `iXcode-vX.Y.Z.zip`（兼容老自动更新）**
6. 用户端已装 App 会通过内置自动更新（启动 3s 后查 `releases/latest`，可用设置里的「启动时自动检查更新」关闭）提示升级；**更新包优先走 dmg**：下载 → `hdiutil attach` 到临时挂载点 → `ditto` 拷出 iXcode.app → detach，zip 逻辑保留作兜底
7. ⚠️ **当 git https 通道被代理挡（502）时**：用 `scripts/api_push.sh <本地内容基准commit> "<msg>" <tag>` 走 Git Data API 推送。注意 base 参数必须传**本地** commit SHA（内容与远端一致的最近本地提交），传远端 SHA 会报 `bad object`；`<tag>` 传空字符串则只推 main、不触发发版
8. 只想改文档/脚本、不想发版时，用 `scripts/api_push.sh <base> "<msg>" ""`，main 更新但不打 tag

## 网络请求约定（踩坑记录）

⚠️ **不要用 `URLSession` 做更新检查/下载**。macOS 上 URLSession 会跟随系统代理，而很多公司/本地代理对 `api.github.com` 直接返回 **403**（而 `github.com` 反而必须走代理）；`connectionProxyDictionary = ["HTTPEnable": 0, ...]` 实测并不能可靠绕过。

现方案（`AppDelegate+Update.swift`）：统一走 `/usr/bin/curl`，显式指定通道。

| 目标 | 通道顺序 | 原因 |
|---|---|---|
| `api.github.com`（版本检查） | 直连 → 系统代理 | 代理常返回 403 |
| `github.com`（zip 下载、atom 兜底） | 系统代理 → 直连 | 直连常被墙/超时 |

- 系统代理从 `scutil --proxy` 解析（`AppDelegate.systemProxy()`），别硬编码端口
- curl 必须带 `--retry 3 --retry-all-errors`（代理偶发掐断会得到 `status=18` partial file）
- 版本检查失败时走 `releases.atom` 兜底（不消耗 API 配额，抗 403 限流），资产名按 `iXcode-<tag>.dmg` 约定拼
- 挑资产用 `preferredAssetURL(in:)`：**dmg 优先、zip 兜底**，别写死扩展名
- 更新失败必须把真实原因（HTTP 码 / curl 报错）显示在设置面板 label + tooltip 里，不要只说"检查失败"

## 主线程禁令（2026-10-29 转圈事故复盘）

**事故**：启动 3 秒后整个 App 转圈点不动。`sample iXcode` 抓到主线程 100% 卡在
`checkForUpdates → fetch → curl → read()`——`curl` 是同步 `Process`，被直接放在了主线程的
`asyncAfter` 里，一次检查最坏要走「API 直连 + API 代理 + atom 代理 + atom 直连」4 条通道
（每条 `--retry 3`、`connect-timeout 10`、`max-time 30`），再加上下载 `max-time 120`，
等于把主线程焊死几十秒到几分钟。

**规则（写新代码必须遵守）**：

| 类别 | 禁止在主线程做 | 正确做法 |
|---|---|---|
| 网络 | `curl()` / `fetch()` / `downloadUpdate()` / `unzipAndPrepare()` | `AppDelegate.netQueue`（串行后台队列），回调里 `DispatchQueue.main.async` 刷 UI |
| simctl 变更 | `erase` / `delete` / `uninstall` / `shutdown` / `create` | `AppDelegate.simctlQueue`，或用 `runSimctl(_:done:)` |
| DerivedData 扫描 | `RecentsScanner.scan()` | `refreshProjectsAsync()`，主线程只读 `cachedProjects` |
| 体积遍历 | `derivedDataSize()`（遍历整棵树，几十万文件） | `refreshCachesAsync()` 后台跑 + **60 秒节流** |
| App 图标解码 | `appIcon(fromBundlePath:)` 直接同步调用 | `RecentsScanner.loadAppIcon()` 后台 + 内存缓存（`NSLock` 保护），视图先放占位图 |

- `NSStatusItem` 菜单、`applicationDockMenu` 都是**主线程同步构建**的，里面只能读缓存，不能有磁盘 I/O 或子进程
- 调试手法：怀疑卡顿时直接 `sample <进程名> 5 -file /tmp/x.txt`，看 `Main Thread` 分支，别靠猜


## 红线（历史教训，禁止再犯）

1. **公开仓库严禁出现公司内部信息**：公司工程名（如内部 App 代号）、内部域名、公司账号、工号等，一律不得写进 README / 源码注释 / commit message / icon
2. **README 双语**：`README.md`（英文优先）+ `README.zh-CN.md`（中文），顶部互相链接；README 开头定位是「Xcode 效率工具合集」，不要把卖点写窄成单一功能
3. **图标读取**：模拟器 App 图标不能依赖 `NSWorkspace.icon(forFile:)`（对模拟器 .app 返回禁止占位图），要走 `RecentsScanner.appIcon(fromBundlePath:)` 解析 Info.plist 读 PNG
4. **数据指标类改动**注意 `DeviceMenuProvider.appsCache` 的失效（卸载/抹掉/删除后必须 `invalidate(udid:)`；该缓存带 15s TTL 且有锁，后台写/主线程读别绕过封装直接摸字典）
5. **快捷键注册**：状态栏菜单里的 `keyEquivalent` 只在菜单展开时生效，⌘,/⌘Q 这类全局快捷键必须挂在 `installMainMenu()` 建的主菜单上；语言切换后要重建主菜单
6. **更新包校验**：dmg/zip 解出来的 iXcode.app 必须 `validateApp(at:expectedVersion:)`（bundle id 一致性）后才进 `.ready`；安装脚本必须「旁路拷贝 + 两步换位 + 失败回滚」，禁止先 `rm -rf` 原 App 再 `cp`
7. **通知授权**：`notify()` 的授权结果有缓存（`notificationGranted`），别每条通知都 `requestAuthorization`
5. **Redmine/工作流**：这是个人开源项目，与公司工作区（/Users/jojo/com）无关，不要混用

## 风格约定

- 中文注释，每个文件顶部 `// MARK: -` 标注职责
- 菜单条目统一 `menu.autoenablesItems = false` + 手动 `isEnabled = true`
- 耗时操作（simctl、体积计算、网络）一律后台线程，回主线程刷 UI；菜单开着时通过 `refreshCachesAsync` + `menuIsOpen` 原地重建
- 菜单构建只允许读缓存（`cachedProjects` / `cachedSimulators` / `cachedDDSize`），禁止在 `rebuild` / `buildDockMenu` 里做磁盘或子进程调用，详见「主线程禁令」
- 破坏性操作（清理/抹掉/删除/卸载）必须 `confirm()` 弹窗 + 完成后 `notify()` 系统通知
