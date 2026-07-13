// Focus Familiar — native macOS overlay
// A small creature that floats above your desktop, watches which app is
// frontmost (no permissions needed for that), and reacts: deep work feeds
// it, doomscrolling corrupts it. ⌥Space asks it what you were doing.

import Cocoa
import WebKit
import Carbon.HIToolbox
import ServiceManagement

// ── app classification ──────────────────────────────────────
// kind strings understood by overlay.html:
//   code / term / cad / paper / notes  → deep work (typed resources)
//   distraction / neutral

let deepApps: [String: String] = [
    "com.microsoft.VSCode": "code",
    "com.todesktop.230313mzl4w4u92": "code",   // Cursor
    "com.anthropic.claudefordesktop": "code",  // Claude desktop / Claude Code
    "com.apple.dt.Xcode": "code",
    "com.mathworks.matlab": "code",
    "com.apple.Terminal": "term",
    "com.googlecode.iterm2": "term",
    "dev.warp.Warp": "term",
    "org.alacritty": "term",
    "com.github.wez.wezterm": "term",
    "com.mitchellh.ghostty": "term",
    "notion.id": "notes",
    "md.obsidian": "notes",
    "com.apple.Preview": "paper",
    "net.sourceforge.skim-app.skim": "paper",
    "com.readdle.PDFExpert-Mac": "paper",
    "com.figma.Desktop": "cad",
    "com.autodesk.fusion360": "cad",
]
let deepPrefixes: [String: String] = [
    "org.kicad": "cad",
    "com.jetbrains": "code",
    "com.sublimetext": "code",
]
let distractionApps: Set<String> = [
    "com.twitter.twitter-mac",
    "maccatalyst.com.atebits.Tweetie2",       // X on mac
    "tv.twitch.desktop",
    "com.valvesoftware.steam",
]
let browserApps: Set<String> = [
    "com.apple.Safari", "com.google.Chrome", "com.google.Chrome.canary",
    "company.thebrowser.Browser", "org.mozilla.firefox", "com.microsoft.edgemac",
    "com.brave.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    "org.chromium.Chromium",
]
let distractionTitleWords = [
    "youtube", "shorts", "twitter", "· x", "/ x", "reddit", "tiktok",
    "bilibili", "哔哩", "小红书", "rednote", "instagram", "netflix", "twitch",
]
let deepTitleWords = [
    "arxiv", "github", "overleaf", "colab", "stack overflow", "huggingface",
    "wandb", "docs.google", "paper", "documentation",
]
// domain → kind, matched against the URL of the active browser tab
let distractionDomains = [
    "youtube.com", "youtu.be", "x.com", "twitter.com", "reddit.com",
    "tiktok.com", "bilibili.com", "xiaohongshu.com", "xhslink.com", "instagram.com",
    "netflix.com", "twitch.tv", "weibo.com", "douyin.com", "facebook.com",
]
let deepDomains: [String: String] = [
    "arxiv.org": "paper", "openreview.net": "paper", "overleaf.com": "paper",
    "github.com": "code", "stackoverflow.com": "code",
    "colab.research.google.com": "code", "huggingface.co": "code",
    "wandb.ai": "code", "docs.google.com": "notes", "notion.so": "notes",
]

// ── user rule overrides (Rules… window), persisted to UserDefaults ──
// key = bundle id or domain, value = kind
var ruleOverrides: [String: String] =
    UserDefaults.standard.dictionary(forKey: "ruleOverrides")?.compactMapValues { $0 as? String } ?? [:]

func saveOverrides() { UserDefaults.standard.set(ruleOverrides, forKey: "ruleOverrides") }

func overrideFor(host: String?) -> String? {
    guard let h = host else { return nil }
    if let o = ruleOverrides[h] { return o }
    for (k, v) in ruleOverrides where h.hasSuffix("." + k) { return v }
    return nil
}

// built-in classification, before user overrides (also used to show
// defaults in the Rules window, where key is a bundle id or domain)
func defaultKind(_ key: String) -> String {
    if browserApps.contains(key) { return "neutral" }
    if let k = deepApps[key] { return k }
    for (p, k) in deepPrefixes where key.hasPrefix(p) { return k }
    if distractionApps.contains(key) { return "distraction" }
    for d in distractionDomains where key == d || key.hasSuffix("." + d) { return "distraction" }
    for (d, k) in deepDomains where key == d || key.hasSuffix("." + d) { return k }
    return "neutral"
}

