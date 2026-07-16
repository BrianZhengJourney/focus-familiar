// Mimo — productization layer
// settings window (HTML), data retention/eraser, git-commit celebration

import Cocoa
import WebKit
import ServiceManagement
import UniformTypeIdentifiers

struct PendingCharacterSheetDraft {
    let pngData: Data
    let temperamentID: String
    let quality: PetGenerationQuality
    let createdAt: Date
}

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
    guard let entries = try? FileManager.default.contentsOfDirectory(
        at: logDir, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
    for entry in entries {
        let name = entry.lastPathComponent
        if name.hasPrefix("activity-") && entry.pathExtension == "jsonl" {
            try? FileManager.default.removeItem(at: entry)
        } else if name == "exports" {
            try? FileManager.default.removeItem(at: entry)
        }
    }
}

func historyStats() -> String {
    guard let files = try? FileManager.default.contentsOfDirectory(at: logDir, includingPropertiesForKeys: [.fileSizeKey]) else { return voice("还没有数据", "no data yet") }
    let logs = files.filter { $0.lastPathComponent.hasPrefix("activity-") }
    let bytes = logs.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
    return voice("本地保存了 \(logs.count) 天 · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) · 全部只在这台 Mac 上",
                 "\(logs.count) day\(logs.count == 1 ? "" : "s") on disk · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) · all local")
}

// ── automation permission status (no prompt) ────────────────

func automationStatus(_ bundleId: String) -> OSStatus {
    let desc = NSAppleEventDescriptor(bundleIdentifier: bundleId)
    guard let aeDesc = desc.aeDesc else { return -1 }
    return AEDeterminePermissionToAutomateTarget(aeDesc, typeWildCard, typeWildCard, false)
}

var appIconCache: [String: String] = [:]

func appIconDataURI(_ bundleId: String) -> String? {
    if let hit = appIconCache[bundleId] { return hit.isEmpty ? nil : hit }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
        appIconCache[bundleId] = ""
        return nil
    }
    let icon = NSWorkspace.shared.icon(forFile: url.path)
    let small = NSImage(size: NSSize(width: 32, height: 32))
    small.lockFocus()
    icon.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
    small.unlockFocus()
    guard let tiff = small.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return nil }
    let uri = "data:image/png;base64," + png.base64EncodedString()
    appIconCache[bundleId] = uri
    return uri
}

func petReferenceDataURI(_ url: URL) -> String? {
    guard let source = NSImage(contentsOf: url), source.size.width > 0, source.size.height > 0 else { return nil }
    let canvasSide: CGFloat = 768
    let scale = min(canvasSide / source.size.width, canvasSide / source.size.height)
    let fitted = NSSize(width: source.size.width * scale, height: source.size.height * scale)
    let destination = NSRect(x: (canvasSide - fitted.width) / 2, y: (canvasSide - fitted.height) / 2,
                             width: fitted.width, height: fitted.height)
    let image = NSImage(size: NSSize(width: canvasSide, height: canvasSide))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(in: destination, from: NSRect(origin: .zero, size: source.size),
                operation: .copy, fraction: 1)
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return nil }
    return "data:image/png;base64," + png.base64EncodedString()
}

