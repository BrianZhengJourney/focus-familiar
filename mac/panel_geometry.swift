import Cocoa

func clampedPanelOrigin(_ origin: NSPoint, size: NSSize, inside visibleFrame: NSRect) -> NSPoint {
    let maxX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
    let maxY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
    return NSPoint(
        x: min(max(origin.x, visibleFrame.minX), maxX),
        y: min(max(origin.y, visibleFrame.minY), maxY)
    )
}

private func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
    let intersection = lhs.intersection(rhs)
    guard !intersection.isNull, !intersection.isEmpty else { return 0 }
    return intersection.width * intersection.height
}

func recoveredPanelOrigin(saved: NSPoint?, fallback: NSPoint, size: NSSize,
                          visibleFrames: [NSRect]) -> NSPoint {
    guard let saved else { return fallback }
    let savedFrame = NSRect(origin: saved, size: size)
    guard let best = visibleFrames
        .map({ ($0, intersectionArea(savedFrame, $0)) })
        .filter({ $0.1 > 0 })
        .max(by: { $0.1 < $1.1 })?.0
    else { return fallback }
    return clampedPanelOrigin(saved, size: size, inside: best)
}
