// Focus Familiar — productization layer
// onboarding, preferences, data retention/eraser, git-commit celebration

import Cocoa
import ServiceManagement

// ── data retention & privacy eraser ─────────────────────────

func pruneOldLogs() {
    let days = UserDefaults.standard.object(forKey: "retentionDays") as? Int ?? 90
    guard days > 0 else { return }
    let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
    guard let files = try? FileManager.default.contentsOfDirectory(at: logDir, includingPropertiesForKeys: nil) else { return }
    for url in files where url.lastPathComponent.hasPrefix("activity-") {
        let name = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "activity-", with: "")
        if let d = f.date(from: name), d < cutoff { try? FileManager.default.removeItem(at: url) }
    }
}

// drop everything recorded after `ts` (ms epoch) from today's log
func eraseSince(_ ts: Double) {
    let url = todayLogURL()
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
    let kept = text.split(separator: "\n").filter { line in
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t1 = obj["t1"] as? Double else { return false }
        return t1 <= ts
    }
    let out = kept.joined(separator: "\n") + (kept.isEmpty ? "" : "\n")
    try? out.write(to: url, atomically: true, encoding: .utf8)
}

func eraseAllHistory() {
    try? FileManager.default.removeItem(at: logDir)
    try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
}

func historyStats() -> String {
    guard let files = try? FileManager.default.contentsOfDirectory(at: logDir, includingPropertiesForKeys: [.fileSizeKey]) else { return "no data yet" }
    let logs = files.filter { $0.lastPathComponent.hasPrefix("activity-") }
    let bytes = logs.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
    return "\(logs.count) day\(logs.count == 1 ? "" : "s") on disk · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) · all local"
}

// ── automation permission status (no prompt) ────────────────

func automationStatus(_ bundleId: String) -> OSStatus {
    let desc = NSAppleEventDescriptor(bundleIdentifier: bundleId)
    guard let aeDesc = desc.aeDesc else { return -1 }
    return AEDeterminePermissionToAutomateTarget(aeDesc, typeWildCard, typeWildCard, false)
}

func defaultBrowserBundleId() -> String? {
    guard let url = URL(string: "https://example.com"),
          let appURL = NSWorkspace.shared.urlForApplication(toOpen: url),
          let bundle = Bundle(url: appURL) else { return nil }
    return bundle.bundleIdentifier
}

// ── git commit watcher → proud celebration ──────────────────
// polls .git/logs/HEAD mtimes under the projects folder every 30s

final class GitWatcher {
    var timer: Timer?
    var mtimes: [String: Date] = [:]
    var onCommit: ((String) -> Void)?

    static func projectsDir() -> URL {
        if let p = UserDefaults.standard.string(forKey: "projectsDir") {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/GitHub")
    }

    func start() {
        scan(initial: true)
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.scan(initial: false)
        }
    }

    func scan(initial: Bool) {
        let dir = GitWatcher.projectsDir()
        guard let kids = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for repo in kids {
            let head = repo.appendingPathComponent(".git/logs/HEAD")
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: head.path),
                  let m = attrs[.modificationDate] as? Date else { continue }
            let key = repo.lastPathComponent
            defer { mtimes[key] = m }
            guard !initial, let prev = mtimes[key], m > prev else { continue }
            if let text = try? String(contentsOf: head, encoding: .utf8),
               let last = text.split(separator: "\n").last,
               last.contains("commit") {
                onCommit?(key)
            }
        }
    }
}

// ── shared UI helpers ───────────────────────────────────────

private func label(_ text: String, size: CGFloat = 13, bold: Bool = false, dim: Bool = false) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
    if dim { l.textColor = .secondaryLabelColor }
    l.lineBreakMode = .byWordWrapping
    l.preferredMaxLayoutWidth = 420
    return l
}

// ── onboarding & preferences windows ────────────────────────

extension AppDelegate {

