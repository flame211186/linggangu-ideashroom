import AppKit

enum WidgetMetrics {
    static let designSize = NSSize(width: 320, height: 404)
    static let displayScale: CGFloat = 2.0 / 3.0
    static let windowSize = NSSize(width: 214, height: 270)
    static let physicsSceneSize = CGSize(width: 288, height: 206)
    static let dragThreshold: CGFloat = 3

    static func logicalContainerDelta(from physicalDelta: CGVector) -> CGVector {
        CGVector(
            dx: physicalDelta.dx / displayScale,
            dy: physicalDelta.dy / displayScale
        )
    }
}
