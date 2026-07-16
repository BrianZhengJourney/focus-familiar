// Mimo — image-to-familiar generation service.
// Provider credentials are transferred from bundled Settings into the macOS
// Keychain and are never returned to JavaScript after saving.

import Cocoa
import Foundation
import Security

enum MimoSecret: String {
    case pixelLab = "pixellab"
    case openAI = "openai"

    private var account: String { "mimo.\(rawValue).api-key" }
    private var environmentNames: [String] {
        switch self {
        case .pixelLab: return ["PIXELLAB_API_TOKEN", "PIXELLAB_API_KEY"]
        case .openAI: return ["OPENAI_API_KEY"]
        }
    }

    func read() -> String? {
        for key in environmentNames {
            if let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty { return value }
        }
        // Local builds are ad-hoc signed, so use the standard macOS login
        // Keychain. The data-protection Keychain requires a provisioned app ID.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.brianzheng.mimo",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else { return nil }
        return value
    }

    @discardableResult
    func write(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.brianzheng.mimo",
            kSecAttrAccount as String: account,
        ]
        if trimmed.isEmpty {
            let status = SecItemDelete(lookup as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let attrs: [String: Any] = [
            kSecValueData as String: Data(trimmed.utf8),
        ]
        let updated = SecItemUpdate(lookup as CFDictionary, attrs as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        var add = lookup
        attrs.forEach { add[$0.key] = $0.value }
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    var isConfigured: Bool { read() != nil }
}

enum PetGenerationError: LocalizedError {
    case missingKey(String)
    case invalidImage
    case invalidResponse(String)
    case provider(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .missingKey(let provider): return "Missing \(provider) API key"
        case .invalidImage: return "The reference image could not be read"
        case .invalidResponse(let provider): return "\(provider) returned an unreadable response"
        case .provider(let message): return message
        case .timedOut: return "Generation timed out"
        }
    }
}

final class PetGenerationCoordinator {
    typealias SheetProgress = (_ phase: String, _ detail: String?) -> Void
    typealias SheetCompletion = (Result<Data, Error>) -> Void

    private let session: URLSession
    private let callbackQueue = DispatchQueue.main
    private let lock = NSLock()
    private var cancelled = Set<String>()
    private var activeTasks: [String: [UUID: URLSessionTask]] = [:]

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 240
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    func cancel(_ requestID: String) {
        lock.lock()
        cancelled.insert(requestID)
        let tasks = Array((activeTasks.removeValue(forKey: requestID) ?? [:]).values)
        lock.unlock()
        tasks.forEach { $0.cancel() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 300) { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.cancelled.remove(requestID); self.lock.unlock()
        }
    }

    func generateCharacterSheet(requestID: String, sourceDataURI: String,
                                personalityVisual: String, likeness: Double,
                                progress: @escaping SheetProgress,
                                completion: @escaping SheetCompletion) {
        lock.lock(); cancelled.remove(requestID); lock.unlock()
        guard let openAIKey = MimoSecret.openAI.read() else {
            finishSheet(completion, result: .failure(PetGenerationError.missingKey("OpenAI")))
            return
        }
        guard let imageData = Self.dataFromDataURI(sourceDataURI),
              Self.isSupportedImageData(imageData), imageData.count <= 12 * 1024 * 1024 else {
            finishSheet(completion, result: .failure(PetGenerationError.invalidImage)); return
        }
        emitSheet(progress, phase: "generating", detail: "medium · 1536×1024")
        let request = Self.characterSheetRequest(imageData: imageData,
                                                 personalityVisual: personalityVisual,
                                                 likeness: likeness,
                                                 apiKey: openAIKey)
        performJSON(request, provider: "OpenAI", requestID: requestID) { result in
            guard !self.isCancelled(requestID) else { return }
            switch result {
            case .failure(let error): self.finishSheet(completion, result: .failure(error))
            case .success(let json):
                guard let images = Self.imageStrings(in: json), let first = images.first else {
                    self.finishSheet(completion, result: .failure(PetGenerationError.invalidResponse("OpenAI"))); return
                }
                self.resolveImage(first, requestID: requestID) { resolved in
                    guard !self.isCancelled(requestID) else { return }
                    let checked = resolved.flatMap { data -> Result<Data, Error> in
                        guard let size = Self.pngPixelSize(data), size.0 == 1536, size.1 == 1024 else {
                            return .failure(PetGenerationError.invalidResponse("OpenAI character sheet"))
                        }
                        return .success(data)
                    }
                    self.finishSheet(completion, result: checked)
                }
            }
        }
    }

    static func characterSheetRequest(imageData: Data, personalityVisual: String,
                                      likeness: Double, apiKey: String,
                                      boundary: String = "mimo-\(UUID().uuidString)") -> URLRequest {
        let url = URL(string: "https://api.openai.com/v1/images/edits")!
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendUTF8("\(value)\r\n")
        }
        field("model", "gpt-image-2")
        field("size", "1536x1024")
        field("quality", "medium")
        field("output_format", "png")
        field("background", "opaque")
        field("n", "1")
        field("prompt", characterSheetPrompt(personalityVisual: personalityVisual, likeness: likeness))
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"image[]\"; filename=\"reference.png\"\r\n")
        body.appendUTF8("Content-Type: image/png\r\n\r\n")
        body.append(imageData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: url, timeoutInterval: 240)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        request.httpBody = body
        return request
    }

