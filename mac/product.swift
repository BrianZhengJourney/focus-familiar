// Focus Familiar — productization layer
// settings window (HTML), data retention/eraser, git-commit celebration

import Cocoa
import WebKit
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

// ── the one settings window (hosts settings.html) ───────────

extension AppDelegate {

    @objc func showSettings() {
        if let w = settingsWin {
            pushSettingsState()
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "settings")
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 560, height: 780), configuration: cfg)
        web.navigationDelegate = self
        if let dir = Bundle.main.resourceURL {
            web.loadFileURL(dir.appendingPathComponent("settings.html"), allowingReadAccessTo: dir)
        }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 780),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Focus Familiar"
        win.contentView = web
        win.isReleasedWhenClosed = false
        win.center()
        settingsWeb = web
        settingsWin = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func permLine(_ code: OSStatus) -> String {
        switch code {
        case 0: return "granted — the familiar can read tab addresses"
        case -1744: return "not yet enabled"
        case -1743: return "denied — System Settings → Privacy → Automation"
        case -600: return "open your browser, then click Enable"
        default: return "no default browser found"
        }
    }

    func pushSettingsState() {
        let d = UserDefaults.standard
        let bid = defaultBrowserBundleId()
        let code = bid.map { automationStatus($0) } ?? OSStatus(-1)
        var rules: [[String: Any]] = []
        for (key, label) in seenItems {
            rules.append(["key": key, "label": label, "kind": ruleOverrides[key] ?? defaultKind(key)])
        }
        rules.sort { ($0["label"] as? String ?? "").lowercased() < ($1["label"] as? String ?? "").lowercased() }
        let state: [String: Any] = [
            "character": d.string(forKey: "character") ?? "lulu",
            "permCode": Int(code),
            "permText": permLine(code),
            "rules": rules,
            "idle": d.object(forKey: "idleThreshold") as? Double ?? 150,
            "retention": d.object(forKey: "retentionDays") as? Int ?? 90,
            "sounds": d.bool(forKey: "soundOn"),
            "login": SMAppService.mainApp.status == .enabled,
            "stats": historyStats(),
            "projects": GitWatcher.projectsDir().lastPathComponent,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: state),
              let json = String(data: data, encoding: .utf8) else { return }
        settingsWeb?.evaluateJavaScript("initSettings(\(json))", completionHandler: nil)
    }

    func handleSettings(_ body: [String: Any]) {
        let d = UserDefaults.standard
        switch body["type"] as? String ?? "" {
        case "pick":
            if let id = body["id"] as? String {
                js("famSetCharacter('\(id)')")
                d.set(id, forKey: "character")
            }
        case "grant":
            grantAutomation()
        case "recheck":
            pushSettingsState()
        case "rule":
            if let key = body["key"] as? String, let kind = body["kind"] as? String {
                if kind == defaultKind(key) { ruleOverrides.removeValue(forKey: key) }
                else { ruleOverrides[key] = kind }
                saveOverrides()
                lastSent = ""
                if let front = NSWorkspace.shared.frontmostApplication { send(app: front) }
            }
        case "idle":
            if let secs = body["secs"] as? Double { d.set(secs, forKey: "idleThreshold") }
        case "sounds":
            d.set(body["on"] as? Bool ?? false, forKey: "soundOn")
        case "login":
            let svc = SMAppService.mainApp
            if body["on"] as? Bool == true { try? svc.register() } else { try? svc.unregister() }
        case "projects":
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.directoryURL = GitWatcher.projectsDir()
            if panel.runModal() == .OK, let url = panel.url {
                d.set(url.path, forKey: "projectsDir")
                gitWatcher.mtimes = [:]
                gitWatcher.scan(initial: true)
            }
            pushSettingsState()
        case "retention":
            if let days = body["days"] as? Int {
                d.set(days, forKey: "retentionDays")
                pruneOldLogs()
                pushSettingsState()
            }
        case "forget":
            switch body["span"] as? String ?? "" {
            case "hour":
                let ts = Date().timeIntervalSince1970 * 1000 - 3_600_000
                eraseSince(ts); js("famEraseSince(\(ts))")
            case "today":
                let start = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 * 1000
                eraseSince(start); js("famEraseSince(\(start))")
            case "all":
                let a = NSAlert()
                a.messageText = "Delete all history?"
                a.informativeText = "Every day of activity, gone. XP and level stay. No undo."
                a.addButton(withTitle: "Delete Everything")
                a.addButton(withTitle: "Cancel")
                a.alertStyle = .warning
                if a.runModal() == .alertFirstButtonReturn {
                    eraseAllHistory(); js("famEraseSince(0)")
                }
            default: break
            }
            pushSettingsState()
        case "reveal":
            NSWorkspace.shared.activateFileViewerSelecting([logDir])
        case "done":
            d.set(true, forKey: "onboarded1")
            settingsWin?.close()
        default:
            break
        }
    }

    @objc func grantAutomation() {
        guard let bid = defaultBrowserBundleId() else { return }
        if NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bid }) == nil,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            _ = activeTab(bundleId: bid)
            self?.pushSettingsState()
        }
    }
}