    // — Welcome / permissions (shown once on first run) —
    @objc func showOnboarding() {
        if let w = onboardingWin { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)

        stack.addArrangedSubview(label("Welcome to Focus Familiar", size: 22, bold: true))
        stack.addArrangedSubview(label("A tiny creature that lives on your screen. It feeds on your focus, gets poisoned by doomscrolling, and remembers what you were doing.", dim: true))

        stack.addArrangedSubview(label("Choose your familiar", size: 15, bold: true))
        let picker = NSPopUpButton()
        for (id, name) in [("lulu", "噜噜 LuLu — butter hamster"), ("clawd", "Clawd — terracotta voxel"), ("nat", "Nat — snorkeling kitty")] {
            picker.addItem(withTitle: name)
            picker.lastItem?.representedObject = id
        }
        picker.target = self
        picker.action = #selector(onboardPickCharacter(_:))
        stack.addArrangedSubview(picker)

        stack.addArrangedSubview(label("Permissions", size: 15, bold: true))
        stack.addArrangedSubview(label("App tracking needs no permission — it just works. ✓"))
        let permRow = NSStackView()
        permRow.orientation = .horizontal
        permRow.spacing = 10
        let permStatus = label(automationStatusLine(), dim: true)
        permStatus.identifier = .init("permStatus")
        let grantBtn = NSButton(title: "Enable browser awareness…", target: self, action: #selector(grantAutomation))
        permRow.addArrangedSubview(grantBtn)
        permRow.addArrangedSubview(permStatus)
        stack.addArrangedSubview(permRow)
        stack.addArrangedSubview(label("Browser awareness reads only the active tab's address, locally, to tell arXiv from YouTube. Nothing ever leaves your Mac.", size: 11, dim: true))

        stack.addArrangedSubview(label("The essentials", size: 15, bold: true))
        stack.addArrangedSubview(label("⌥Space — \"what was I doing?\"\n◐ menu → Today's journal — your day as an RPG quest log\n◐ menu → Begin a hunt — a pomodoro your familiar joins\nDrag the creature to a screen edge to tuck it away", dim: true))

        let login = NSButton(checkboxWithTitle: "Start Focus Familiar at login", target: self, action: #selector(onboardToggleLogin(_:)))
        login.state = SMAppServiceStatusEnabled() ? .on : .off
        stack.addArrangedSubview(login)

        let done = NSButton(title: "Let's go", target: self, action: #selector(finishOnboarding))
        done.keyEquivalent = "\r"
        stack.addArrangedSubview(done)

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 480),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Focus Familiar"
        win.contentView = stack
        win.isReleasedWhenClosed = false
        win.center()
        onboardingWin = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func automationStatusLine() -> String {
        guard let bid = defaultBrowserBundleId() else { return "no default browser found" }
        switch automationStatus(bid) {
        case 0: return "granted ✓"
        case -1744: return "not yet asked"
        case -1743: return "denied — enable in System Settings → Privacy → Automation"
        case -600: return "open your browser first, then click Enable"
        default: return "unknown"
        }
    }

    @objc func onboardPickCharacter(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String else { return }
        js("famSetCharacter('\(id)')")
        UserDefaults.standard.set(id, forKey: "character")
    }

    @objc func grantAutomation() {
        // fire a real (harmless) event at the default browser to trigger the prompt
        if let bid = defaultBrowserBundleId() {
            if NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bid }) == nil,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                _ = activeTab(bundleId: bid)
                self?.refreshPermStatus()
            }
        }
    }

    func refreshPermStatus() {
        guard let stack = onboardingWin?.contentView as? NSStackView else { return }
        func walk(_ v: NSView) {
            if let l = v as? NSTextField, l.identifier?.rawValue == "permStatus" { l.stringValue = automationStatusLine() }
            v.subviews.forEach(walk)
        }
        walk(stack)
    }

    @objc func onboardToggleLogin(_ sender: NSButton) { toggleLogin(NSMenuItem()) }