    static func characterSheetPrompt(personalityVisual: String, likeness: Double) -> String {
        let likenessCopy = likeness >= 0.66
            ? "Preserve the subject's identity, facial or marking structure, primary colors, outfit colors, and signature feature very closely."
            : likeness >= 0.4
                ? "Preserve the subject's face or markings, primary colors, and one signature feature while simplifying it into a familiar."
                : "Freely reinterpret the subject, but retain two unmistakable visual traits and its primary color family."
        return """
        PRODUCTION ASSET — MIMO DESKTOP FAMILIAR CHARACTER SHEET

        REFERENCE
        Image 1 is the identity and color reference for the main subject, not a pose or layout template.
        Likeness: \(likenessCopy)
        Temperament: \(personalityVisual)

        PURPOSE AND STYLE
        Create one original tiny desktop familiar that remains charming and readable at roughly 96–160 px tall on macOS.
        Use premium handcrafted pixel-inspired sprite art: cute chibi proportions, large expressive head, tiny full body,
        crisp stepped edges, restrained dark-cocoa outline, a coherent 10–14 color palette, warm selective shading, and a
        strong readable silhouette. Avoid photorealism, 3D rendering, painterly brushwork, smooth vector art, or emoji style.

        LAYOUT
        One 1536×1024 landscape sheet with exactly three isolated full-body versions arranged LEFT, CENTER, RIGHT—one in
        each equal third. Front-facing neutral standing pose, eyes open, feet fully visible, same horizontal center and same
        ground baseline in every panel. Keep generous clear margin. No dividers and no labels.

        EVOLUTION
        LEFT — SEED: youngest and smallest form; round, simple silhouette; fewest details.
        CENTER — BLOOM: unmistakably the same individual; slightly taller and more confident; signature feature grows.
        RIGHT — RADIANT: unmistakably the same individual; clearest evolved silhouette with a crest, ear, leaf, tail, wing,
        or luminous body-marking flourish; powerful but still tiny and cute.
        Lock the same face, species, hairstyle or markings, primary palette, outfit colors, and signature trait across all
        three. Evolve silhouette and internal markings—never create three different people, species, poses, or outfits.

        EXTRACTION MATTE
        Use one flat opaque warm matte background, exact color #F1ECE2, across the whole canvas. No gradient, texture,
        floor, cast shadow, halo, external glow, particles, props, scenery, frame, UI, text, logo, watermark, extra
        characters, or cropped limbs. Convey Radiant energy only through silhouette and body markings; Mimo adds effects.
        """
    }

    private func resolveImage(_ value: String, requestID: String,
                              completion: @escaping (Result<Data, Error>) -> Void) {
        let maximumImageBytes = 12 * 1024 * 1024
        if let data = Self.dataFromDataURI(value) {
            guard data.count <= maximumImageBytes, Self.isSupportedImageData(data) else {
                completion(.failure(PetGenerationError.invalidImage)); return
            }
            completion(.success(data)); return
        }
        guard let url = URL(string: value), url.scheme?.lowercased() == "https",
              url.host != nil, url.user == nil, url.password == nil else {
            completion(.failure(PetGenerationError.invalidImage)); return
        }
        var request = URLRequest(url: url, timeoutInterval: 45)
        request.setValue("image/png,image/jpeg,image/webp", forHTTPHeaderField: "Accept")
        request.setValue("bytes=0-\(maximumImageBytes)", forHTTPHeaderField: "Range")
        let token = UUID()
        let task = session.dataTask(with: request) { data, response, error in
            self.untrack(token, requestID: requestID)
            if let error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
                  let data, !data.isEmpty, data.count <= maximumImageBytes,
                  Self.isSupportedImageData(data),
                  http.mimeType.map({ $0.hasPrefix("image/") || $0 == "application/octet-stream" }) ?? true else {
                completion(.failure(PetGenerationError.invalidResponse("image host"))); return
            }
            completion(.success(data))
        }
        track(task, token: token, requestID: requestID); task.resume()
    }

