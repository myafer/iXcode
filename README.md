<div align="center">

# 🔨 iXcode

**Your Xcode companion in the menu bar — recents, simulators, cleanup, all in one menu.**

[中文说明](README.zh-CN.md) · English

</div>

---

Xcode's built-in project switching is bare-bones: the Recent menu shows bare file names, the Dock right-click menu has nothing at all, and identically-named workspaces (Flutter's `Runner`, anyone?) become indistinguishable. Meanwhile everyday chores — simulator management, cache cleanup — mean opening Terminal and typing simctl commands.

**iXcode packs all of that into one menu** — a 🔨 icon living in your menu bar:

- **Recent projects** with full path and time; workspace names are auto-replaced by their repo folder name, so same-named projects are instantly tellable apart
- **Simulator manager** — boot/shutdown, app list, sandbox access, no simctl needed
- **Cache cleanup & quick folders**, one click away

## Features ✨

- 📂 **Recent Projects** — project name + full path + relative time, sorted by last opened
  - Click = open in Xcode
  - `⌘` Click = copy full path
  - `⇧` Click = open project folder in Terminal
  - `⌥` Click = reveal in Finder
  - `⌃` Click / right-click = pin to top (pinned projects stay first, marked with a pin icon)
  - 🔍 **Search window** (`⌘F`) — fuzzy-filter **all** projects (not capped by the menu limit), ↑↓ select, ↩ open, ⌥↩ Finder
  - `⇧` opens with your terminal of choice — iTerm2 / Warp / Ghostty / kitty… auto-detected, pick one in Settings
- 📱 **Simulator Manager** — one submenu per device:
  - Boot / shutdown, open device data folder
  - Installed apps in iSimulator style: icon tile + name·version(build) + bundle ID
    - Launch app · Open sandbox · Open app bundle · Uninstall
  - Erase content… · Delete simulator…
  - Global: open Simulator.app, shutdown all, create latest iPhone simulator, delete unavailable devices
- 🧹 **Clean DerivedData** — live cache size shown in the menu, one-click clean (with confirmation + system notification)
- 📦 **Quick Folders & Organizer** — Open Xcode Organizer (Archives) directly / Provisioning Profiles / iOS DeviceSupport / DerivedData
- 🟢 **Status at a glance** — booted simulators pinned to the top with a green dot, idle ones below
- 🖥 **Optional Dock mode** — show a Dock icon with a right-click quick menu; click the icon to open Settings
- 🌐 **Bilingual UI** — English / 简体中文 / follow system
- ⚙️ **Settings panel** (`⌘,`) — tabbed General / About: language, max menu items (5–30), module toggles, launch at login, show in Dock, optional auto-update check
- 🔄 **Built-in auto-updater** — checks GitHub Releases (can be turned off), downloads the DMG, mounts & extracts the new app, one-click install & relaunch

## How it works

The recent-projects data comes from `~/Library/Developer/Xcode/DerivedData/*/info.plist` (`WorkspacePath` + `LastAccessedDate`). No permissions needed, no TCC prompts. Simulator data comes from `xcrun simctl`.

## Install

**Download** — grab `iXcode-vX.Y.Z.dmg` from [Releases](https://github.com/myafer/iXcode/releases), open it and drag **iXcode** into `Applications`, then launch (the 🔨 icon appears in your menu bar). A `.zip` is also provided for the built-in auto-updater of older versions.

> The binary is ad-hoc signed, not notarized. On first launch macOS may warn — right-click the app → **Open**, or allow it in System Settings → Privacy & Security.

**Build from source** — it's a standard Xcode project (`iXcode.xcodeproj`, generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen)):

```bash
open iXcode.xcodeproj   # build & debug in Xcode, or:
make                    # xcodebuild Release -> build/iXcode.app
make test               # run unit tests (pure-logic bundle, no app launch)
make install            # install to ~/Applications and launch
make project            # regenerate the xcodeproj after editing project.yml
```

Requires macOS 13+ and Xcode 15+.

## UI

| Menu | Settings |
|:---:|:---:|
| Projects / Simulators / Clean / Quick folders | Language / Item count / Toggles / Launch at login |

## License

MIT
