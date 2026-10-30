import AppKit

// MARK: - 工程搜索面板（⌘F）
//
// 独立小窗：搜索框 + 结果列表。↑↓ 选择、↩ 在 Xcode 打开、⌥↩ 在 Finder 显示、esc 关闭。
// 数据来自 AppDelegate.allProjects（全量，不受菜单 maxItems 限制）。

final class ProjectSearchController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {

    private weak var owner: AppDelegate?
    private var window: NSWindow?
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let countLabel = NSTextField(labelWithString: "")

    private var all: [RecentProject] = []
    private var shown: [RecentProject] = []

    init(owner: AppDelegate) {
        self.owner = owner
        super.init()
    }

    // MARK: 显示 / 更新

    func show(projects: [RecentProject]) {
        all = projects
        buildWindowIfNeeded()
        applyFilter(searchField.stringValue)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(searchField)
        searchField.currentEditor()?.selectAll(nil)
        selectRow(0)
    }

    /// 后台扫到新列表时回填（窗口开着才有意义）
    func update(projects: [RecentProject]) {
        all = projects
        guard window?.isVisible == true else { return }
        applyFilter(searchField.stringValue)
    }

    private func close() {
        window?.orderOut(nil)
    }

    // MARK: UI

    private func buildWindowIfNeeded() {
        guard window == nil else { return }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        win.title = L10n.tr("searchProjects")
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.minSize = NSSize(width: 420, height: 240)

        let content = NSView()

        searchField.placeholderString = L10n.tr("searchPlaceholder")
        searchField.font = .systemFont(ofSize: 13)
        searchField.delegate = self
        searchField.sendsWholeSearchString = false
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("project"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 46
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .systemFont(ofSize: 10.5)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.lineBreakMode = .byTruncatingTail
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(searchField)
        content.addSubview(scroll)
        content.addSubview(countLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),

            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: countLabel.topAnchor, constant: -6),

            countLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            countLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            countLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])

        win.contentView = content
        window = win
    }

    // MARK: 过滤 / 选择

    private func applyFilter(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            shown = all
        } else {
            shown = all.filter {
                $0.displayName.lowercased().contains(q) || $0.path.lowercased().contains(q)
            }
        }
        tableView.reloadData()
        countLabel.stringValue = shown.isEmpty
            ? L10n.tr("noMatch")
            : "\(shown.count) / \(all.count) · \(L10n.tr("searchHint"))"
        selectRow(0)
    }

    private func selectRow(_ row: Int) {
        guard !shown.isEmpty else {
            tableView.deselectAll(nil)
            return
        }
        let idx = min(max(row, 0), shown.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        tableView.scrollRowToVisible(idx)
    }

    private func move(_ delta: Int) {
        let current = tableView.selectedRow < 0 ? 0 : tableView.selectedRow
        selectRow(current + delta)
    }

    private func openSelected(reveal: Bool) {
        let row = tableView.selectedRow
        guard row >= 0, row < shown.count else { return }
        let project = shown[row]
        close()
        if reveal || !project.exists {
            owner?.revealInFinder(path: project.path)
        } else {
            owner?.openInXcode(project.path)
        }
    }

    @objc private func rowDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < shown.count else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        openSelected(reveal: NSApp.currentEvent?.modifierFlags.contains(.option) == true)
    }

    // MARK: NSTextFieldDelegate（方向键 / 回车 / esc）

    func controlTextDidChange(_ obj: Notification) {
        applyFilter(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            move(1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            move(-1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            openSelected(reveal: NSApp.currentEvent?.modifierFlags.contains(.option) == true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("ProjectSearchRow")
        let view = tableView.makeView(withIdentifier: id, owner: nil) as? SearchRowView ?? SearchRowView()
        view.identifier = id
        view.configure(project: shown[row], pinned: Settings.pinnedPaths.contains(shown[row].path))
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // 键盘上下移动后保证可见（selectRow 里已处理，这里是兜底）
        let row = tableView.selectedRow
        if row >= 0 { tableView.scrollRowToVisible(row) }
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // 保留 window 实例（isReleasedWhenClosed = false），下次直接复用
    }
}

// MARK: - 结果行（双行：名称 / 路径）

private final class SearchRowView: NSTableCellView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let pinView = NSImageView()

    /// 名字左起点：给置顶图钉固定预留槽位，保证置顶/非置顶行名字对齐
    private let nameX: CGFloat = 14 + PinMark.slotWidth + 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        pathLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pinView.image = PinMark.image(pointSize: 10)
        pinView.contentTintColor = .tertiaryLabelColor
        pinView.isHidden = true
        addSubview(nameLabel)
        addSubview(pathLabel)
        addSubview(pinView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(project: RecentProject, pinned: Bool) {
        pinView.isHidden = !pinned
        nameLabel.stringValue = project.displayName
        nameLabel.textColor = project.exists ? .labelColor : .tertiaryLabelColor
        let suffix = project.exists ? project.relativeTime : L10n.tr("missing")
        pathLabel.stringValue = "\(project.detailPath)　·　\(suffix)"
    }

    override func layout() {
        super.layout()
        let nameTop = bounds.height - 25
        let width = max(bounds.width - nameX - 14, 40)
        nameLabel.frame = NSRect(x: nameX, y: nameTop, width: width, height: 17)
        pathLabel.frame = NSRect(x: nameX, y: 8, width: width, height: 14)

        let pinSize = pinView.image?.size ?? NSSize(width: PinMark.slotWidth, height: 11)
        pinView.frame = NSRect(x: 14, y: nameTop + (17 - pinSize.height) / 2,
                               width: pinSize.width, height: pinSize.height)
    }
}
