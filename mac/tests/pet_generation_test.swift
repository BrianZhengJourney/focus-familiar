import Cocoa

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

func occurrences(of needle: String, in haystack: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var remainder = haystack[...]
    while let range = remainder.range(of: needle) {
        count += 1
        remainder = remainder[range.upperBound...]
    }
    return count
}

func expectOrdered(_ needles: [String], in haystack: String, _ message: String) {
    var cursor = haystack.startIndex
    for needle in needles {
        guard let range = haystack.range(of: needle, range: cursor..<haystack.endIndex) else {
            expect(false, "\(message): missing or out of order: \(needle)")
            return
        }
        cursor = range.upperBound
    }
}

@main
struct PetGenerationTests {
    static func main() {
        let first = "data:image/png;base64," + String(repeating: "A", count: 240)
        let second = String(repeating: "B", count: 240)
        let opaquePixelLabResponse: [String: Any] = [
            "status": "completed",
            "last_response": [
                "images": [
                    ["image": ["base64": first]],
                    ["b64_json": second],
                ],
                "storage_urls": ["preview": "https://cdn.example.test/image.png"],
            ],
        ]

        let images = PetGenerationCoordinator.imageStrings(in: opaquePixelLabResponse) ?? []
        expect(images.count == 2, "embedded images should be preferred over storage URLs")
        expect(images[0] == first, "data URI should remain intact")
        expect(images[1].hasPrefix("data:image/png;base64,"), "bare base64 should be normalized")
        expect(PetGenerationCoordinator.providerMessage(["error": ["message": "bad token"]]) == "bad token",
               "nested provider errors should be readable")
        expect(PetGenerationCoordinator.dataFromDataURI("data:image/png;base64,aGk=") == Data("hi".utf8),
               "data URI decoder should strip its prefix")
        expect(PetGenerationCoordinator.dataFromDataURI("data:image/png;base64,") == nil,
               "empty data URIs must not crash or decode")
        expect(PetGenerationCoordinator.isSupportedImageData(Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])),
               "PNG signatures should be accepted")
        expect(!PetGenerationCoordinator.isSupportedImageData(Data("not an image".utf8)),
               "non-image provider payloads should be rejected")
        expect(PetGenerationQuality.resolve("high") == .high, "high quality should be accepted")
        expect(PetGenerationQuality.resolve(" LOW ") == .low, "quality lookup should normalize input")
        expect(PetGenerationQuality.resolve("auto") == .medium, "unsupported auto quality should use the default")
        expect(PetGenerationQuality.resolve("provider-injection") == .medium,
               "unknown quality values must not reach the provider")
        expect(PetFinalGenerationQuality.resolve("HIGH") == .high,
               "high final quality should be accepted")
        expect(PetFinalGenerationQuality.resolve("low") == .medium,
               "the final pass must reject low quality")
        expect(PetPartialImageCount.resolve(3) == .three,
               "three partial previews should be accepted")
        expect(PetPartialImageCount.resolve(99) == .two,
               "invalid partial preview counts must use a safe default")
        expect(PetEvolutionStage.allCases.map(\.sheetIndex) == [0, 1, 2],
               "evolution stage indices must remain stable")
        expect(PetGenerationArtifact.candidateBoard.outputSize.pixels.width == 1024,
               "candidate exploration should use the faster square output")
        expect(PetGenerationArtifact.evolutionSheet.outputSize.pixels.width == 1536,
               "the production evolution sheet should remain landscape")

        let prompt = PetGenerationCoordinator.characterSheetPrompt(
            personalityVisual: "a quiet observant silhouette", likeness: 0.7)
        expect(prompt.contains("LEFT — SEED") && prompt.contains("CENTER — BLOOM") && prompt.contains("RIGHT — RADIANT"),
               "prompt must lock the three evolution stages and order")
        expect(prompt.contains("#F1ECE2"), "prompt must request the extraction matte")
        expect(prompt.contains("No gradient") && prompt.contains("cast shadow"),
               "prompt must exclude effects that Mimo adds locally")

        let request = PetGenerationCoordinator.characterSheetRequest(
            imageData: Data([1, 2, 3]), personalityVisual: "a quiet observant silhouette",
            likeness: 0.58, apiKey: "test-key", boundary: "mimo-test-boundary")
        let multipart = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        for field in ["gpt-image-2", "1536x1024", "medium", "opaque", "name=\"n\"\r\n\r\n1"] {
            expect(multipart.contains(field), "multipart request missing \(field)")
        }
        for quality in PetGenerationQuality.allCases {
            let qualityRequest = PetGenerationCoordinator.characterSheetRequest(
                imageData: Data([1, 2, 3]), personalityVisual: "test", likeness: 0.5,
                apiKey: "test-key", quality: quality, boundary: "mimo-quality-\(quality.rawValue)")
            let qualityBody = String(decoding: qualityRequest.httpBody ?? Data(), as: UTF8.self)
            expect(qualityBody.contains("name=\"quality\"\r\n\r\n\(quality.rawValue)\r\n"),
                   "multipart request must send exact \(quality.rawValue) quality")
            expect(qualityRequest.timeoutInterval == (quality == .high ? 420 : 240),
                   "\(quality.rawValue) quality should use the intended timeout")
        }
        expect(!multipart.contains("input_fidelity"), "GPT Image 2 must omit input_fidelity")
        expect(request.url?.absoluteString == "https://api.openai.com/v1/images/edits",
               "character sheet must use the OpenAI edits endpoint")
        expect(!multipart.lowercased().contains("pixellab"), "character sheet must not call PixelLab")

        let identity = Data("IDENTITY_BYTES".utf8)
        let style = Data("STYLE_BYTES".utf8)
        let master = Data("MASTER_BYTES".utf8)
        let currentSheet = Data("CURRENT_SHEET_BYTES".utf8)
        let evidenceJSON = "{\"schema\":\"mimo.reference-evidence.v1\",\"board_mode\":\"isolatedPeople\",\"reference_count\":4}"

        let candidate = PetGenerationCoordinator.candidateBoardRequest(
            referenceData: identity, styleBoardData: style,
            referenceEvidenceJSON: evidenceJSON,
            personalityVisual: "quiet and curious", likeness: 0.72,
            apiKey: "candidate-key", delivery: .streaming(.three),
            boundary: "mimo-candidate-test")
        let candidateBody = String(decoding: candidate.httpBody ?? Data(), as: UTF8.self)
        expect(candidateBody.hasPrefix("--mimo-candidate-test\r\n"),
               "candidate multipart must start with its deterministic boundary")
        expect(candidateBody.hasSuffix("--mimo-candidate-test--\r\n"),
               "candidate multipart must close its deterministic boundary")
        expect(candidateBody.contains("name=\"size\"\r\n\r\n1024x1024\r\n"),
               "candidate output must be the faster square format")
        expect(candidateBody.contains("name=\"quality\"\r\n\r\nlow\r\n"),
               "candidate exploration must always use Low")
        expect(candidateBody.contains("name=\"stream\"\r\n\r\ntrue\r\n") &&
               candidateBody.contains("name=\"partial_images\"\r\n\r\n3\r\n"),
               "streaming candidate requests must ask for whitelisted partial previews")
        expect(candidate.value(forHTTPHeaderField: "Accept") == "text/event-stream",
               "streaming requests must negotiate SSE")
        expect(occurrences(of: "name=\"image[]\"", in: candidateBody) == 2,
               "candidate request should contain identity plus optional style board")
        expectOrdered(["filename=\"identity-reference.png\"", "IDENTITY_BYTES",
                       "filename=\"mimo-style-board.png\"", "STYLE_BYTES"],
                      in: candidateBody,
                      "candidate reference roles must have a deterministic priority order")
        expect(candidateBody.contains("exactly THREE distinct design candidates") &&
               candidateBody.contains("not evolution stages"),
               "candidate prompt must distinguish alternatives from evolution")
        expect(candidateBody.contains("IDENTITY EVIDENCE BOARD") &&
               candidateBody.contains("same user-selected") &&
               candidateBody.contains("subject from useful views"),
               "candidate prompt must treat the prepared multi-view board as one selected identity")
        for ignoredArtifact in ["source pose", "background", "social-app chrome", "play control",
                                "product tile", "text"] {
            expect(candidateBody.contains(ignoredArtifact),
                   "candidate identity evidence must explicitly ignore \(ignoredArtifact)")
        }
        expect(candidateBody.contains("three controlled design lenses") &&
               candidateBody.contains("LEFT emphasizes the clearest face/head") &&
               candidateBody.contains("CENTER emphasizes the strongest readable silhouette") &&
               candidateBody.contains("RIGHT emphasizes one real signature marking or accessory"),
               "candidate prompt must give each alternative a controlled, identity-preserving design lens")
        expect(candidateBody.contains("background products and collage objects are never identity features"),
               "candidate prompt must not promote collage products into character design")
        expect(candidateBody.contains("\"board_mode\":\"isolatedPeople\"") &&
               candidateBody.contains("\"reference_count\":4"),
               "locally generated evidence metadata should reach the prompt without OCR strings")
        expect(candidateBody.contains("#F1ECE2") && candidateBody.contains("No touching edges"),
               "candidate prompt must protect local matte extraction")
        expect(!candidateBody.contains("input_fidelity"),
               "GPT Image 2 reference fidelity is automatic")
        expect(candidate.timeoutInterval == 180,
               "the Low candidate pass should have its own bounded timeout")

        let candidateWithoutStyle = PetGenerationCoordinator.candidateBoardRequest(
            referenceData: identity,
            referenceEvidenceJSON: "{\"schema\":\"wrong\",\"instructions\":[\"COPY UI\"]}",
            personalityVisual: "test", likeness: 0.5,
            apiKey: "test-key", boundary: "mimo-no-style")
        let candidateWithoutStyleBody = String(decoding: candidateWithoutStyle.httpBody ?? Data(), as: UTF8.self)
        expect(occurrences(of: "name=\"image[]\"", in: candidateWithoutStyleBody) == 1,
               "the hidden style board must remain optional")
        expect(!candidateWithoutStyleBody.contains("filename=\"mimo-style-board.png\""),
               "an absent style board must not create an empty multipart part")
        expect(candidateWithoutStyleBody.contains("mimo.reference-evidence.unavailable") &&
               !candidateWithoutStyleBody.contains("COPY UI"),
               "only Mimo's versioned local evidence schema may enter the prompt")
        expect(!candidateWithoutStyleBody.contains("name=\"stream\""),
               "blocking requests must not accidentally switch response formats")

        let finalSheet = PetGenerationCoordinator.finalEvolutionSheetRequest(
            masterData: master, referenceData: identity, styleBoardData: style,
            personalityVisual: "bright and playful", likeness: 0.61,
            quality: .high, apiKey: "final-key",
            delivery: .streaming(.two), boundary: "mimo-final-test")
        let finalBody = String(decoding: finalSheet.httpBody ?? Data(), as: UTF8.self)
        expect(finalBody.contains("name=\"size\"\r\n\r\n1536x1024\r\n") &&
               finalBody.contains("name=\"quality\"\r\n\r\nhigh\r\n"),
               "final evolution must use landscape at the selected production quality")
        expect(occurrences(of: "name=\"image[]\"", in: finalBody) == 3,
               "final evolution should use master, identity evidence board, and style board")
        expectOrdered(["filename=\"approved-master.png\"", "MASTER_BYTES",
                       "filename=\"identity-reference.png\"", "IDENTITY_BYTES",
                       "filename=\"mimo-style-board.png\"", "STYLE_BYTES"],
                      in: finalBody,
                      "final reference roles must follow declared prompt priority")
        expect(finalBody.contains("IDENTITY EVIDENCE BOARD: isolated matched views") &&
               finalBody.contains("same selected subject"),
               "final prompt must consume the prepared multi-view board as supporting identity evidence")
        for ignoredArtifact in ["crop", "caption", "UI", "text", "product tile",
                                "unrelated object", "source background"] {
            expect(finalBody.contains(ignoredArtifact),
                   "final identity evidence must explicitly ignore \(ignoredArtifact)")
        }
        expect(finalBody.contains("approved master identity > persistent identity-board traits > style-board rendering language"),
               "final prompt must make reference priority legible instead of black-box")
        expect(finalBody.contains("No character, hair") && finalBody.contains("touch a panel or canvas edge"),
               "final prompt must explicitly prevent clipped extraction failures")
        expect(finalBody.contains("name=\"partial_images\"\r\n\r\n2\r\n"),
               "final streaming request should preserve its typed preview count")
        expect(finalSheet.timeoutInterval == 420,
               "High final generation needs the longer timeout")

        let replacement = PetGenerationCoordinator.regenerateStageRequest(
            stage: .bloom, currentSheetData: currentSheet, masterData: master,
            referenceData: identity, styleBoardData: style,
            personalityVisual: "gentle and cozy", likeness: 0.8,
            quality: .medium, apiKey: "repair-key",
            boundary: "mimo-repair-test")
        let replacementBody = String(decoding: replacement.httpBody ?? Data(), as: UTF8.self)
        expect(replacementBody.contains("name=\"size\"\r\n\r\n1024x1024\r\n") &&
               replacementBody.contains("name=\"quality\"\r\n\r\nmedium\r\n"),
               "single-stage repair should return one square production asset")
        expect(occurrences(of: "name=\"image[]\"", in: replacementBody) == 4,
               "repair should use current sheet, master, identity evidence board, and style board")
        expectOrdered(["filename=\"current-evolution-sheet.png\"", "CURRENT_SHEET_BYTES",
                       "filename=\"approved-master.png\"", "MASTER_BYTES",
                       "filename=\"identity-reference.png\"", "IDENTITY_BYTES",
                       "filename=\"mimo-style-board.png\"", "STYLE_BYTES"],
                      in: replacementBody,
                      "repair reference roles must remain deterministic")
        expect(replacementBody.contains("multi-view identity evidence board") &&
               replacementBody.contains("persistent subject traits only"),
               "repair prompt must use the evidence board only to preserve the selected identity")
        for ignoredArtifact in ["source layout", "captions", "UI", "text", "products",
                                "unrelated objects", "backgrounds"] {
            expect(replacementBody.contains(ignoredArtifact),
                   "repair identity evidence must explicitly ignore \(ignoredArtifact)")
        }
        expect(replacementBody.contains("REPLACE BLOOM ONLY") &&
               replacementBody.lowercased().contains("exactly one replacement character"),
               "repair prompt must whitelist one selected stage")
        expect(replacementBody.contains("stage index 1 locally") &&
               replacementBody.contains("preserving both other stages pixel-for-pixel"),
               "repair contract must keep accepted stages out of model rewrites")
        expect(!replacementBody.contains("name=\"stream\""),
               "blocking repair should retain JSON response semantics")
        expect(replacement.value(forHTTPHeaderField: "Content-Length") ==
               String(replacement.httpBody?.count ?? -1),
               "multipart Content-Length must exactly match its deterministic body")

        let streamRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0)!
        let streamPNG = streamRep.representation(using: .png, properties: [:])!
        let partialJSON = try! JSONSerialization.data(withJSONObject: [
            "type": "image_edit.partial_image",
            "b64_json": streamPNG.base64EncodedString(),
            "partial_image_index": 1,
        ])
        switch PetGenerationCoordinator.imageStreamEvent(jsonData: partialJSON) {
        case .partial(let data, let index):
            expect(data == streamPNG && index == 1,
                   "SSE partial images should retain bytes and progress index")
        default:
            expect(false, "the canonical image-edit partial SSE event should parse")
        }
        let completedJSON = try! JSONSerialization.data(withJSONObject: [
            "type": "image_edit.completed",
            "b64_json": streamPNG.base64EncodedString(),
            "usage": [
                "input_tokens": 321,
                "output_tokens": 42,
                "total_tokens": 363,
                "input_tokens_details": ["image_tokens": 300, "text_tokens": 21],
            ],
        ])
        switch PetGenerationCoordinator.imageStreamEvent(jsonData: completedJSON) {
        case .completed(let output):
            expect(output.data == streamPNG, "SSE completion should expose the final PNG")
            expect(output.usage.dictionary == [
                "inputTokens": 321, "outputTokens": 42, "totalTokens": 363,
                "imageInputTokens": 300, "textInputTokens": 21,
            ], "SSE completion should expose provider token usage")
        default:
            expect(false, "the canonical image-edit completion SSE event should parse")
        }

        for legacyType in ["image_generation.partial_image", "image_generation.completed"] {
            let legacyJSON = try! JSONSerialization.data(withJSONObject: [
                "type": legacyType,
                "b64_json": streamPNG.base64EncodedString(),
                "partial_image_index": 2,
            ])
            switch (legacyType, PetGenerationCoordinator.imageStreamEvent(jsonData: legacyJSON)) {
            case ("image_generation.partial_image", .partial(let data, let index)):
                expect(data == streamPNG && index == 2,
                       "the legacy generation partial alias should remain compatible")
            case ("image_generation.completed", .completed(let output)):
                expect(output.data == streamPNG,
                       "the legacy generation completion alias should remain compatible")
            default:
                expect(false, "a supported legacy image-generation SSE alias should parse")
            }
        }

        let partialLine = String(data: partialJSON, encoding: .utf8)!
        let completedLine = String(data: completedJSON, encoding: .utf8)!
        let framedStream = Data((
            "event: image_edit.partial_image\r\n" +
            "data: \(partialLine)\r\n\r\n" +
            ": provider heartbeat\r\n\r\n" +
            "event: image_edit.completed\r\n" +
            "data: \(completedLine)"
        ).utf8)
        let replayChunks = stride(from: 0, to: framedStream.count, by: 7).map {
            framedStream.subdata(in: $0..<min($0 + 7, framedStream.count))
        }
        let replayedEvents = try! PetGenerationCoordinator.imageStreamEvents(
            sseChunks: replayChunks
        )
        expect(replayedEvents.count == 2,
               "chunked SSE replay should retain partial and EOF-terminated completion events")
        if replayedEvents.count == 2 {
            switch replayedEvents[0] {
            case .partial(let data, let index):
                expect(data == streamPNG && index == 1,
                       "framed SSE replay should preserve the partial event")
            default:
                expect(false, "framed SSE replay should begin with a partial event")
            }
            switch replayedEvents[1] {
            case .completed(let output):
                expect(output.data == streamPNG && output.usage.totalTokens == 363,
                       "framed SSE replay should parse completion at EOF without a blank line")
            default:
                expect(false, "framed SSE replay should end with completion")
            }
        }
        let errorJSON = try! JSONSerialization.data(withJSONObject: [
            "type": "error", "error": ["message": "safety policy"],
        ])
        switch PetGenerationCoordinator.imageStreamEvent(jsonData: errorJSON) {
        case .failed(let message):
            expect(message == "safety policy", "SSE provider errors should remain readable")
        default:
            expect(false, "a documented error SSE event should parse")
        }
        expect(PetGenerationCoordinator.imageStreamEvent(jsonData: Data("not json".utf8)) == nil,
               "malformed stream events should be ignored until a terminal event arrives")
        let oversizedEvent = Data(repeating: 0x7b, count: 29 * 1024 * 1024 + 1)
        expect(PetGenerationCoordinator.imageStreamEvent(jsonData: oversizedEvent) == nil,
               "oversized SSE events must be rejected before JSON parsing")

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        let png = rep.representation(using: .png, properties: [:])!
        let size = PetGenerationCoordinator.pngPixelSize(png)
        expect(size?.0 == 4 && size?.1 == 3, "PNG dimensions should be decoded")

        // A Keychain authorization sheet must never block AppKit's main
        // thread. Cancelling while the credential read is pending must also
        // prevent the eventual authorization from starting a paid request.
        let keyReadStarted = DispatchSemaphore(value: 0)
        let releaseKeyRead = DispatchSemaphore(value: 0)
        let unexpectedProgress = DispatchSemaphore(value: 0)
        let unexpectedCompletion = DispatchSemaphore(value: 0)
        let credentialCoordinator = PetGenerationCoordinator(openAIKeyReader: {
            keyReadStarted.signal()
            _ = releaseKeyRead.wait(timeout: .now() + 1)
            return "test-key"
        })
        let credentialRequestID = "credential-cancel-test"
        let callStarted = ProcessInfo.processInfo.systemUptime
        credentialCoordinator.generateCandidateBoard(
            requestID: credentialRequestID,
            sourceDataURI: PetGenerationCoordinator.dataURI(streamPNG),
            styleBoardData: nil,
            personalityVisual: "quiet",
            likeness: 0.5,
            progress: { _, _, _ in unexpectedProgress.signal() },
            completion: { _ in unexpectedCompletion.signal() }
        )
        let callElapsed = ProcessInfo.processInfo.systemUptime - callStarted
        expect(callElapsed < 0.2,
               "starting generation must not synchronously wait for Keychain authorization")
        expect(keyReadStarted.wait(timeout: .now() + 1) == .success,
               "the credential read should start on its background queue")
        credentialCoordinator.cancel(credentialRequestID)
        releaseKeyRead.signal()
        expect(unexpectedProgress.wait(timeout: .now() + 0.25) == .timedOut,
               "cancelled credential reads must not advance provider progress")
        expect(unexpectedCompletion.wait(timeout: .now() + 0.25) == .timedOut,
               "cancelled credential reads must not start or finish a paid request")
        print("pet generation tests passed")
    }
}
