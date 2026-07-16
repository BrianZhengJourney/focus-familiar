import Cocoa

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
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

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        let png = rep.representation(using: .png, properties: [:])!
        let size = PetGenerationCoordinator.pngPixelSize(png)
        expect(size?.0 == 4 && size?.1 == 3, "PNG dimensions should be decoded")
        print("pet generation tests passed")
    }
}