// ── LuLu, drawn tiny for the menu bar ───────────────────────

func luluStatusIcon() -> NSImage {
    let base = [
        "....Y......YB....",
        "...yY.....YYYy...",
        "..YYYY...YYYY..T.",
        ".YyYYYYYYYYYY.TT.",
        ".YYYYYYYYYYYYyTTT",
        "YYYOOOOOOOOYYYYTT",
        "YYOOOOOOOOOOYYYTT",
        ".YOOOOOOOOOOYYTT.",
        ".YBOOCNCOOOBYYT..",
        "YYOOOCCCOOOOYYY..",
        "YYYOOOOOOOOYYYY..",
        "YYYYYYYYYYYYHHH..",
        ".YYYYYYYYYYYHH...",
        ".YFF.YHHY.FF.H...",
        "..FF......FF.....",
    ]
    let eyes: [(Int, Int, Character)] = [(4,6,"K"),(5,6,"K"),(4,7,"K"),(5,7,"K"),(4,6,"W"),
                                         (9,6,"K"),(10,6,"K"),(9,7,"K"),(10,7,"K"),(9,6,"W")]
    let mouth: [(Int, Int, Character)] = [(5,10,"M"),(7,10,"M")]
    func color(_ ch: Character) -> NSColor? {
        let hex: [Character: Int] = ["Y": 0xffd982, "y": 0xfff0c4, "O": 0xffb043, "C": 0xfff1cf,
                                     "N": 0xc96f3f, "F": 0xf7c778, "T": 0xe69b3d, "B": 0xff9d6b,
                                     "K": 0x2b1c12, "W": 0xffffff, "H": 0xf2bc61, "M": 0x8a5a33]
        guard let v = hex[ch] else { return nil }
        return NSColor(red: CGFloat((v >> 16) & 255) / 255,
                       green: CGFloat((v >> 8) & 255) / 255,
                       blue: CGFloat(v & 255) / 255, alpha: 1)
    }
    var grid = base.map { Array($0) }
    for (x, y, ch) in eyes + mouth { grid[y][x] = ch }
    let size = NSSize(width: 18, height: 16)
    let img = NSImage(size: size)
    img.lockFocus()
    let cell: CGFloat = 18.0 / 17.0
    let rows = grid.count
    for (y, row) in grid.enumerated() {
        for (x, ch) in row.enumerated() {
            guard let c = color(ch) else { continue }
            c.setFill()
            // AppKit origin is bottom-left; flip the row index
            NSRect(x: CGFloat(x) * cell,
                   y: CGFloat(rows - 1 - y) * cell + 0.2,
                   width: cell + 0.05, height: cell + 0.05).fill()
        }
    }
    img.unlockFocus()
    return img
}
