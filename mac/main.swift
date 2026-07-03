// Focus Familiar — native macOS overlay
// A small creature that floats above your desktop, watches which app is
// frontmost (no permissions needed for that), and reacts: deep work feeds
// it, doomscrolling corrupts it. ⌥Space asks it what you were doing.

import Cocoa
import WebKit
import Carbon.HIToolbox

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

func classify(bundleId: String, title: String?, url: String?) -> String {
    if let k = deepApps[bundleId] { return k }
    for (p, k) in deepPrefixes where bundleId.hasPrefix(p) { return k }
    if distractionApps.contains(bundleId) { return "distraction" }
    if browserApps.contains(bundleId) {
        if let u = url?.lowercased(), let host = URL(string: u)?.host {
            for d in distractionDomains where host == d || host.hasSuffix("." + d) { return "distraction" }
            for (d, k) in deepDomains where host == d || host.hasSuffix("." + d) { return k }
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

let appleScriptForBrowser: [String: String] = [
    "com.google.Chrome": "tell application \"Google Chrome\" to if (count of windows) > 0 then return URL of active tab of front window",
    "com.brave.Browser": "tell application \"Brave Browser\" to if (count of windows) > 0 then return URL of active tab of front window",
    "com.microsoft.edgemac": "tell application \"Microsoft Edge\" to if (count of windows) > 0 then return URL of active tab of front window",
    "company.thebrowser.Browser": "tell application \"Arc\" to if (count of windows) > 0 then return URL of active tab of front window",
    "com.apple.Safari": "tell application \"Safari\" to if (count of documents) > 0 then return URL of front document",
]

func activeTabURL(bundleId: String) -> String? {
    guard let src = appleScriptForBrowser[bundleId],
          let script = NSAppleScript(source: src) else { return nil }
    var err: NSDictionary?
    let result = script.executeAndReturnError(&err)
    return result.stringValue
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

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
    var panel: OverlayPanel!
    var webView: WKWebView!
    var statusItem: NSStatusItem!
    var hotKeyRef: EventHotKeyRef?
    var browserTimer: Timer?
    var lastSent = ""
    var clickable = false          // user preference (menu toggle)
    var bubbleForcedClickable = false
    var paused = false

    static let characters: [(id: String, name: String)] = [
        ("wisp", "Wisp"), ("robocat", "Robo-cat"), ("panda", "Panda"),
        ("atom", "暗原子 · Dark Atom"), ("beaver", "Beaver"),
    ]

    func applicationDidFinishLaunching(_ note: Notification) {
        buildPanel()
        buildStatusItem()
        watchApps()
        registerHotKey()
        // greet with whatever is frontmost right now
        if let front = NSWorkspace.shared.frontmostApplication { send(app: front) }
    }

    // — panel + webview —
    func buildPanel() {
        let size = NSSize(width: 500, height: 320)
        guard let screen = NSScreen.main else { fatalError("no screen") }
        let vf = screen.visibleFrame
        let origin = NSPoint(x: vf.maxX - size.width - 12, y: vf.minY + 4)

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
        webView = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: cfg)
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 12.0, *) { webView.underPageBackgroundColor = .clear }

        let dir = Bundle.main.resourceURL!
        let url = dir.appendingPathComponent("overlay.html")
        webView.loadFileURL(url, allowingReadAccessTo: dir)
        panel.contentView = webView
        panel.orderFrontRegardless()
    }

    // — status bar —
    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "◐"
        let menu = NSMenu()

        let charMenu = NSMenu()
        for (id, name) in Self.characters {
            let item = NSMenuItem(title: name, action: #selector(pickCharacter(_:)), keyEquivalent: "")
            item.representedObject = id
            item.target = self
            charMenu.addItem(item)
        }
        let charRoot = NSMenuItem(title: "Character", action: nil, keyEquivalent: "")
        menu.addItem(charRoot)
        menu.setSubmenu(charMenu, for: charRoot)

        menu.addItem(NSMenuItem.separator())
        let ctx = NSMenuItem(title: "What was I doing?  (⌥Space)", action: #selector(toggleContextMenu), keyEquivalent: "")
        ctx.target = self; menu.addItem(ctx)

        let click = NSMenuItem(title: "Clickable familiar", action: #selector(toggleClickable(_:)), keyEquivalent: "")
        click.target = self; menu.addItem(click)

        let pause = NSMenuItem(title: "Pause watching", action: #selector(togglePause(_:)), keyEquivalent: "")
        pause.target = self; menu.addItem(pause)

        menu.addItem(NSMenuItem.separator())
        let ax = NSMenuItem(title: "Enable browser awareness…", action: #selector(enableAX), keyEquivalent: "")
        ax.target = self; menu.addItem(ax)

        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Quit Focus Familiar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        menu.delegate = self
        statusItem.menu = menu
    }

    // — app watching —
    func watchApps() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self, !self.paused,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self.send(app: app)
        }
        // browsers change "what you're doing" without app switches (tabs) —
        // poll the focused window title every 5s if we have AX permission
        browserTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, !self.paused,
                  let front = NSWorkspace.shared.frontmostApplication,
                  let bid = front.bundleIdentifier,
                  browserApps.contains(bid)
            else { return }
            self.send(app: front)
        }
    }

    func send(app: NSRunningApplication) {
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let bid = app.bundleIdentifier ?? "?"
        let name = app.localizedName ?? bid
        var title: String? = nil
        var url: String? = nil
        if browserApps.contains(bid) {
            url = activeTabURL(bundleId: bid)
            if url == nil, AXIsProcessTrusted() {
                title = focusedWindowTitle(pid: app.processIdentifier)
            }
        }
        let kind = classify(bundleId: bid, title: title, url: url)
        var display = name
        if let host = url.flatMap({ URL(string: $0)?.host }) {
            display = "\(name) — \(host.replacingOccurrences(of: "www.", with: ""))"
        } else if let t = title, !t.isEmpty {
            display = "\(name) — \(t.prefix(48))"
        }
        let key = "\(display)|\(kind)"
        guard key != lastSent else { return }
        lastSent = key
        js("famSetApp(\(jsonStr(display)), \(jsonStr(kind)), '')")
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
    func showContext() {
        bubbleForcedClickable = true
        panel.ignoresMouseEvents = false
        js("famToggleContext()")
    }
    @objc func toggleClickable(_ sender: NSMenuItem) {
        clickable.toggle()
        panel.ignoresMouseEvents = !clickable
    }
    @objc func togglePause(_ sender: NSMenuItem) {
        paused.toggle()
        js("famPause(\(paused))")
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

    // — JS bridge —
    func js(_ script: String) {
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "bridge",
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        if type == "bubble", let on = body["on"] as? Bool, !on, bubbleForcedClickable {
            bubbleForcedClickable = false
            panel.ignoresMouseEvents = !clickable
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        let current = UserDefaults.standard.string(forKey: "character") ?? "wisp"
        for item in menu.items {
            if let sub = item.submenu, item.title == "Character" {
                for c in sub.items { c.state = (c.representedObject as? String == current) ? .on : .off }
            }
            if item.title == "Clickable familiar" { item.state = clickable ? .on : .off }
            if item.title == "Pause watching" { item.state = paused ? .on : .off }
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