    private func performJSON(_ request: URLRequest, provider: String, requestID: String, attempt: Int = 0,
                             completion: @escaping (Result<[String: Any], Error>) -> Void) {
        let token = UUID()
        let task = session.dataTask(with: request) { data, response, error in
            self.untrack(token, requestID: requestID)
            guard !self.isCancelled(requestID) else { return }
            if let error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(PetGenerationError.invalidResponse(provider))); return
            }
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            guard 200..<300 ~= http.statusCode else {
                let retryable = http.statusCode == 429
                    || (request.httpMethod != "POST" && 500...599 ~= http.statusCode)
                let retryLimit = 2
                if attempt < retryLimit && retryable {
                    let headerDelay = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 2
                    let delay = min(12, max(1, headerDelay * pow(2, Double(attempt))))
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
                        self.performJSON(request, provider: provider, requestID: requestID,
                                         attempt: attempt + 1, completion: completion)
                    }
                    return
                }
                let message = Self.providerMessage(object ?? [:]) ?? "\(provider) request failed (\(http.statusCode))"
                completion(.failure(PetGenerationError.provider(message))); return
            }
            guard let object else {
                completion(.failure(PetGenerationError.invalidResponse(provider))); return
            }
            completion(.success(object))
        }
        track(task, token: token, requestID: requestID); task.resume()
    }

    private func emitSheet(_ callback: @escaping SheetProgress, phase: String, detail: String?) {
        callbackQueue.async { callback(phase, detail) }
    }

    private func finishSheet(_ callback: @escaping SheetCompletion, result: Result<Data, Error>) {
        callbackQueue.async { callback(result) }
    }

    private func isCancelled(_ requestID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled.contains(requestID)
    }

    private func track(_ task: URLSessionTask, token: UUID, requestID: String) {
        lock.lock()
        if cancelled.contains(requestID) { lock.unlock(); task.cancel(); return }
        activeTasks[requestID, default: [:]][token] = task
        lock.unlock()
    }

    private func untrack(_ token: UUID, requestID: String) {
        lock.lock()
        activeTasks[requestID]?.removeValue(forKey: token)
        if activeTasks[requestID]?.isEmpty == true { activeTasks.removeValue(forKey: requestID) }
        lock.unlock()
    }

    static func dataFromDataURI(_ value: String) -> Data? {
        let raw: String
        if let comma = value.firstIndex(of: ",") {
            raw = String(value[value.index(after: comma)...])
        } else {
            raw = value
        }
        guard !raw.isEmpty else { return nil }
        return Data(base64Encoded: raw, options: [.ignoreUnknownCharacters])
    }

    static func dataURI(_ data: Data) -> String { "data:image/png;base64," + data.base64EncodedString() }

    static func pngPixelSize(_ data: Data) -> (Int, Int)? {
        guard isSupportedImageData(data),
              let rep = NSBitmapImageRep(data: data),
              rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return nil }
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    static func isSupportedImageData(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        let png: [UInt8] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
        if bytes.starts(with: png) { return true }
        if bytes.count >= 3, bytes[0...2].elementsEqual([0xff, 0xd8, 0xff]) { return true }
        if bytes.count >= 6,
           String(bytes: bytes[0..<6], encoding: .ascii).map({ $0 == "GIF87a" || $0 == "GIF89a" }) == true { return true }
        if bytes.count >= 12,
           String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
           String(bytes: bytes[8..<12], encoding: .ascii) == "WEBP" { return true }
        return false
    }

    // Provider responses vary between embedded base64 and storage URLs. Walk
    // defensively, preferring embedded image data so private assets stay local.
    static func imageStrings(in value: Any) -> [String]? {
        var embedded: [String] = [], urls: [String] = []
        func visit(_ node: Any, key: String? = nil) {
            if let dictionary = node as? [String: Any] {
                let preferred = ["images", "image", "base64", "b64_json", "output", "outputs", "storage_urls"]
                for name in preferred where dictionary[name] != nil { visit(dictionary[name]!, key: name) }
                for (name, child) in dictionary where !preferred.contains(name) { visit(child, key: name) }
            } else if let array = node as? [Any] {
                array.forEach { visit($0, key: key) }
            } else if let string = node as? String {
                let lower = string.lowercased()
                if lower.hasPrefix("data:image/") { embedded.append(string) }
                else if (key == "base64" || key == "b64_json"), string.count > 200 {
                    embedded.append("data:image/png;base64," + string)
                } else if (lower.hasPrefix("https://") || lower.hasPrefix("http://")),
                          lower.contains(".png") || lower.contains("image") { urls.append(string) }
            }
        }
        visit(value)
        let unique = (embedded.isEmpty ? urls : embedded).reduce(into: [String]()) { out, item in
            if !out.contains(item) { out.append(item) }
        }
        return unique.isEmpty ? nil : unique
    }

    static func providerMessage(_ value: Any) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        if let dictionary = value as? [String: Any] {
            for key in ["message", "detail", "error", "failure_reason"] {
                if let message = providerMessage(dictionary[key] as Any), !message.isEmpty { return message }
            }
        }
        if let array = value as? [Any] {
            for item in array { if let message = providerMessage(item) { return message } }
        }
        return nil
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) { append(Data(string.utf8)) }
}