// YouTube is not one thing: shorts are junk food, lectures are spellbooks
func youtubeKind(path: String, title: String?) -> String {
    if path.hasPrefix("/shorts") { return "distraction" }
    let t = (title ?? "").lowercased()
    let learn = ["lecture", "tutorial", "course", "talk", "explained", "how to",
                 "paper", "deep dive", "seminar", "keynote", "lesson", "conference",
                 "walkthrough", "教程", "课程", "讲座", "公开课"]
    if learn.contains(where: { t.contains($0) }) { return "paper" }
    return "distraction"
}

func classify(bundleId: String, title: String?, url: String?) -> String {
    let host = url.flatMap { URL(string: $0.lowercased())?.host }
    if let o = overrideFor(host: host) { return o }
    if let o = ruleOverrides[bundleId] { return o }
    if let k = deepApps[bundleId] { return k }
    for (p, k) in deepPrefixes where bundleId.hasPrefix(p) { return k }
    if distractionApps.contains(bundleId) { return "distraction" }
    if browserApps.contains(bundleId) {
        if let h = host {
            if h == "youtube.com" || h.hasSuffix(".youtube.com") {
                return youtubeKind(path: url.flatMap { URL(string: $0)?.path } ?? "", title: title)
            }
            for d in distractionDomains where h == d || h.hasSuffix("." + d) { return "distraction" }
            for (d, k) in deepDomains where h == d || h.hasSuffix("." + d) { return k }
            return "neutral"
        }
        guard let t = title?.lowercased() else { return "neutral" }
        for w in distractionTitleWords where t.contains(w) { return "distraction" }
        for w in deepTitleWords where t.contains(w) { return "paper" }
        return "neutral"
    }
    return "neutral"
}

// ── browser tab URL via AppleScript (prompts for Automation once) ──

// returns "URL\ntitle" so one round-trip gets both
let appleScriptForBrowser: [String: String] = [
    "com.google.Chrome": "tell application \"Google Chrome\" to if (count of windows) > 0 then return (URL of active tab of front window) & \"\n\" & (title of active tab of front window)",
    "com.brave.Browser": "tell application \"Brave Browser\" to if (count of windows) > 0 then return (URL of active tab of front window) & \"\n\" & (title of active tab of front window)",
    "com.microsoft.edgemac": "tell application \"Microsoft Edge\" to if (count of windows) > 0 then return (URL of active tab of front window) & \"\n\" & (title of active tab of front window)",
    "company.thebrowser.Browser": "tell application \"Arc\" to if (count of windows) > 0 then return (URL of active tab of front window) & \"\n\" & (title of active tab of front window)",
    "com.apple.Safari": "tell application \"Safari\" to if (count of documents) > 0 then return (URL of front document) & \"\n\" & (name of front document)",
]

func activeTab(bundleId: String) -> (url: String, title: String)? {
    guard let src = appleScriptForBrowser[bundleId],
          let script = NSAppleScript(source: src) else { return nil }
    var err: NSDictionary?
    guard let s = script.executeAndReturnError(&err).stringValue else { return nil }
    let parts = s.split(separator: "\n", maxSplits: 1).map(String.init)
    return (parts.first ?? "", parts.count > 1 ? parts[1] : "")
}

// "Google Chrome" → "Chrome" etc. for the bubble
let shortNames: [String: String] = [
    "Google Chrome": "Chrome", "Visual Studio Code": "VS Code",
    "Microsoft Edge": "Edge", "Brave Browser": "Brave",
    "Adobe Acrobat Reader": "Acrobat",
]
func shortName(_ n: String) -> String { shortNames[n] ?? n }

// ── activity log: one JSONL file per day in Application Support.
// working memory (JS, in-RAM) → episodic log (disk) → replayed on launch ──

let logDir: URL = {
    let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("FocusFamiliar")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}()

func todayLogURL() -> URL {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return logDir.appendingPathComponent("activity-\(f.string(from: Date())).jsonl")
}