func validGeneratedPetSpec(_ spec: [String: Any]) -> Bool {
    func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        guard let number = value as? NSNumber,
              number.doubleValue.isFinite,
              number.doubleValue.rounded() == number.doubleValue else { return nil }
        return number.intValue
    }
    guard integer(spec["schemaVersion"]) == 1,
          let name = spec["name"] as? String,
          (1...60).contains(name.count),
          !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
          let palette = spec["PAL"] as? [String: String], (7...16).contains(palette.count),
          Set(["P", "L", "A", "D", "K", "W", "M"]).isSubset(of: Set(palette.keys)),
          palette.allSatisfy({ key, value in
              key.count == 1 && value.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil
          }),
          let base = spec["BASE"] as? [String], (6...24).contains(base.count),
          let width = base.first?.count, (6...24).contains(width) else { return false }

    let height = base.count
    let allowed = Set(palette.keys.compactMap(\.first)).union([Character(".")])
    func validRows(_ rows: [String]) -> Bool {
        rows.count == height && rows.joined().contains(where: { $0 != "." }) && rows.allSatisfy { row in
            row.count == width && row.allSatisfy { allowed.contains($0) }
        }
    }
    guard validRows(base),
          let forms = spec["EVOLUTION_BASES"] as? [[String]],
          (1...3).contains(forms.count), forms.allSatisfy(validRows),
          let face = spec["face"] as? [String: Any],
          let lx = integer(face["lx"]), let rx = integer(face["rx"]),
          let y = integer(face["y"]), let mx = integer(face["mx"]), let my = integer(face["my"]),
          (1..<(width - 2)).contains(lx), (lx + 2..<(width - 1)).contains(rx),
          (1..<(height - 1)).contains(y), (1..<(width - 1)).contains(mx),
          (0..<(height - 1)).contains(my) else { return false }

    func validPixels(_ value: Any?) -> Bool {
        guard let pixels = value as? [Any], (1...64).contains(pixels.count) else { return false }
        return pixels.allSatisfy { value in
            guard let pixel = value as? [Any], pixel.count == 3,
                  let x = integer(pixel[0]), let y = integer(pixel[1]),
                  let token = pixel[2] as? String, token.count == 1,
                  palette[token] != nil else { return false }
            return (0..<width).contains(x) && (0..<height).contains(y)
        }
    }
    guard validPixels(spec["EYES"]), validPixels(spec["MOUTH"]) else { return false }

    if let viewBox = spec["vb"] as? String {
        let tokens = viewBox.split(whereSeparator: \.isWhitespace)
        let values = tokens.compactMap { Double(String($0)) }
        guard tokens.count == 4, values.count == 4, values.allSatisfy(\.isFinite),
              values[0] >= -64, values[1] >= -64,
              values[2] > 0, values[2] <= 64, values[3] > 0, values[3] <= 64 else { return false }
    }
    return true
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
    private var mtimes: [String: Date] = [:]
    var onCommit: ((String) -> Void)?
    private let queue = DispatchQueue(label: "com.brianzheng.mimo.git-watcher", qos: .utility)

    static func projectsDir() -> URL {
        if let p = UserDefaults.standard.string(forKey: "projectsDir") {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/GitHub")
    }

    func start() {
        scheduleScan(initial: true)
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.scheduleScan(initial: false)
        }
    }

    func resetAndScan() {
        queue.async { [weak self] in
            guard let self else { return }
            self.mtimes.removeAll()
            self.scan(initial: true)
        }
    }

    private func scheduleScan(initial: Bool) {
        queue.async { [weak self] in self?.scan(initial: initial) }
    }

    private func scan(initial: Bool) {
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
                DispatchQueue.main.async { [weak self] in self?.onCommit?(key) }
            }
        }
    }
}

// ── the one settings window (hosts settings.html) ───────────

extension AppDelegate {

    func settingsCall(_ function: String, _ payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        settingsWeb?.evaluateJavaScript("\(function)(\(json))", completionHandler: nil)
    }

    func storedCustomPetSpec() -> [String: Any]? {
        guard let json = UserDefaults.standard.string(forKey: "customPetSpec"),
              let data = json.data(using: .utf8),
              let spec = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              validGeneratedPetSpec(spec) else { return nil }
        return spec
    }

    func restoreCustomPetIfNeeded() {
        if let spec = storedCustomPetSpec(),
           let data = try? JSONSerialization.data(withJSONObject: spec),
           let json = String(data: data, encoding: .utf8) {
            js("famRegisterPrototypePet(\(json), false)")
        }
        let customPets = (try? customPetStore.listRuntimeSpecs()) ?? []
        for spec in customPets {
            guard let data = try? JSONSerialization.data(withJSONObject: spec),
                  let json = String(data: data, encoding: .utf8) else { continue }
            js("famRegisterCustomPet(\(json), false)")
        }
        let builtins: Set<String> = ["lulu", "clawd", "nat"]
        let customIDs = Set(customPets.compactMap { $0["characterID"] as? String })
        let requested = UserDefaults.standard.string(forKey: "character") ?? "lulu"
        let valid = builtins.contains(requested)
            || (requested == "prototype" && storedCustomPetSpec() != nil)
            || customIDs.contains(requested)
        let selected = valid ? requested : "lulu"
        if selected != requested { UserDefaults.standard.set(selected, forKey: "character") }
        js("famSetCharacter(\(jsonStr(selected)))")
    }

