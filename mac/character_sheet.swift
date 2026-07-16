// Mimo — deterministic processing for GPT Image character sheets.
//
// The provider returns one opaque 1536x1024 PNG containing Seed, Bloom, and
// Radiant in equal thirds. This processor removes the border-connected matte,
// rejects clipped/empty stages, and normalizes all three forms with one scale
// and one feet baseline. No network or model runtime is involved here.

import Cocoa
import Foundation

enum CharacterSheetStageKind: String, CaseIterable, Codable {
    case seed
    case bloom
    case radiant
}

struct CharacterSheetPixelBounds: Equatable, Codable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    var maxX: Int { x + width - 1 }
    var maxY: Int { y + height - 1 }
    var midX: Double { Double(x) + Double(width) / 2 }
}

struct CharacterSheetProcessedStage {
    let kind: CharacterSheetStageKind
    let pngData: Data
    let sourceBounds: CharacterSheetPixelBounds
    let normalizedBounds: CharacterSheetPixelBounds
}

struct CharacterSheetProcessingResult {
    /// A transparent 1536x512 PNG: Seed, Bloom, and Radiant in 512px cells.
    let pngData: Data
    let stages: [CharacterSheetProcessedStage]
    let scale: Double
    /// Top-left pixel coordinate of the shared bottom edge of every form.
    let baselineY: Int

    var stagePNGs: [Data] { stages.map(\.pngData) }
}

enum CharacterSheetProcessingError: LocalizedError, Equatable {
    case notPNG
    case unreadableImage
    case invalidDimensions(width: Int, height: Int)
    case emptyStage(Int)
    case stageTooSmall(Int)
    case stageTouchesMargin(Int)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .notPNG:
            return "Character sheet must be a PNG"
        case .unreadableImage:
            return "Character sheet could not be decoded"
        case .invalidDimensions(let width, let height):
            return "Character sheet must be 1536x1024 (received \(width)x\(height))"
        case .emptyStage(let index):
            return "Character sheet stage \(index + 1) is empty"
        case .stageTooSmall(let index):
            return "Character sheet stage \(index + 1) is too small"
        case .stageTouchesMargin(let index):
            return "Character sheet stage \(index + 1) is clipped or touches an edge"
        case .encodingFailed:
            return "Processed character sheet could not be encoded"
        }
    }
}

/// A small RGBA8 image value used internally and by deterministic fixture tests.
struct CharacterSheetRGBAImage: Equatable {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, fill: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)) {
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
        if fill != (0, 0, 0, 0) {
            for index in stride(from: 0, to: pixels.count, by: 4) {
                pixels[index] = fill.0
                pixels[index + 1] = fill.1
                pixels[index + 2] = fill.2
                pixels[index + 3] = fill.3
            }
        }
    }

    func rgba(x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let index = (y * width + x) * 4
        return (pixels[index], pixels[index + 1], pixels[index + 2], pixels[index + 3])
    }

    mutating func setRGBA(x: Int, y: Int, _ rgba: (UInt8, UInt8, UInt8, UInt8)) {
        let index = (y * width + x) * 4
        pixels[index] = rgba.0
        pixels[index + 1] = rgba.1
        pixels[index + 2] = rgba.2
        pixels[index + 3] = rgba.3
    }
}

enum CharacterSheetProcessor {
    static let inputWidth = 1536
    static let inputHeight = 1024
    static let stageSourceWidth = 512
    static let outputStageSize = 512
    static let outputWidth = 1536
    static let outputHeight = 512

    /// Source forms must have clear matte around them so a malformed layout is
    /// never silently cropped into a desktop sprite.
    static let requiredSourceMargin = 16
    static let outputSidePadding = 32
    static let outputTopPadding = 24
    static let outputBottomPadding = 32

    static func process(pngData: Data) throws -> CharacterSheetProcessingResult {
        guard pngData.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) else {
            throw CharacterSheetProcessingError.notPNG
        }
        let source = try decodePNG(pngData)
        guard source.width == inputWidth, source.height == inputHeight else {
            throw CharacterSheetProcessingError.invalidDimensions(width: source.width, height: source.height)
        }

        var cleanedStages: [CharacterSheetRGBAImage] = []
        var sourceBounds: [CharacterSheetPixelBounds] = []
        for index in 0..<CharacterSheetStageKind.allCases.count {
            var panel = extractPanel(source, index: index)
            removeBorderConnectedMatte(from: &panel)
            removeSmallSpecks(from: &panel)
            let bounds = try validatedBounds(of: panel, stageIndex: index)
            cleanedStages.append(panel)
            sourceBounds.append(bounds)
        }