func appendLog(_ entry: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: entry),
          let line = String(data: data, encoding: .utf8) else { return }
    let url = todayLogURL()
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile()
        h.write((line + "\n").data(using: .utf8)!)
        try? h.close()
    } else {
        try? (line + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

func readTodayLog() -> String {
    guard let text = try? String(contentsOf: todayLogURL(), encoding: .utf8) else { return "[]" }
    let items = text.split(separator: "\n").joined(separator: ",")
    return "[\(items)]"
}

// past 6 days (today comes from the live in-page history, so skip it)
func readWeekLog() -> String {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
    var lines: [String] = []
    for i in 1...6 {
        guard let d = Calendar.current.date(byAdding: .day, value: -i, to: Date()) else { continue }
        let url = logDir.appendingPathComponent("activity-\(f.string(from: d)).jsonl")
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            lines.append(contentsOf: text.split(separator: "\n").map(String.init))
        }
    }
    return "[\(lines.joined(separator: ","))]"
}

// ── on-device AI classifier (Apple FoundationModels, macOS 26+).
// one call per unique (host, title), verdict cached forever in UserDefaults;
// heuristics remain the instant fallback ──

#if canImport(FoundationModels)
import FoundationModels
#endif

let aiInstructions = """
    You classify what someone is doing in a browser tab, and name the content.
    Categories (pick exactly one):
      code — programming, github, technical docs, terminals
      paper — reading papers/articles, lectures, educational videos, learning
      notes — writing, planning, note-taking
      neutral — email, search, shopping, logistics, misc
      distraction — social feeds, short videos, entertainment, gossip
    Canonical name: the underlying content's short natural name — a paper's
    title without site suffixes or IDs, a video's topic, or the site name.
    Reply with exactly one line, no explanation:  CATEGORY|CANONICAL NAME
    """

final class SmartClassifier {
    static let shared = SmartClassifier()
    private var cache: [String: String] =
        UserDefaults.standard.dictionary(forKey: "aiVerdicts")?.compactMapValues { $0 as? String } ?? [:]
    private var inFlight = Set<String>()

    // local OpenAI-compatible fallback (e.g. `mlx_lm.server --port 8080`)
    private let endpoint = UserDefaults.standard.string(forKey: "aiEndpoint") ?? "http://127.0.0.1:8080/v1"
    private var localAlive = false
    private var lastPing = Date.distantPast

    private var appleAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    var statusLine: String {
        pingLocal()
        if appleAvailable { return "AI: Apple on-device model active" }
        if localAlive { return "AI: local model at \(endpoint)" }
        return "AI: off — heuristics only (run mlx_lm.server on :8080)"
    }

    func pingLocal() {
        guard Date().timeIntervalSince(lastPing) > 60 else { return }
        lastPing = Date()
        guard let u = URL(string: endpoint + "/models") else { return }
        var req = URLRequest(url: u); req.timeoutInterval = 1.5
        URLSession.shared.dataTask(with: req) { _, r, _ in
            DispatchQueue.main.async { self.localAlive = (r as? HTTPURLResponse)?.statusCode == 200 }
        }.resume()
    }

    // returns cached verdict "(kind, canonicalLabel)" if known; else nil and
    // (optionally) kicks off a background classification
    func verdict(host: String, title: String, onNew: @escaping () -> Void) -> (kind: String, label: String)? {
        let key = host + "|" + title
        if let v = cache[key] {
            let parts = v.split(separator: "|", maxSplits: 1).map(String.init)
            return parts.count == 2 ? (parts[0], parts[1]) : nil
        }
        classifyInBackground(key: key, host: host, title: title, onDone: onNew)
        return nil
    }

    private func classifyInBackground(key: String, host: String, title: String, onDone: @escaping () -> Void) {
        pingLocal()
        guard !inFlight.contains(key), appleAvailable || localAlive else { return }
        inFlight.insert(key)
        let prompt = "Site: \(host)\nTab title: \(title)"
        let finish: (String?) -> Void = { reply in
            DispatchQueue.main.async {
                self.inFlight.remove(key)
                guard let reply else { return }
                let line = reply.split(separator: "\n").first.map(String.init) ?? ""
                let parts = line.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                let kinds = ["code", "paper", "notes", "neutral", "distraction"]
                guard parts.count == 2, kinds.contains(parts[0].lowercased()) else { return }
                self.cache[key] = "\(parts[0].lowercased())|\(parts[1].prefix(70))"
                UserDefaults.standard.set(self.cache, forKey: "aiVerdicts")
                onDone()
            }
        }
        if appleAvailable {
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                Task {
                    let session = LanguageModelSession(instructions: aiInstructions)
                    finish(try? await session.respond(to: prompt).content)
                }
            }
            #endif
        } else {
            classifyViaLocal(prompt: prompt, finish: finish)
        }
    }

    // OpenAI-compatible /chat/completions against the local server
    private func classifyViaLocal(prompt: String, finish: @escaping (String?) -> Void) {
        guard let u = URL(string: endpoint + "/chat/completions") else { return finish(nil) }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "messages": [["role": "system", "content": aiInstructions],
                         ["role": "user", "content": prompt]],
            "temperature": 0, "max_tokens": 50,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let msg = choices.first?["message"] as? [String: Any],
                  let content = msg["content"] as? String
            else { return finish(nil) }
            finish(content)
        }.resume()
    }
}

