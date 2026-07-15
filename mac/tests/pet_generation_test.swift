import Foundation

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
        print("pet generation parser tests passed")
    }
}