        let largestWidth = sourceBounds.map(\.width).max() ?? 0
        let largestHeight = sourceBounds.map(\.height).max() ?? 0
        guard largestWidth > 0, largestHeight > 0 else {
            throw CharacterSheetProcessingError.emptyStage(0)
        }
        let availableWidth = outputStageSize - outputSidePadding * 2
        let baselineY = outputHeight - outputBottomPadding
        let availableHeight = baselineY - outputTopPadding
        let scale = min(Double(availableWidth) / Double(largestWidth),
                        Double(availableHeight) / Double(largestHeight))

        var combined = CharacterSheetRGBAImage(width: outputWidth, height: outputHeight)
        var processedStages: [CharacterSheetProcessedStage] = []
        for index in cleanedStages.indices {
            let normalized = normalize(cleanedStages[index], bounds: sourceBounds[index],
                                       scale: scale, baselineY: baselineY)
            guard let normalizedBounds = alphaBounds(of: normalized) else {
                throw CharacterSheetProcessingError.emptyStage(index)
            }
            copy(normalized, into: &combined, destinationX: index * outputStageSize)
            let stagePNG = try encodePNG(normalized)
            processedStages.append(CharacterSheetProcessedStage(
                kind: CharacterSheetStageKind.allCases[index],
                pngData: stagePNG,
                sourceBounds: sourceBounds[index],
                normalizedBounds: normalizedBounds
            ))
        }

