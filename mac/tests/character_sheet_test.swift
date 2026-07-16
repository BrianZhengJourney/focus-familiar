import Cocoa

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

private let matte: (UInt8, UInt8, UInt8, UInt8) = (241, 236, 226, 255)
private let ink: (UInt8, UInt8, UInt8, UInt8) = (71, 43, 45, 255)
private let nearMatte: (UInt8, UInt8, UInt8, UInt8) = (232, 227, 217, 255)

private func paintRect(_ image: inout CharacterSheetRGBAImage,
                       x: Int, y: Int, width: Int, height: Int,
                       color: (UInt8, UInt8, UInt8, UInt8)) {
    for py in y..<(y + height) {
        for px in x..<(x + width) { image.setRGBA(x: px, y: py, color) }
    }
}

private func fixture(emptyStage: Int? = nil, clippedStage: Int? = nil) throws -> Data {
    var image = CharacterSheetRGBAImage(width: 1536, height: 1024, fill: matte)
    // Give the inferred matte a little deterministic border variance.
    for x in 0..<image.width {
        let delta = UInt8(x % 3)
        image.setRGBA(x: x, y: 0, (241 + delta, 236 + delta, 226 + delta, 255))
        image.setRGBA(x: x, y: image.height - 1, (241 + delta, 236 + delta, 226 + delta, 255))
    }

    let forms = [
        (x: 170, y: 280, width: 172, height: 600),
        (x: 151, y: 230, width: 210, height: 650),
        (x: 131, y: 180, width: 250, height: 700),
    ]
    for (index, form) in forms.enumerated() where index != emptyStage {
        let panelX = index * 512
        let localX = clippedStage == index ? 5 : form.x
        paintRect(&image, x: panelX + localX, y: form.y,
                  width: form.width, height: form.height, color: ink)
        // A near-background-colored inset must survive because it is not
        // border-connected to the matte.
        paintRect(&image, x: panelX + localX + 20, y: form.y + 30,
                  width: 20, height: 20, color: nearMatte)
        // Provider dust should not expand the character bounds.
        paintRect(&image, x: panelX + 50, y: 50, width: 2, height: 2,
                  color: (130, 40, 170, 255))
    }
    return try CharacterSheetProcessor.encodePNG(image)
}

private func containsColor(_ image: CharacterSheetRGBAImage,
                           _ color: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
    for y in 0..<image.height {
        for x in 0..<image.width {
            let pixel = image.rgba(x: x, y: y)
            if pixel == color { return true }
        }
    }
    return false
}

@main
struct CharacterSheetTests {
    static func main() throws {
        var orientation = CharacterSheetRGBAImage(width: 2, height: 2)
        paintRect(&orientation, x: 0, y: 0, width: 2, height: 1,
                  color: (255, 0, 0, 255))
        paintRect(&orientation, x: 0, y: 1, width: 2, height: 1,
                  color: (0, 0, 255, 255))
        let orientationRoundTrip = try CharacterSheetProcessor.decodePNG(
            CharacterSheetProcessor.encodePNG(orientation))
        expect(orientationRoundTrip.rgba(x: 0, y: 0).0 == 255
               && orientationRoundTrip.rgba(x: 0, y: 1).2 == 255,
               "PNG conversion must preserve the processor's top-left row order")

        do {
            _ = try CharacterSheetProcessor.process(pngData: Data("not png".utf8))
            expect(false, "non-PNG payload should fail")
        } catch {
            expect(error as? CharacterSheetProcessingError == .notPNG,
                   "non-PNG should report notPNG")
        }

        let tiny = CharacterSheetRGBAImage(width: 10, height: 8, fill: matte)
        do {
            _ = try CharacterSheetProcessor.process(pngData: CharacterSheetProcessor.encodePNG(tiny))
            expect(false, "wrong dimensions should fail")
        } catch {
            expect(error as? CharacterSheetProcessingError == .invalidDimensions(width: 10, height: 8),
                   "wrong dimensions should include received size")
        }

        let input = try fixture()
        let result = try CharacterSheetProcessor.process(pngData: input)
        expect(result.stages.map(\.kind) == [.seed, .bloom, .radiant],
               "stage order must be Seed, Bloom, Radiant")
        expect(result.stagePNGs.count == 3, "processor should expose all three stage PNGs")
        expect(result.baselineY == 480, "all stages should share the documented feet baseline")

        let combined = try CharacterSheetProcessor.decodePNG(result.pngData)
        expect(combined.width == 1536 && combined.height == 512,
               "combined sprite sheet must be transparent 1536x512")
        expect(combined.rgba(x: 0, y: 0).3 == 0
               && combined.rgba(x: 511, y: 511).3 == 0,
               "output corners should be transparent")

        let expectedWidths = [172, 210, 250]
        let expectedHeights = [600, 650, 700]
        for index in 0..<3 {
            let stage = result.stages[index]
            expect(stage.sourceBounds.width == expectedWidths[index]
                   && stage.sourceBounds.height == expectedHeights[index],
                   "matte removal should recover stage \(index + 1) bounds and discard dust")
            let bottomEdge = stage.normalizedBounds.y + stage.normalizedBounds.height
            expect(abs(bottomEdge - result.baselineY) <= 1,
                   "stage \(index + 1) feet should align to the shared baseline")
            let decoded = try CharacterSheetProcessor.decodePNG(stage.pngData)
            expect(decoded.width == 512 && decoded.height == 512,
                   "each normalized stage should use a 512px transparent cell")
            expect(containsColor(decoded, nearMatte),
                   "border flood fill must preserve enclosed near-matte character colors")
        }
        expect(result.stages[0].normalizedBounds.height < result.stages[1].normalizedBounds.height
               && result.stages[1].normalizedBounds.height < result.stages[2].normalizedBounds.height,
               "one shared scale must preserve evolution size differences")

        let repeated = try CharacterSheetProcessor.process(pngData: input)
        expect(result.pngData == repeated.pngData,
               "processing the same sheet should be byte-for-byte deterministic")

        do {
            _ = try CharacterSheetProcessor.process(pngData: fixture(emptyStage: 1))
            expect(false, "an empty evolution panel should fail")
        } catch {
            expect(error as? CharacterSheetProcessingError == .emptyStage(1),
                   "empty panel should identify its stage")
        }

        do {
            _ = try CharacterSheetProcessor.process(pngData: fixture(clippedStage: 2))
            expect(false, "a clipped evolution panel should fail")
        } catch {
            expect(error as? CharacterSheetProcessingError == .stageTouchesMargin(2),
                   "clipped panel should identify its stage")
        }

        print("character sheet tests passed")
    }
}
