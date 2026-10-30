## iXcode 1.0.0 · 首个正式版

菜单栏里的 Xcode 效率工具：最近工程、模拟器管理、缓存清理，一站直达。

> 此前 2.x–4.x 都属于开发迭代，仓库历史已合并为单次提交，版本从 1.0.0 重新起算。

### 功能

- **最近工程** — 名称 / 完整路径 / 相对时间；Flutter 的 `Runner` 自动替换成仓库目录名，重名工程一眼区分
  - 点按 = Xcode 打开 ・ `⌘` = 复制路径 ・ `⇧` = 终端打开目录 ・ `⌥` = Finder 显示
  - `⌃` 点按或右键 = 置顶（置顶工程排最前，带图钉标记）
  - `⌘F` 搜索窗口：过滤全部工程（不受菜单条目数限制）
- **模拟器管理** — 启动 / 关机、已装应用列表（图标 + 名称·版本 + bundle ID）、打开沙盒 / App Bundle、卸载、抹除、删除；清理不可用设备、新建最新款 iPhone
- **缓存清理** — DerivedData 体积实时显示，一键清理（确认 + 系统通知）
- **快捷入口** — 直接拉起 Xcode Organizer（Archives）、描述文件、DeviceSupport、DerivedData
- **设置面板**（`⌘,`）— 通用 / 关于两个 tab：语言、菜单条目数、模块开关、开机自启、Dock 图标、自动检查更新
- **内置自动更新** — 优先 dmg（zip 兜底），校验后原子安装，失败自动回滚
- **中英双语** — English / 简体中文 / 跟随系统

### 安装

下载 `iXcode-v1.0.0.dmg` → 打开 → 把 **iXcode** 拖进「应用程序」。

ad-hoc 签名、未公证：首次打开如被拦截，右键 App → **打开**，或到「系统设置 → 隐私与安全性」放行。

---

**English** — iXcode 1.0.0, the first stable release. A menu bar companion for Xcode: recent projects (with full path, pin-to-top, ⌘F search), simulator management (boot/shutdown, installed apps, sandbox access), DerivedData cleanup, quick shortcuts to Organizer/provisioning profiles, tabbed preferences and a built-in dmg-based updater. Previous 2.x–4.x builds were internal iterations; history has been squashed and the version restarts at 1.0.0. Download the dmg, drag iXcode into Applications. Ad-hoc signed and not notarized — right-click → Open on first launch if Gatekeeper complains.