        return CharacterSheetProcessingResult(
            pngData: try encodePNG(combined),
            stages: processedStages,
            scale: scale,
            baselineY: baselineY
        )
    }

    // MARK: - PNG conversion

    static func decodePNG(_ data: Data) throws -> CharacterSheetRGBAImage {
        guard let representation = NSBitmapImageRep(data: data),
              let image = representation.cgImage else {
            throw CharacterSheetProcessingError.unreadableImage
        }
        let width = image.width
        let height = image.height
        var output = CharacterSheetRGBAImage(width: width, height: height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        let rendered = output.pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: colorSpace,
                                          bitmapInfo: bitmapInfo) else { return false }
            // CGImage and the RGBA buffer both use top-first scanlines here.
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw CharacterSheetProcessingError.unreadableImage }
        return output
    }

    static func encodePNG(_ image: CharacterSheetRGBAImage) throws -> Data {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let data = Data(image.pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let cgImage = CGImage(width: image.width,
                                    height: image.height,
                                    bitsPerComponent: 8,
                                    bitsPerPixel: 32,
                                    bytesPerRow: image.width * 4,
                                    space: colorSpace,
                                    bitmapInfo: CGBitmapInfo(rawValue:
                                        CGBitmapInfo.byteOrder32Big.rawValue
                                        | CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider,
                                    decode: nil,
                                    shouldInterpolate: false,
                                    intent: .defaultIntent) else {
            throw CharacterSheetProcessingError.encodingFailed
        }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            throw CharacterSheetProcessingError.encodingFailed
        }
        return png
    }

    // MARK: - Matte and component processing

    private static func extractPanel(_ source: CharacterSheetRGBAImage, index: Int) -> CharacterSheetRGBAImage {
        var panel = CharacterSheetRGBAImage(width: stageSourceWidth, height: inputHeight)
        let sourceX = index * stageSourceWidth
        for y in 0..<inputHeight {
            let inputStart = (y * inputWidth + sourceX) * 4
            let outputStart = y * stageSourceWidth * 4
            panel.pixels.replaceSubrange(outputStart..<(outputStart + stageSourceWidth * 4),
                                         with: source.pixels[inputStart..<(inputStart + stageSourceWidth * 4)])
        }
        return panel
    }

    private static func removeBorderConnectedMatte(from image: inout CharacterSheetRGBAImage) {
        let matte = estimatedMatte(image)
        let threshold = matteThreshold(image, matte: matte)
        let thresholdSquared = threshold * threshold
        let width = image.width
        let height = image.height
        var background = [UInt8](repeating: 0, count: width * height)
        var queue: [Int] = []
        queue.reserveCapacity(width * 4 + height * 4)

        func isMatte(_ index: Int) -> Bool {
            let pixel = index * 4
            if image.pixels[pixel + 3] < 16 { return true }
            let dr = Int(image.pixels[pixel]) - matte.0
            let dg = Int(image.pixels[pixel + 1]) - matte.1
            let db = Int(image.pixels[pixel + 2]) - matte.2
            return dr * dr + dg * dg + db * db <= thresholdSquared
        }
        func seed(_ index: Int) {
            guard background[index] == 0, isMatte(index) else { return }
            background[index] = 1
            queue.append(index)
        }

        for x in 0..<width {
            seed(x)
            seed((height - 1) * width + x)
        }
        for y in 0..<height {
            seed(y * width)
            seed(y * width + width - 1)
        }

        var cursor = 0
        while cursor < queue.count {
            let index = queue[cursor]
            cursor += 1
            let x = index % width
            let y = index / width
            if x > 0 { seed(index - 1) }
            if x + 1 < width { seed(index + 1) }
            if y > 0 { seed(index - width) }
            if y + 1 < height { seed(index + width) }
        }

        for index in 0..<(width * height) {
            let pixel = index * 4
            if background[index] == 1 || image.pixels[pixel + 3] < 16 {
                image.pixels[pixel] = 0
                image.pixels[pixel + 1] = 0
                image.pixels[pixel + 2] = 0
                image.pixels[pixel + 3] = 0
            } else {
                // Character sheets intentionally use crisp sprite edges.
                image.pixels[pixel + 3] = 255
            }
        }
    }

    private static func estimatedMatte(_ image: CharacterSheetRGBAImage) -> (Int, Int, Int) {
        var red: [UInt8] = []
        var green: [UInt8] = []
        var blue: [UInt8] = []
        red.reserveCapacity((image.width + image.height) * 2)
        green.reserveCapacity(red.capacity)
        blue.reserveCapacity(red.capacity)

        func sample(x: Int, y: Int) {
            let pixel = (y * image.width + x) * 4
            guard image.pixels[pixel + 3] >= 16 else { return }
            red.append(image.pixels[pixel])
            green.append(image.pixels[pixel + 1])
            blue.append(image.pixels[pixel + 2])
        }
        for x in 0..<image.width {
            sample(x: x, y: 0)
            sample(x: x, y: image.height - 1)
        }
        for y in 1..<(image.height - 1) {
            sample(x: 0, y: y)
            sample(x: image.width - 1, y: y)
        }
        guard !red.isEmpty else { return (0, 0, 0) }
        red.sort(); green.sort(); blue.sort()
        let middle = red.count / 2
        return (Int(red[middle]), Int(green[middle]), Int(blue[middle]))
    }

    private static func matteThreshold(_ image: CharacterSheetRGBAImage,
                                       matte: (Int, Int, Int)) -> Int {
        var distances: [Int] = []
        distances.reserveCapacity((image.width + image.height) * 2)
        func sample(x: Int, y: Int) {
            let pixel = (y * image.width + x) * 4
            guard image.pixels[pixel + 3] >= 16 else { return }
            let dr = Int(image.pixels[pixel]) - matte.0
            let dg = Int(image.pixels[pixel + 1]) - matte.1
            let db = Int(image.pixels[pixel + 2]) - matte.2
            distances.append(Int(Double(dr * dr + dg * dg + db * db).squareRoot()))
        }
        for x in 0..<image.width {
            sample(x: x, y: 0)
            sample(x: x, y: image.height - 1)
        }
        for y in 1..<(image.height - 1) {
            sample(x: 0, y: y)
            sample(x: image.width - 1, y: y)
        }
        guard !distances.isEmpty else { return 24 }
        distances.sort()
        let percentile = distances[min(distances.count - 1, distances.count * 9 / 10)]
        return min(44, max(18, percentile + 10))
    }

    private static func removeSmallSpecks(from image: inout CharacterSheetRGBAImage) {
        let width = image.width
        let height = image.height
        var labels = [Int](repeating: -1, count: width * height)
        var components: [[Int]] = []
        var queue: [Int] = []

        for start in 0..<(width * height) {
            guard labels[start] == -1, image.pixels[start * 4 + 3] > 0 else { continue }
            let label = components.count
            labels[start] = label
            queue.removeAll(keepingCapacity: true)
            queue.append(start)
            var component: [Int] = []
            var cursor = 0
            while cursor < queue.count {
                let index = queue[cursor]
                cursor += 1
                component.append(index)
                let x = index % width
                let y = index / width
                for oy in -1...1 {
                    for ox in -1...1 where ox != 0 || oy != 0 {
                        let nx = x + ox, ny = y + oy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        let neighbor = ny * width + nx
                        guard labels[neighbor] == -1,
                              image.pixels[neighbor * 4 + 3] > 0 else { continue }
                        labels[neighbor] = label
                        queue.append(neighbor)
                    }
                }
            }
            components.append(component)
        }

        guard let largest = components.map(\.count).max(), largest > 0 else { return }
        let minimumArea = max(16, min(256, largest / 500))
        for component in components where component.count < minimumArea {
            for index in component {
                let pixel = index * 4
                image.pixels[pixel] = 0
                image.pixels[pixel + 1] = 0
                image.pixels[pixel + 2] = 0
                image.pixels[pixel + 3] = 0
            }
        }
    }

    private static func validatedBounds(of image: CharacterSheetRGBAImage,
                                        stageIndex: Int) throws -> CharacterSheetPixelBounds {
        guard let bounds = alphaBounds(of: image) else {
            throw CharacterSheetProcessingError.emptyStage(stageIndex)
        }
        let opaquePixels = stride(from: 3, to: image.pixels.count, by: 4)
            .reduce(into: 0) { count, index in if image.pixels[index] > 0 { count += 1 } }
        guard bounds.width >= 24, bounds.height >= 24, opaquePixels >= 384 else {
            throw CharacterSheetProcessingError.stageTooSmall(stageIndex)
        }
        let rightMargin = image.width - (bounds.x + bounds.width)
        let bottomMargin = image.height - (bounds.y + bounds.height)
        guard bounds.x >= requiredSourceMargin,
              bounds.y >= requiredSourceMargin,
              rightMargin >= requiredSourceMargin,
              bottomMargin >= requiredSourceMargin else {
            throw CharacterSheetProcessingError.stageTouchesMargin(stageIndex)
        }
        return bounds
    }

    // MARK: - Shared normalization

    private static func normalize(_ source: CharacterSheetRGBAImage,
                                  bounds: CharacterSheetPixelBounds,
                                  scale: Double,
                                  baselineY: Int) -> CharacterSheetRGBAImage {
        var output = CharacterSheetRGBAImage(width: outputStageSize, height: outputHeight)
        let xOffset = Double(outputStageSize) / 2 - bounds.midX * scale
        let sourceBottomEdge = Double(bounds.y + bounds.height)
        let yOffset = Double(baselineY) - sourceBottomEdge * scale

        let minimumX = max(0, Int(floor(xOffset + Double(bounds.x) * scale)))
        let maximumX = min(output.width - 1,
                           Int(ceil(xOffset + Double(bounds.x + bounds.width) * scale)) - 1)
        let minimumY = max(0, Int(floor(yOffset + Double(bounds.y) * scale)))
        let maximumY = min(output.height - 1,
                           Int(ceil(yOffset + Double(bounds.y + bounds.height) * scale)) - 1)
        guard minimumX <= maximumX, minimumY <= maximumY else { return output }

        for y in minimumY...maximumY {
            let sourceY = Int(floor((Double(y) + 0.5 - yOffset) / scale))
            guard sourceY >= 0, sourceY < source.height else { continue }
            for x in minimumX...maximumX {
                let sourceX = Int(floor((Double(x) + 0.5 - xOffset) / scale))
                guard sourceX >= 0, sourceX < source.width else { continue }
                let inputIndex = (sourceY * source.width + sourceX) * 4
                guard source.pixels[inputIndex + 3] > 0 else { continue }
                let outputIndex = (y * output.width + x) * 4
                output.pixels[outputIndex] = source.pixels[inputIndex]
                output.pixels[outputIndex + 1] = source.pixels[inputIndex + 1]
                output.pixels[outputIndex + 2] = source.pixels[inputIndex + 2]
                output.pixels[outputIndex + 3] = source.pixels[inputIndex + 3]
            }
        }
        return output
    }

    private static func alphaBounds(of image: CharacterSheetRGBAImage) -> CharacterSheetPixelBounds? {
        var minimumX = image.width
        var minimumY = image.height
        var maximumX = -1
        var maximumY = -1
        for y in 0..<image.height {
            for x in 0..<image.width where image.pixels[(y * image.width + x) * 4 + 3] > 0 {
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
            }
        }
        guard maximumX >= minimumX, maximumY >= minimumY else { return nil }
        return CharacterSheetPixelBounds(x: minimumX, y: minimumY,
                                         width: maximumX - minimumX + 1,
                                         height: maximumY - minimumY + 1)
    }

    private static func copy(_ source: CharacterSheetRGBAImage,
                             into destination: inout CharacterSheetRGBAImage,
                             destinationX: Int) {
        for y in 0..<source.height {
            let sourceStart = y * source.width * 4
            let destinationStart = (y * destination.width + destinationX) * 4
            destination.pixels.replaceSubrange(destinationStart..<(destinationStart + source.width * 4),
                                                with: source.pixels[sourceStart..<(sourceStart + source.width * 4)])
        }
    }
}
