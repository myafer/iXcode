import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// 按设置决定是否停留在 Dock 栏
app.setActivationPolicy(Settings.showInDock ? .regular : .accessory)
app.run()