// seconds since the user last touched mouse or keyboard (no permissions needed)
func idleSeconds() -> Double {
    let types: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
    return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
}

// ── accessibility (optional, for browser tab titles) ────────

func axTrusted(prompt: Bool) -> Bool {
    let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(opts)
}

func focusedWindowTitle(pid: pid_t) -> String? {
    let appEl = AXUIElementCreateApplication(pid)
    var win: AnyObject?
    guard AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &win) == .success,
          let winEl = win else { return nil }
    var title: AnyObject?
    guard AXUIElementCopyAttributeValue(winEl as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success
    else { return nil }
    return title as? String
}

// ── the floating panel ──────────────────────────────────────

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// the panel can never become key, so without this every click inside the
// webview is swallowed as "first mouse" — buttons/tabs/dropdowns dead
final class OverlayWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var panel: OverlayPanel!
    var webView: WKWebView!
    var statusItem: NSStatusItem!
    var hotKeyRef: EventHotKeyRef?
    var browserTimer: Timer?
    var lastSent = ""
    var clickable = false          // user preference: always clickable (menu toggle)
    var bubbleOpen = false
    var paused = false
    // drag / hide state
    var hoverTimer: Timer?
    var dragTimer: Timer?
    var dragMouseStart = NSPoint.zero
    var dragFrameStart = NSPoint.zero
    var dragging = false
    var hidden = false             // tucked away at the right screen edge
    var overlayHidden = false      // fully hidden via the menu bar toggle
    var savedOrigin = NSPoint.zero // where to restore after unhiding
    var activationToken: NSObjectProtocol?  // MUST retain, or the observer dies
    var settingsWin: NSWindow?
    var settingsWeb: WKWebView?
    let gitWatcher = GitWatcher()
    var lockTokens: [NSObjectProtocol] = []
    var isIdle = false


    func applicationDidFinishLaunching(_ note: Notification) {
        buildPanel()
        buildStatusItem()
        watchApps()
        registerHotKey()
        startHoverTracking()
        pruneOldLogs()
        gitWatcher.onCommit = { [weak self] repo in
            self?.js("famProud('🎉 \(repo): commit shipped! +10 XP')")
        }
        gitWatcher.start()
        if !UserDefaults.standard.bool(forKey: "onboarded1") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.showSettings() }
        }
        // NOTE: initial send happens in webView(_:didFinish:) — calling
        // famSetApp before the page loads silently drops the event
    }

    // — panel + webview —
    func buildPanel() {
        let size = NSSize(width: 560, height: 320)
        guard let screen = NSScreen.main else { fatalError("no screen") }
        let vf = screen.visibleFrame
        var origin = NSPoint(x: vf.maxX - size.width - 12, y: vf.minY + 4)
        // restore last dragged position if it's still on some screen
        if let p = UserDefaults.standard.array(forKey: "panelOrigin") as? [Double], p.count == 2 {
            let saved = NSPoint(x: p[0], y: p[1])
            let rect = NSRect(origin: saved, size: size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) { origin = saved }
        }

        panel = OverlayPanel(contentRect: NSRect(origin: origin, size: size),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true          // ambient by default
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false

        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "bridge")
        webView = OverlayWebView(frame: NSRect(origin: .zero, size: size), configuration: cfg)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 12.0, *) { webView.underPageBackgroundColor = .clear }

        let dir = Bundle.main.resourceURL!
        let url = dir.appendingPathComponent("overlay.html")
        webView.loadFileURL(url, allowingReadAccessTo: dir)
        panel.contentView = webView
        overlayHidden = UserDefaults.standard.bool(forKey: "overlayHidden")
        if !overlayHidden { panel.orderFrontRegardless() }
    }

    // — status bar: LuLu icon + a short, visual menu —
    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let icon = luluStatusIcon() as NSImage? {
            statusItem.button?.image = icon
            statusItem.button?.imagePosition = .imageOnly
        } else {
            statusItem.button?.title = "◐"
        }

        func item(_ title: String, _ action: Selector?, _ key: String, _ symbol: String) -> NSMenuItem {
            let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
            it.target = self
            it.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            return it
        }

        let menu = NSMenu()
        menu.addItem(item("What was I doing?  (⌥Space)", #selector(openJournal), "j", "book"))

        let huntMenu = NSMenu()
        for min in [25, 50] {
            let it = NSMenuItem(title: "\(min) minutes", action: #selector(startHunt(_:)), keyEquivalent: "")
            it.representedObject = min; it.target = self
            huntMenu.addItem(it)
        }
        let huntRoot = item("Begin a hunt", nil, "", "scope")
        menu.addItem(huntRoot)
        menu.setSubmenu(huntMenu, for: huntRoot)

        menu.addItem(item("Journal as a page", #selector(openJournalPage), "o", "doc.richtext"))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(item("Settings…", #selector(showSettings), ",", "gearshape"))
        let hide = item("Hide familiar", #selector(toggleOverlay(_:)), "h", "eye.slash")
        hide.identifier = .init("hideToggle")
        menu.addItem(hide)

        menu.addItem(NSMenuItem.separator())
        let ai = NSMenuItem(title: "AI: checking…", action: nil, keyEquivalent: "")
        ai.isEnabled = false
        ai.identifier = .init("aiStatus")
        menu.addItem(ai)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Quit Focus Familiar", #selector(NSApplication.terminate(_:)), "q", "power"))

        menu.delegate = self
        statusItem.menu = menu
    }

    // — app watching —
    func watchApps() {
        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self, !self.paused,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self.send(app: app)
        }
        // 5s heartbeat: idle detection + browser tab re-polling.
        // idle >150s or a locked screen closes the open entry — otherwise an
        // unattended machine racks up hours of fake "deep work"
        browserTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, !self.paused else { return }
            let idle = idleSeconds()
            let idleLimit = UserDefaults.standard.object(forKey: "idleThreshold") as? Double ?? 150
            if !self.isIdle, idle > idleLimit {
                self.isIdle = true
                self.js("famIdle(true)")
            } else if self.isIdle, idle < 10 {
                self.isIdle = false
                self.lastSent = ""
                if let front = NSWorkspace.shared.frontmostApplication { self.send(app: front) }
            }
            guard !self.isIdle,
                  let front = NSWorkspace.shared.frontmostApplication,
                  let bid = front.bundleIdentifier,
                  browserApps.contains(bid) else { return }
            self.send(app: front)
        }
        // screen lock = hard idle, immediately
        let dnc = DistributedNotificationCenter.default()
        lockTokens.append(dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.isIdle = true
            self?.js("famIdle(true)")
        })
        lockTokens.append(dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.isIdle = false
            self?.lastSent = ""
            if let front = NSWorkspace.shared.frontmostApplication { self?.send(app: front) }
        })
    }

    func send(app: NSRunningApplication) {
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let bid = app.bundleIdentifier ?? "?"
        guard bid != "com.apple.loginwindow", bid != "com.apple.ScreenSaver.Engine" else { return }
        let name = shortName(app.localizedName ?? bid)
        var title: String? = nil
        var url: String? = nil
        if browserApps.contains(bid) {
            if let tab = activeTab(bundleId: bid) {
                url = tab.url
                title = tab.title.isEmpty ? nil : tab.title
            } else if AXIsProcessTrusted() {
                title = focusedWindowTitle(pid: app.processIdentifier)
            }
        }
        var kind = classify(bundleId: bid, title: title, url: url)
        var canon = ""
        remember(key: bid, label: name)
        var display = name
        if let host = url.flatMap({ URL(string: $0)?.host }) {
            let h = host.replacingOccurrences(of: "www.", with: "")
            remember(key: h, label: h)
            display = "\(name) — \(h)"
            // user override > on-device AI > heuristics
            let hasOverride = overrideFor(host: host) != nil || ruleOverrides[bid] != nil
            if !hasOverride, let t = title, !t.isEmpty,
               let v = SmartClassifier.shared.verdict(host: h, title: t, onNew: { [weak self] in
                   self?.lastSent = ""
                   if let front = NSWorkspace.shared.frontmostApplication { self?.send(app: front) }
               }) {
                kind = v.kind
                canon = v.label
            }
        }
        let detail = (title ?? "").prefix(90)
        let key = "\(display)|\(kind)|\(detail)|\(canon)"
        guard key != lastSent else { return }
        lastSent = key
        js("famSetApp(\(jsonStr(display)), \(jsonStr(kind)), \(jsonStr(String(detail))), \(jsonStr(url ?? "")), \(jsonStr(canon)))")
    }

    // — hotkey (⌥Space) via Carbon: works without accessibility permission —
    func registerHotKey() {
        let spec = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyPressed))]
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            let me = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async { me.showContext() }
            return noErr
        }, 1, spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        let hotKeyID = EventHotKeyID(signature: OSType(0x46464D4C), id: 1)  // 'FFML'
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // — actions —
    @objc func pickCharacter(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        js("famSetCharacter('\(id)')")
        UserDefaults.standard.set(id, forKey: "character")
    }
    @objc func toggleContextMenu() { showContext() }
    @objc func openJournal() {
        bubbleOpen = true
        panel.ignoresMouseEvents = false
        js("famToggleJournal()")
    }
    func showContext() {
        bubbleOpen = true
        panel.ignoresMouseEvents = false
        js("famToggleContext()")
    }
    @objc func toggleClickable(_ sender: NSMenuItem) {
        clickable.toggle()
    }

    // ── hover hot-zone: click-through everywhere except over the creature ──
    // the stage sits in the panel's bottom-right (right:10 bottom:6, ~150px)
    func creatureRect() -> NSRect {
        let f = panel.frame
        return NSRect(x: f.maxX - 170, y: f.minY, width: 170, height: 175)
    }
    func startHoverTracking() {
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, !self.dragging else { return }
            let interactive = self.bubbleOpen || self.clickable
                || self.creatureRect().contains(NSEvent.mouseLocation)
            self.panel.ignoresMouseEvents = !interactive
        }
    }

    // ── drag: window follows the cursor between dragStart/dragEnd from JS ──
    func beginDrag() {
        dragging = true
        dragMouseStart = NSEvent.mouseLocation
        dragFrameStart = panel.frame.origin
        dragTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard NSEvent.pressedMouseButtons & 1 == 1 else { self.endDrag(); return }
            let m = NSEvent.mouseLocation
            self.panel.setFrameOrigin(NSPoint(x: self.dragFrameStart.x + m.x - self.dragMouseStart.x,
                                              y: self.dragFrameStart.y + m.y - self.dragMouseStart.y))
        }
    }
    func endDrag() {
        dragTimer?.invalidate(); dragTimer = nil
        dragging = false
        let vf = (panel.screen ?? NSScreen.main!).visibleFrame
        let mx = NSEvent.mouseLocation.x
        if mx > vf.maxX - 40 {
            hide(vf: vf, left: false)     // dropped at the right edge → tuck away
        } else if mx < vf.minX + 40 {
            hide(vf: vf, left: true)      // …or the left edge
        } else {
            hidden = false
            UserDefaults.standard.set([panel.frame.origin.x, panel.frame.origin.y], forKey: "panelOrigin")
        }
    }

    // ── edge-hide: leave a ~30px sliver of creature peeking in.
    // the creature sits in the panel's right ~[width-160, width-10],
    // so the offsets differ per side ──
    func hide(vf: NSRect, left: Bool) {
        if !hidden { savedOrigin = NSPoint(x: vf.maxX - panel.frame.width - 12, y: panel.frame.origin.y) }
        hidden = true
        let x = left ? vf.minX + 40 - panel.frame.width : vf.maxX + 130 - panel.frame.width
        panel.setFrameOrigin(NSPoint(x: x, y: panel.frame.origin.y))
    }
    func unhide() {
        hidden = false
        panel.setFrameOrigin(savedOrigin)
        UserDefaults.standard.set([savedOrigin.x, savedOrigin.y], forKey: "panelOrigin")
    }
    @objc func togglePause(_ sender: NSMenuItem) {
        paused.toggle()
        js("famPause(\(paused))")
    }
    @objc func toggleOverlay(_ sender: NSMenuItem) {
        overlayHidden.toggle()
        UserDefaults.standard.set(overlayHidden, forKey: "overlayHidden")
        if overlayHidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }
    @objc func toggleLogin(_ sender: NSMenuItem) {
        let svc = SMAppService.mainApp
        if svc.status == .enabled { try? svc.unregister() } else { try? svc.register() }
    }
    @objc func toggleSounds(_ sender: NSMenuItem) {
        let d = UserDefaults.standard
        d.set(!d.bool(forKey: "soundOn"), forKey: "soundOn")
    }
    @objc func startHunt(_ sender: NSMenuItem) {
        guard let min = sender.representedObject as? Int else { return }
        js("famPomodoro(\(min))")
    }

    // write today's journal as markdown next to the activity logs + clipboard
    @objc func exportJournal() {
        webView.evaluateJavaScript("famExportMD()") { result, _ in
            guard let md = result as? String else { return }
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            let dir = logDir.appendingPathComponent("exports")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("journal-\(f.string(from: Date())).md")
            try? md.write(to: url, atomically: true, encoding: .utf8)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(md, forType: .string)
            let a = NSAlert()
            a.messageText = "Journal exported"
            a.informativeText = "Copied to clipboard and saved to \(url.path)"
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
        }
    }

    // render today's journal as a standalone page and open it in the browser.
    // same dated filename each time — newer exports overwrite older ones.
    @objc func openJournalPage() {
        webView.evaluateJavaScript("famExportHTML()") { result, _ in
            guard let html = result as? String else { return }
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            let dir = logDir.appendingPathComponent("exports")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("journal-\(f.string(from: Date())).html")
            try? html.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
        }
    }

    // show the level-up spectacle without granting XP
    @objc func previewEvolution() {
        js("""
        (() => { const ring = document.getElementById('ring') || (() => {
            const r = document.createElement('div'); r.className='ring'; r.id='ring';
            document.getElementById('stage').appendChild(r); return r; })();
          ring.classList.remove('burst'); void ring.offsetWidth; ring.classList.add('burst');
          Fam.sparkle(9); toast('✦ evolution preview ✦'); })()
        """)
        victoryWalk()
        if UserDefaults.standard.bool(forKey: "soundOn") { NSSound(named: "Glass")?.play() }
    }
    @objc func enableAX() {
        if axTrusted(prompt: true) {
            let a = NSAlert()
            a.messageText = "Browser awareness is on"
            a.informativeText = "The familiar can now tell YouTube from arXiv by reading the focused window's title."
            a.runModal()
        }
        // if not trusted, macOS shows the System Settings prompt itself
    }

    // — Rules… window: reclassify any seen app or site —
    var rulesWindow: NSWindow?
    var rulesTable: NSTableView?
    var rulesKeys: [String] = []          // row → key (bundle id or domain)
    var seenItems: [String: String] {     // key → display label
        get { UserDefaults.standard.dictionary(forKey: "seenItems")?.compactMapValues { $0 as? String } ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "seenItems") }
    }
    func remember(key: String, label: String) {
        var s = seenItems
        if s[key] != label { s[key] = label; seenItems = s }
    }

    static let kinds: [(id: String, label: String)] = [
        ("code", "Deep — code"), ("term", "Deep — terminal"), ("cad", "Deep — CAD/design"),
        ("paper", "Deep — reading"), ("notes", "Deep — notes"),
        ("neutral", "Neutral"), ("distraction", "Distraction"),
    ]

    @objc func openRules() {
        let seen = seenItems
        rulesKeys = seen.keys.sorted { (seen[$0] ?? $0).lowercased() < (seen[$1] ?? $1).lowercased() }

        if rulesWindow == nil {
            let table = NSTableView()
            table.rowHeight = 26
            table.dataSource = self
            table.delegate = self
            let cName = NSTableColumn(identifier: .init("name")); cName.title = "App / site"; cName.width = 250
            let cKind = NSTableColumn(identifier: .init("kind")); cKind.title = "Counts as"; cKind.width = 150
            table.addTableColumn(cName); table.addTableColumn(cKind)

            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 430, height: 380))
            scroll.documentView = table
            scroll.hasVerticalScroller = true

            let win = NSWindow(contentRect: scroll.frame,
                               styleMask: [.titled, .closable, .resizable],
                               backing: .buffered, defer: false)
            win.title = "Focus Rules — what counts as deep work"
            win.contentView = scroll
            win.isReleasedWhenClosed = false
            win.center()
            rulesWindow = win
            rulesTable = table
        }
        rulesTable?.reloadData()
        NSApp.activate(ignoringOtherApps: true)
        rulesWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func rulePicked(_ sender: NSPopUpButton) {
        let row = sender.tag
        guard row >= 0, row < rulesKeys.count,
              let kind = sender.selectedItem?.representedObject as? String else { return }
        let key = rulesKeys[row]
        if kind == defaultKind(key) { ruleOverrides.removeValue(forKey: key) }
        else { ruleOverrides[key] = kind }
        saveOverrides()
        lastSent = ""                     // force re-send so the change shows immediately
        if let front = NSWorkspace.shared.frontmostApplication { send(app: front) }
    }

    // — JS bridge —
    func js(_ script: String) {
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if message.name == "settings" { handleSettings(body); return }
        guard message.name == "bridge",
              let type = body["type"] as? String else { return }
        switch type {
        case "bubble":
            bubbleOpen = (body["on"] as? Bool) ?? false
        case "dragStart":
            beginDrag()
        case "dragEnd":
            endDrag()
        case "famClick":
            if hidden { unhide() } else { showContext() }
        case "ctxMenu":
            let m = NSMenu()
            let hideIt = NSMenuItem(title: overlayHidden ? "Show familiar" : "Hide familiar",
                                    action: #selector(toggleOverlay(_:)), keyEquivalent: "")
            hideIt.target = self
            hideIt.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)
            m.addItem(hideIt)
            let settingsIt = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: "")
            settingsIt.target = self
            settingsIt.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
            m.addItem(settingsIt)
            m.addItem(NSMenuItem.separator())
            m.addItem(NSMenuItem(title: "Quit Focus Familiar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
            m.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        case "log":
            if let entry = body["entry"] as? [String: Any] { appendLog(entry) }
        case "levelUp":
            victoryWalk()
            playSound("Glass")
        case "sound":
            // gain = soft tick, streak = bright ping, poison = low thud
            let map = ["gain": "Tink", "streak": "Ping", "poison": "Basso"]
            if let n = body["name"] as? String, let snd = map[n] { playSound(snd) }
        default:
            break
        }
    }

    func playSound(_ name: String) {
        guard UserDefaults.standard.bool(forKey: "soundOn") else { return }
        NSSound(named: name)?.play()
    }

    // ── milestone moment: waddle across the screen bottom and back ──
    var walkTimer: Timer?
    func victoryWalk() {
        guard walkTimer == nil, !dragging, !overlayHidden, !hidden else { return }
        let vf = (panel.screen ?? NSScreen.main!).visibleFrame
        let home = panel.frame.origin
        let target = vf.minX + 160 - panel.frame.width   // creature reaches the left screen edge
        let start = Date()
        let dur = 10.0
        js("famWalking(true)")
        walkTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            let p = Date().timeIntervalSince(start) / dur
            if p >= 1 {
                t.invalidate(); self.walkTimer = nil
                self.panel.setFrameOrigin(home)
                self.js("famWalking(false)")
                return
            }
            let tri = p < 0.5 ? p * 2 : (1 - p) * 2       // out and back
            let eased = tri * tri * (3 - 2 * tri)          // smoothstep
            self.panel.setFrameOrigin(NSPoint(x: home.x + (target - home.x) * eased, y: home.y))
        }
        RunLoop.main.add(walkTimer!, forMode: .common)
    }

    // replay today's persisted history once the overlay page is ready,
    // then greet with whatever is frontmost right now
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === settingsWeb { pushSettingsState(); return }
        js("famLoadHistory(\(readTodayLog()))")
        js("famLoadWeek(\(readWeekLog()))")
        if let front = NSWorkspace.shared.frontmostApplication { send(app: front) }
    }
}