    @objc func showSettings() {
        if let w = settingsWin {
            pushSettingsState()
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "settings")
        cfg.setURLSchemeHandler(CustomPetAssetSchemeHandler(store: customPetStore),
                                forURLScheme: CustomPetStore.scheme)
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 560, height: 780), configuration: cfg)
        web.navigationDelegate = self
        if let dir = Bundle.main.resourceURL {
            web.loadFileURL(dir.appendingPathComponent("settings.html"), allowingReadAccessTo: dir)
        }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 780),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = voice("Mimo 米墨", "Mimo")
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
        case 0: return voice("已授权——米墨可以读取标签页地址", "granted — Mimo can read tab addresses")
        case -1744: return voice("尚未启用", "not yet enabled")
        case -1743: return voice("已拒绝——系统设置 → 隐私与安全性 → 自动化", "denied — System Settings → Privacy → Automation")
        case -600: return voice("打开浏览器，然后点击启用", "open your browser, then click Enable")
        default: return voice("找不到默认浏览器", "no default browser found")
        }
    }

    func pushSettingsState() {
        let d = UserDefaults.standard
        let bid = defaultBrowserBundleId()
        let code = bid.map { automationStatus($0) } ?? OSStatus(-1)
        var rules: [[String: Any]] = []
        for (key, label) in seenItems {
            var row: [String: Any] = ["key": key, "label": label,
                                      "kind": ruleOverrides[key] ?? defaultKind(key)]
            if let uri = appIconDataURI(key) { row["icon"] = uri }          // local app icon only
            rules.append(row)
        }
        rules.sort { ($0["label"] as? String ?? "").lowercased() < ($1["label"] as? String ?? "").lowercased() }
        var state: [String: Any] = [
            "character": d.string(forKey: "character") ?? "lulu",
            "language": voiceLanguage(),
            "permCode": Int(code),
            "permText": permLine(code),
            "rules": rules,
            "idle": d.object(forKey: "idleThreshold") as? Double ?? 150,
            "retention": d.object(forKey: "retentionDays") as? Int ?? 90,
            "sounds": d.bool(forKey: "soundOn"),
            "login": SMAppService.mainApp.status == .enabled,
            "stats": historyStats(),
            "projects": GitWatcher.projectsDir().lastPathComponent,
            "pixelLabConfigured": MimoSecret.pixelLab.isConfigured,
            "openAIConfigured": MimoSecret.openAI.isConfigured,
            "imageQuality": PetGenerationQuality.resolve(d.string(forKey: "petImageQuality")).rawValue,
        ]
        if let customPet = storedCustomPetSpec() { state["customPet"] = customPet }
        state["customPets"] = (try? customPetStore.listRuntimeSpecs()) ?? []
        guard let data = try? JSONSerialization.data(withJSONObject: state),
              let json = String(data: data, encoding: .utf8) else { return }
        settingsWeb?.evaluateJavaScript("initSettings(\(json))", completionHandler: nil)
    }

    func handleSettings(_ body: [String: Any]) {
        let d = UserDefaults.standard
        switch body["type"] as? String ?? "" {
        case "pick":
            if let id = body["id"] as? String {
                let builtins: Set<String> = ["lulu", "clawd", "nat"]
                let allowed = builtins.contains(id)
                    || (id == "prototype" && storedCustomPetSpec() != nil)
                    || (try? customPetStore.runtimeSpec(characterID: id)) != nil
                if allowed {
                    js("famSetCharacter(\(jsonStr(id)))")
                    d.set(id, forKey: "character")
                }
            }
        case "petPrototype":
            if let spec = body["spec"] as? [String: Any],
               validGeneratedPetSpec(spec),
               JSONSerialization.isValidJSONObject(spec),
               let data = try? JSONSerialization.data(withJSONObject: spec),
               let json = String(data: data, encoding: .utf8) {
                d.set(json, forKey: "customPetSpec")
                d.set("prototype", forKey: "character")
                js("famSetPrototypePet(\(json))")
                revealOverlay()
            }
        case "petUpload":
            let panel = NSOpenPanel()
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.image]
            panel.message = voice("为你的小伴灵选择一张参考图片", "Choose a reference for your tiny familiar")
            if panel.runModal() == .OK, let url = panel.url,
               let uri = petReferenceDataURI(url) {
                let name = url.deletingPathExtension().lastPathComponent
                settingsWeb?.evaluateJavaScript(
                    "loadPetImageData(\(jsonStr(uri)), \(jsonStr(name)))",
                    completionHandler: nil)
            }
        case "petSaveKeys":
            var failed: [String] = []
            if let value = body["pixelLab"] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !MimoSecret.pixelLab.write(value) { failed.append("PixelLab") }
            }
            if let value = body["openAI"] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !MimoSecret.openAI.write(value) { failed.append("OpenAI") }
            }
            var keyState: [String: Any] = [
                "pixelLabConfigured": MimoSecret.pixelLab.isConfigured,
                "openAIConfigured": MimoSecret.openAI.isConfigured,
            ]
            if !failed.isEmpty {
                keyState["failed"] = failed
                keyState["error"] = voice("无法安全保存：\(failed.joined(separator: ", "))", "Could not save securely: \(failed.joined(separator: ", "))")
            }
            settingsCall("petKeysSaved", keyState)
        case "petClearKey":
            let provider = body["provider"] as? String == "openai" ? "OpenAI" : "PixelLab"
            let cleared = provider == "OpenAI" ? MimoSecret.openAI.write("") : MimoSecret.pixelLab.write("")
            var keyState: [String: Any] = [
                "pixelLabConfigured": MimoSecret.pixelLab.isConfigured,
                "openAIConfigured": MimoSecret.openAI.isConfigured,
                "cleared": provider,
            ]
            if !cleared { keyState["error"] = voice("无法清除 \(provider)", "Could not clear \(provider)") }
            settingsCall("petKeysSaved", keyState)
        case "petCancel":
            if let id = body["requestID"] as? String {
                petGenerator.cancel(id)
                pendingCharacterSheets.removeValue(forKey: id)
                if activePetGenerationID == id {
                    activePetGenerationID = nil
                }
            }
        case "petQuality":
            let quality = PetGenerationQuality.resolve(body["quality"] as? String)
            d.set(quality.rawValue, forKey: "petImageQuality")
        case "petGenerateSheet":
            let requestID = (body["requestID"] as? String) ?? UUID().uuidString
            guard let source = body["source"] as? String, source.hasPrefix("data:image/"),
                  source.count < 16_000_000,
                  let sourceData = PetGenerationCoordinator.dataFromDataURI(source),
                  sourceData.count <= 12 * 1024 * 1024,
                  PetGenerationCoordinator.isSupportedImageData(sourceData) else {
                settingsCall("petSheetError", [
                    "requestID": requestID,
                    "message": voice("参考图片无效", "Invalid reference image"),
                ])
                return
            }
            let temperamentID = body["temperamentID"] as? String
            let profile = CustomPetTemperaments.profile(for: temperamentID)
            let likeness = max(0, min(1, body["likeness"] as? Double ?? 0.58))
            let quality = PetGenerationQuality.resolve(body["quality"] as? String)
            d.set(quality.rawValue, forKey: "petImageQuality")
            if let previous = activePetGenerationID {
                petGenerator.cancel(previous)
                pendingCharacterSheets.removeValue(forKey: previous)
            }
            pendingCharacterSheets = pendingCharacterSheets.filter {
                Date().timeIntervalSince($0.value.createdAt) < 15 * 60
            }
            activePetGenerationID = requestID
            petGenerator.generateCharacterSheet(requestID: requestID, sourceDataURI: source,
                                                personalityVisual: profile.promptFragment,
                                                likeness: likeness, quality: quality,
                                                progress: { [weak self] phase, detail in
                guard let self, self.activePetGenerationID == requestID else { return }
                var payload: [String: Any] = ["requestID": requestID, "phase": phase]
                if let detail { payload["detail"] = detail }
                self.settingsCall("petSheetProgress", payload)
            }, completion: { [weak self] result in
                guard let self, self.activePetGenerationID == requestID else { return }
                switch result {
                case .success(let rawSheet):
                    self.settingsCall("petSheetProgress", ["requestID": requestID, "phase": "extracting"])
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        let processed = Result { try CharacterSheetProcessor.process(pngData: rawSheet) }
                        DispatchQueue.main.async {
                            guard let self, self.activePetGenerationID == requestID else { return }
                            switch processed {
                            case .success(let sheet):
                                self.pendingCharacterSheets[requestID] = PendingCharacterSheetDraft(
                                    pngData: sheet.pngData, temperamentID: profile.id,
                                    quality: quality, createdAt: Date())
                                self.settingsCall("petSheetResult", [
                                    "requestID": requestID, "draftID": requestID,
                                    "sheet": PetGenerationCoordinator.dataURI(sheet.pngData),
                                    "quality": quality.rawValue,
                                ])
                            case .failure(let error):
                                self.settingsCall("petSheetError", [
                                    "requestID": requestID, "message": error.localizedDescription,
                                ])
                            }
                            self.activePetGenerationID = nil
                        }
                    }
                case .failure(let error):
                    self.settingsCall("petSheetError", [
                        "requestID": requestID, "message": error.localizedDescription,
                    ])
                    self.activePetGenerationID = nil
                }
            })
        case "petInstallRaster":
            guard let draftID = body["draftID"] as? String,
                  let draft = pendingCharacterSheets[draftID] else {
                settingsCall("petSheetError", [
                    "requestID": body["draftID"] as? String ?? "",
                    "message": voice("这张预览已过期，请重新生成", "This preview expired; generate it again"),
                ])
                return
            }
            let requestedName = (body["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let name = requestedName.isEmpty ? voice("我的小伴灵", "My little familiar") : String(requestedName.prefix(60))
            let profile = CustomPetTemperaments.profile(for: draft.temperamentID)
            do {
                let spec = try customPetStore.install(pngData: draft.pngData, name: name,
                                                      temperamentID: profile.id, accent: profile.accent)
                pendingCharacterSheets.removeValue(forKey: draftID)
                guard let characterID = spec["characterID"] as? String,
                      JSONSerialization.isValidJSONObject(spec),
                      let data = try? JSONSerialization.data(withJSONObject: spec),
                      let json = String(data: data, encoding: .utf8) else {
                    throw CustomPetStoreError.corruptManifest
                }
                d.set(characterID, forKey: "character")
                js("famSetCustomPet(\(json))")
                settingsCall("customPetAdopted", ["spec": spec])
                pushSettingsState()
                revealOverlay()
            } catch {
                settingsCall("petSheetError", ["requestID": draftID, "message": error.localizedDescription])
            }
        case "petDelete":
            guard let characterID = body["characterID"] as? String else { return }
            let runtime = try? customPetStore.runtimeSpec(characterID: characterID)
            let legacy = characterID == "prototype" ? storedCustomPetSpec() : nil
            guard let name = (runtime?["name"] as? String) ?? (legacy?["name"] as? String) else {
                settingsCall("petDeleteFailed", ["message": voice("找不到这个 DIY 角色", "This DIY familiar could not be found")])
                return
            }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = voice("让「\(name)」离开桌面？", "Remove “\(name)” from Mimo?")
            alert.informativeText = voice(
                "这会删除它的三段形态。成长等级、活动记录和 API Key 会保留。此操作不能撤销。",
                "Its three forms will be deleted. Growth level, activity history, and API keys stay. This can’t be undone."
            )
            alert.addButton(withTitle: voice("删除角色", "Delete familiar"))
            alert.addButton(withTitle: voice("取消", "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            do {
                if characterID == "prototype" {
                    d.removeObject(forKey: "customPetSpec")
                    js("famUnregisterPrototypePet()")
                } else {
                    try customPetStore.delete(characterID: characterID)
                    js("famUnregisterCustomPet(\(jsonStr(characterID)))")
                }
                if d.string(forKey: "character") == characterID {
                    d.set("lulu", forKey: "character")
                    js("famSetCharacter('lulu')")
                }
                pushSettingsState()
            } catch {
                settingsCall("petDeleteFailed", ["message": error.localizedDescription])
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
        case "language":
            let lang = body["language"] as? String == "en" ? "en" : "zh"
            d.set(lang, forKey: "voiceLanguage")
            js("famSetLanguage('\(lang)')")
            settingsWin?.title = voice("Mimo 米墨", "Mimo")
            buildMainMenu()
            rebuildStatusItem()
            pushSettingsState()
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
                gitWatcher.resetAndScan()
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
                a.messageText = voice("删除全部历史记录？", "Delete all history?")
                a.informativeText = voice("所有活动记录都会消失；XP 和等级会保留。此操作无法撤销。", "Every day of activity, gone. XP and level stay. No undo.")
                a.addButton(withTitle: voice("全部删除", "Delete Everything"))
                a.addButton(withTitle: voice("取消", "Cancel"))
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
