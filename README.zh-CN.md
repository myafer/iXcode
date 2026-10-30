<div align="center">

# 🔨 iXcode

**菜单栏里的 Xcode 效率工具——最近工程、模拟器管理、缓存清理，一站直达。**

English · [简体中文](README.zh-CN.md)

</div>

---

Xcode 自带的项目切换能力相当原始：Recent 菜单只给个文件名，Dock 右键菜单更是啥都没有，工程一重名（比如 Flutter 的 `Runner`）就彻底抓瞎；模拟器管理、缓存清理这些日常操作又得开终端敲命令。

**iXcode 把这些装进了一个菜单**——菜单栏常驻 🔨 图标，点开即达：

- **最近工程**，带完整路径和时间，Runner 自动替换为仓库目录名，重名工程一眼区分
- **模拟器管理**，启动/关机、应用列表、沙盒直达，不用再敲 simctl
- **缓存清理、常用目录**，一键直达

## 功能 ✨

- 📂 **最近工程列表** — 工程名 + 完整路径 + 相对时间，按最后打开时间排序
  - 点按 = 用 Xcode 打开
  - `⌘` 点按 = 复制完整路径
  - `⇧` 点按 = 在终端打开工程目录
  - `⌃` 点按 / 右键 = 置顶（置顶的工程排最前，带图钉标记）
  - 🔍 **搜索窗口**（`⌘F`）— 过滤**全部**工程（不受菜单条目数限制），↑↓ 选择、↩ 打开、⌥↩ Finder
  - `⇧` 使用的终端可自选 — iTerm2 / Warp / Ghostty / kitty… 自动检测，设置里选一个
- 📱 **模拟器管理** — 每台设备一个子菜单：
  - 启动 / 关机、打开设备数据目录
  - 已装应用（iSimulator 风格）：圆角图标块 + 名称·版本(build) + bundle ID
    - 启动 App · 打开沙盒目录 · 打开 App Bundle · 卸载应用
  - 抹掉内容… · 删除模拟器…
  - 全局操作：打开 Simulator.app、关闭所有模拟器、新建最新款 iPhone 模拟器、清理不可用设备
- 🧹 **清理 DerivedData** — 菜单内实时显示缓存体积，一键清理（带确认 + 系统通知）
- 📦 **快捷目录 & Organizer** — 直接拉起 Xcode Organizer（Archives 面板）/ 描述文件 / iOS DeviceSupport / DerivedData
- 🟢 **状态一目了然** — 运行中的模拟器带绿点排在最上方，未运行的排下方
- 🖥 **Dock 模式**（可选）— Dock 栏常驻图标，右键快捷菜单，点击图标打开设置
- 🌐 **中英双语** — English / 简体中文 / 跟随系统
- ⚙️ **设置面板**（`⌘,`）— 通用 / 关于两个 tab：语言、菜单条目数（5–30）、各模块开关、开机自启、Dock 图标显示、自动检查更新开关
- 🔄 **内置自动更新** — 检查 GitHub Releases（可关闭），下载 dmg 并挂载提取新版本，一键安装重启

## 实现原理

最近工程数据来自 `~/Library/Developer/Xcode/DerivedData/*/info.plist`（`WorkspacePath` + `LastAccessedDate`），无需任何系统权限、不会触发 TCC 弹窗。模拟器数据来自 `xcrun simctl`。

## 安装

**下载安装** — 从 [Releases](https://github.com/myafer/iXcode/releases) 下载 `iXcode-vX.Y.Z.dmg`，打开后把 **iXcode** 拖进「应用程序」，双击打开（菜单栏出现 🔨 即成功）。同时提供 `.zip` 供旧版本内置自动更新使用。

> 安装包为 ad-hoc 签名（未公证），首次打开 macOS 可能弹安全提示——右键 App → **打开**，或到 系统设置 → 隐私与安全性 里放行。

**源码构建** — 标准 Xcode 工程（`iXcode.xcodeproj`，由 `project.yml` 经 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 生成）：

```bash
open iXcode.xcodeproj   # 在 Xcode 里构建 / 断点调试，或者：
make                    # xcodebuild Release → build/iXcode.app
make test               # 跑单元测试（纯逻辑 bundle，不会启动 App）
make install            # 安装到 ~/Applications 并启动
make project            # 改过 project.yml 后重新生成工程
```

要求 macOS 13+、Xcode 15+。

## 界面

| 菜单 | 设置面板 |
|:---:|:---:|
| 工程 / 模拟器 / 清理 / 快捷入口 | 语言 / 条目数 / 开关 / 开机自启 |

## 许可

MIT