    @objc func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarded1")
        onboardingWin?.close()
    }

    // — Preferences (General + Data) —
    @objc func showPreferences() {
        if let w = prefsWin { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }

        let tabs = NSTabView(frame: NSRect(x: 0, y: 0, width: 480, height: 340))

        // General
        let g = NSStackView()
        g.orientation = .vertical; g.alignment = .leading; g.spacing = 12
        g.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let idleRow = NSStackView(); idleRow.spacing = 8
        idleRow.addArrangedSubview(label("Consider me away after"))
        let idlePop = NSPopUpButton()
        for (secs, name) in [(60.0, "1 minute"), (150.0, "2.5 minutes"), (300.0, "5 minutes"), (600.0, "10 minutes")] {
            idlePop.addItem(withTitle: name)
            idlePop.lastItem?.representedObject = secs
        }
        let curIdle = UserDefaults.standard.object(forKey: "idleThreshold") as? Double ?? 150
        idlePop.selectItem(at: [60.0, 150.0, 300.0, 600.0].firstIndex(of: curIdle) ?? 1)
        idlePop.target = self; idlePop.action = #selector(prefIdleChanged(_:))
        idleRow.addArrangedSubview(idlePop)
        g.addArrangedSubview(idleRow)
        g.addArrangedSubview(label("Away time never counts as work.", size: 11, dim: true))

        let sounds = NSButton(checkboxWithTitle: "Sounds (level-ups, streaks, poisonings)", target: self, action: #selector(prefToggleSounds(_:)))
        sounds.state = UserDefaults.standard.bool(forKey: "soundOn") ? .on : .off
        g.addArrangedSubview(sounds)

        let login = NSButton(checkboxWithTitle: "Start at login", target: self, action: #selector(onboardToggleLogin(_:)))
        login.state = SMAppServiceStatusEnabled() ? .on : .off
        g.addArrangedSubview(login)

        let projRow = NSStackView(); projRow.spacing = 8
        projRow.addArrangedSubview(label("Projects folder (for commit celebrations)"))
        let projBtn = NSButton(title: GitWatcher.projectsDir().lastPathComponent + "…", target: self, action: #selector(prefPickProjects(_:)))
        projRow.addArrangedSubview(projBtn)
        g.addArrangedSubview(projRow)
        g.addArrangedSubview(label("Your familiar celebrates every git commit it sees there.", size: 11, dim: true))

        let gTab = NSTabViewItem(identifier: "general"); gTab.label = "General"; gTab.view = g
        tabs.addTabViewItem(gTab)

        // Data
        let d = NSStackView()
        d.orientation = .vertical; d.alignment = .leading; d.spacing = 12
        d.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        d.addArrangedSubview(label("Everything is recorded locally. Nothing leaves this Mac.", bold: true))
        let statsL = label(historyStats(), dim: true)
        statsL.identifier = .init("dataStats")
        d.addArrangedSubview(statsL)

        let retRow = NSStackView(); retRow.spacing = 8
        retRow.addArrangedSubview(label("Keep history for"))
        let retPop = NSPopUpButton()
        for (days, name) in [(30, "30 days"), (90, "90 days"), (365, "1 year"), (0, "forever")] {
            retPop.addItem(withTitle: name)
            retPop.lastItem?.representedObject = days
        }
        let curRet = UserDefaults.standard.object(forKey: "retentionDays") as? Int ?? 90
        retPop.selectItem(at: [30, 90, 365, 0].firstIndex(of: curRet) ?? 1)
        retPop.target = self; retPop.action = #selector(prefRetentionChanged(_:))
        retRow.addArrangedSubview(retPop)
        d.addArrangedSubview(retRow)

        d.addArrangedSubview(label("Forget", size: 15, bold: true))
        let btnRow = NSStackView(); btnRow.spacing = 8
        btnRow.addArrangedSubview(NSButton(title: "Last hour", target: self, action: #selector(forgetHour)))
        btnRow.addArrangedSubview(NSButton(title: "Today", target: self, action: #selector(forgetToday)))
        btnRow.addArrangedSubview(NSButton(title: "Everything…", target: self, action: #selector(forgetEverything)))
        d.addArrangedSubview(btnRow)
        d.addArrangedSubview(label("Removes entries from disk and from the familiar's memory. No undo.", size: 11, dim: true))

        d.addArrangedSubview(NSButton(title: "Reveal data folder in Finder", target: self, action: #selector(revealData)))

        let dTab = NSTabViewItem(identifier: "data"); dTab.label = "Data & Privacy"; dTab.view = d
        tabs.addTabViewItem(dTab)

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Focus Familiar Preferences"
        win.contentView = tabs
        win.isReleasedWhenClosed = false
        win.center()
        prefsWin = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func SMAppServiceStatusEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc func prefIdleChanged(_ sender: NSPopUpButton) {
        if let secs = sender.selectedItem?.representedObject as? Double {
            UserDefaults.standard.set(secs, forKey: "idleThreshold")
        }
    }
    @objc func prefToggleSounds(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "soundOn")
    }
    @objc func prefRetentionChanged(_ sender: NSPopUpButton) {
        if let days = sender.selectedItem?.representedObject as? Int {
            UserDefaults.standard.set(days, forKey: "retentionDays")
            pruneOldLogs()
            refreshDataStats()
        }
    }
    @objc func prefPickProjects(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = GitWatcher.projectsDir()
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: "projectsDir")
            sender.title = url.lastPathComponent + "…"
            gitWatcher.mtimes = [:]
            gitWatcher.scan(initial: true)
        }
    }

    @objc func forgetHour() {
        let ts = Date().timeIntervalSince1970 * 1000 - 3_600_000
        eraseSince(ts)
        js("famEraseSince(\(ts))")
        refreshDataStats()
    }
    @objc func forgetToday() {
        let start = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 * 1000
        eraseSince(start)
        js("famEraseSince(\(start))")
        refreshDataStats()
    }
    @objc func forgetEverything() {
        let a = NSAlert()
        a.messageText = "Delete all history?"
        a.informativeText = "Every day of activity, gone. XP and level stay. No undo."
        a.addButton(withTitle: "Delete Everything")
        a.addButton(withTitle: "Cancel")
        a.alertStyle = .warning
        if a.runModal() == .alertFirstButtonReturn {
            eraseAllHistory()
            js("famEraseSince(0)")
            refreshDataStats()
        }
    }
    @objc func revealData() { NSWorkspace.shared.activateFileViewerSelecting([logDir]) }

    func refreshDataStats() {
        guard let tabs = prefsWin?.contentView as? NSTabView else { return }
        func walk(_ v: NSView) {
            if let l = v as? NSTextField, l.identifier?.rawValue == "dataStats" { l.stringValue = historyStats() }
            v.subviews.forEach(walk)
        }
        for item in tabs.tabViewItems { if let v = item.view { walk(v) } }
    }
}