extension AppDelegate: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { rulesKeys.count }

    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        guard row < rulesKeys.count else { return nil }
        let key = rulesKeys[row]
        if col?.identifier.rawValue == "name" {
            let label = seenItems[key] ?? key
            let tf = NSTextField(labelWithString: label == key ? key : "\(label)  ·  \(key)")
            tf.lineBreakMode = .byTruncatingTail
            tf.toolTip = key
            return tf
        }
        let pop = NSPopUpButton()
        pop.bezelStyle = .rounded
        pop.controlSize = .small
        for k in Self.kinds {
            pop.addItem(withTitle: k.label)
            pop.lastItem?.representedObject = k.id
        }
        let current = ruleOverrides[key] ?? defaultKind(key)
        if let idx = Self.kinds.firstIndex(where: { $0.id == current }) { pop.selectItem(at: idx) }
        pop.tag = row
        pop.target = self
        pop.action = #selector(rulePicked(_:))
        return pop
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        let current = UserDefaults.standard.string(forKey: "character") ?? "lulu"
        for item in menu.items {
            if let sub = item.submenu, item.title == "Familiar" {
                for c in sub.items { c.state = (c.representedObject as? String == current) ? .on : .off }
            }

            if item.identifier?.rawValue == "aiStatus" { item.title = SmartClassifier.shared.statusLine }
            if item.identifier?.rawValue == "hideToggle" { item.title = overlayHidden ? "Show familiar" : "Hide familiar" }
        }
    }
}

func jsonStr(_ s: String) -> String {
    let data = try! JSONEncoder().encode([s])
    let arr = String(data: data, encoding: .utf8)!
    return String(arr.dropFirst().dropLast())    // ["…"] → "…"
}

// ── boot ────────────────────────────────────────────────────
let app = NSApplication.shared
app.setActivationPolicy(.accessory)     // no dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
