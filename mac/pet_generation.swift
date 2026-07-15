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
    typealias Progress = (_ route: String, _ phase: String, _ detail: String?) -> Void
    typealias Completion = (_ route: String, _ result: Result<[String], Error>) -> Void

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

    func generateBoth(requestID: String, sourceDataURI: String, styleDataURI: String?,
                      personality: String, likeness: Double,
                      progress: @escaping Progress, completion: @escaping Completion) {
        lock.lock(); cancelled.remove(requestID); lock.unlock()
        guard let pixelKey = MimoSecret.pixelLab.read() else {
            finish(completion, route: "B", result: .failure(PetGenerationError.missingKey("PixelLab")))
            finish(completion, route: "C", result: .failure(PetGenerationError.missingKey("PixelLab")))
            return
        }

        emit(progress, route: "B", phase: "pixel", detail: nil)
        generatePixelLab(referenceImages: [(sourceDataURI, 256, 256,
                                            "Preserve the subject's recognizable silhouette, colors, and distinguishing features")],
                         styleDataURI: styleDataURI, personality: personality,
                         likeness: likeness, apiKey: pixelKey, requestID: requestID) { [weak self] result in
            guard let self, !self.isCancelled(requestID) else { return }
            self.finish(completion, route: "B", result: result)
        }

        guard let openAIKey = MimoSecret.openAI.read() else {
            finish(completion, route: "C", result: .failure(PetGenerationError.missingKey("OpenAI")))
            return
        }
        emit(progress, route: "C", phase: "concept", detail: nil)
        generateConcept(sourceDataURI: sourceDataURI, personality: personality,
                        likeness: likeness, apiKey: openAIKey, requestID: requestID) { [weak self] concept in
            guard let self, !self.isCancelled(requestID) else { return }
            switch concept {
            case .failure(let error):
                self.finish(completion, route: "C", result: .failure(error))
            case .success(let conceptDataURI):
                self.emit(progress, route: "C", phase: "pixel", detail: nil)
                self.generatePixelLab(referenceImages: [
                    (conceptDataURI, 1024, 1024, "Use this as the primary character concept and silhouette"),
                    (sourceDataURI, 256, 256, "Preserve the original subject's recognizable identity and colors"),
                ], styleDataURI: styleDataURI, personality: personality,
                   likeness: max(0.25, likeness - 0.12), apiKey: pixelKey,
                   requestID: requestID) { [weak self] result in
                    guard let self, !self.isCancelled(requestID) else { return }
                    self.finish(completion, route: "C", result: result)
                }
            }
        }
    }

    private func generateConcept(sourceDataURI: String, personality: String, likeness: Double,
                                 apiKey: String, requestID: String,
                                 completion: @escaping (Result<String, Error>) -> Void) {
        guard let imageData = Self.dataFromDataURI(sourceDataURI),
              let url = URL(string: "https://api.openai.com/v1/images/edits") else {
            completion(.failure(PetGenerationError.invalidImage)); return
        }
        let boundary = "mimo-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendUTF8("\(value)\r\n")
        }
        field("model", "gpt-image-2")
        field("size", "1024x1024")
        field("quality", "low")
        field("output_format", "png")
        field("n", "1")
        let likenessCopy = likeness >= 0.66 ? "Stay very faithful to the subject." :
            likeness >= 0.4 ? "Balance likeness with a charming reinterpretation." :
            "Freely reinterpret the subject while keeping one or two unmistakable traits."
        field("prompt", """
        Reimagine the main subject as one tiny Mimo desktop familiar. \(likenessCopy)
        Personality: \(personality). Make a compact, warm, playful full-body character with a bold readable silhouette,
        expressive face, and one signature feature derived from the reference. Front-facing, centered, isolated on a plain
        neutral background. No text, scenery, border, extra characters, UI, or cast shadow. This is clean concept art that
        will be converted to strict pixel art in a second step.
        """)
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"image[]\"; filename=\"reference.png\"\r\n")
        body.appendUTF8("Content-Type: image/png\r\n\r\n")
        body.append(imageData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: url, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        performJSON(request, provider: "OpenAI", requestID: requestID) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let json):
                guard let images = Self.imageStrings(in: json), let first = images.first else {
                    completion(.failure(PetGenerationError.invalidResponse("OpenAI"))); return
                }
                self.resolveImage(first, requestID: requestID) { resolved in
                    completion(resolved.map { Self.dataURI($0) })
                }
            }
        }
    }

    private func generatePixelLab(referenceImages: [(String, Int, Int, String)], styleDataURI: String?,
                                  personality: String, likeness: Double, apiKey: String,
                                  requestID: String, completion: @escaping (Result<[String], Error>) -> Void) {
        guard let url = URL(string: "https://api.pixellab.ai/v2/generate-image-v2") else {
            completion(.failure(PetGenerationError.invalidResponse("PixelLab"))); return
        }
        let likenessCopy = likeness >= 0.66 ? "Closely preserve the reference subject." :
            likeness >= 0.4 ? "Preserve the reference identity while simplifying it." :
            "Use the reference as inspiration and prioritize a delightful character."
        var payload: [String: Any] = [
            "description": """
            One single Mimo desktop familiar, front-facing full body, true handcrafted pixel art. \(likenessCopy)
            Personality: \(personality). Compact cute proportions, bold distinctive silhouette, 6–8 coherent colors,
            readable face, tiny feet, selective one-pixel outline, subtle pixel shading. Centered with generous transparent
            padding. No text, scenery, floor, frame, UI, props, duplicate character, or non-pixel brushwork.
            """,
            "image_size": ["width": 96, "height": 96],
            "no_background": true,
            "reference_images": referenceImages.map { item in
                ["image": ["type": "base64", "base64": item.0, "format": "png"],
                 "size": ["width": item.1, "height": item.2],
                 "usage_description": item.3]
            },
        ]
        if let styleDataURI, !styleDataURI.isEmpty {
            payload["style_image"] = [
                "image": ["type": "base64", "base64": styleDataURI, "format": "png"],
                "size": ["width": 128, "height": 64],
                "usage_description": "Match the warm low-resolution sprite language, pixel scale, outline, and shading of Nat and Clawd",
            ]
            payload["style_options"] = ["color_palette": false, "outline": true, "detail": true, "shading": true]
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(.failure(PetGenerationError.invalidImage)); return
        }
        var request = URLRequest(url: url, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        performJSON(request, provider: "PixelLab", requestID: requestID) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let json):
                guard let jobID = json["background_job_id"] as? String else {
                    completion(.failure(PetGenerationError.invalidResponse("PixelLab"))); return
                }
                self.pollPixelLab(jobID: jobID, apiKey: apiKey, attempt: 0,
                                  requestID: requestID, completion: completion)
            }
        }
    }

    private func pollPixelLab(jobID: String, apiKey: String, attempt: Int, requestID: String,
                              completion: @escaping (Result<[String], Error>) -> Void) {
        guard !isCancelled(requestID) else { return }
        guard attempt < 45 else { completion(.failure(PetGenerationError.timedOut)); return }
        guard let url = URL(string: "https://api.pixellab.ai/v2/background-jobs/\(jobID)") else {
            completion(.failure(PetGenerationError.invalidResponse("PixelLab"))); return
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        performJSON(request, provider: "PixelLab", requestID: requestID) { result in
            guard !self.isCancelled(requestID) else { return }
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let json):
                let status = (json["status"] as? String ?? "").lowercased()
                if status == "failed" {
                    completion(.failure(PetGenerationError.provider(Self.providerMessage(json) ?? "PixelLab generation failed")))
                } else if status == "completed" {
                    let raw = json["last_response"] ?? json
                    guard let imageValues = Self.imageStrings(in: raw), !imageValues.isEmpty else {
                        completion(.failure(PetGenerationError.invalidResponse("PixelLab"))); return
                    }
                    self.resolveImages(Array(imageValues.prefix(4)), requestID: requestID, completion: completion)
                } else {
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
                        self.pollPixelLab(jobID: jobID, apiKey: apiKey, attempt: attempt + 1,
                                          requestID: requestID, completion: completion)
                    }
                }
            }
        }
    }

    private func resolveImages(_ values: [String], requestID: String,
                               completion: @escaping (Result<[String], Error>) -> Void) {
        let group = DispatchGroup()
        let resultLock = NSLock()
        var resolved: [Int: String] = [:]
        var firstError: Error?
        for (index, value) in values.enumerated() {
            group.enter()
            resolveImage(value, requestID: requestID) { result in
                resultLock.lock()
                switch result {
                case .success(let data): resolved[index] = Self.dataURI(data)
                case .failure(let error): if firstError == nil { firstError = error }
                }
                resultLock.unlock(); group.leave()
            }
        }
        group.notify(queue: .global(qos: .userInitiated)) {
            let ordered = resolved.keys.sorted().compactMap { resolved[$0] }
            if !ordered.isEmpty { completion(.success(ordered)) }
            else { completion(.failure(firstError ?? PetGenerationError.invalidResponse("PixelLab"))) }
        }
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
                let retryLimit = provider == "PixelLab" && http.statusCode == 429 ? 6 : 2
                if attempt < retryLimit && retryable {
                    let headerDelay = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 2
                    let baseDelay = provider == "PixelLab" && http.statusCode == 429 ? max(4, headerDelay) : headerDelay
                    let delay = min(12, max(1, baseDelay * pow(2, Double(attempt))))
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

    private func emit(_ callback: @escaping Progress, route: String, phase: String, detail: String?) {
        callbackQueue.async { callback(route, phase, detail) }
    }

    private func finish(_ callback: @escaping Completion, route: String, result: Result<[String], Error>) {
        callbackQueue.async { callback(route, result) }
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

    // PixelLab intentionally types background-job last_response as opaque JSON.
    // Walk it defensively, preferring embedded base64 before storage URLs.
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
