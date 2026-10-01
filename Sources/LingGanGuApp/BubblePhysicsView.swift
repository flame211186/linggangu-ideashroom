import AppKit
import LingGanGuCore
import SpriteKit
import SwiftUI

struct BubblePhysicsView: NSViewRepresentable {
    let ideas: [Idea]
    let pinnedIdeaID: UUID?
    let reduceMotion: Bool
    let onSelect: (UUID) -> Void
    let onDragReleased: (UUID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SKView {
        let view = BubbleInteractionSKView()
        view.allowsTransparency = true
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.isOpaque = false
        view.layer?.masksToBounds = true
        view.isAsynchronous = false
        view.ignoresSiblingOrder = true
        view.shouldCullNonVisibleNodes = true
        view.preferredFramesPerSecond = reduceMotion ? 30 : 60
        view.setAccessibilityLabel("灵感气泡物理区域")

        let scene = BubblePhysicsScene(size: WidgetMetrics.physicsSceneSize)
        scene.scaleMode = .aspectFit
        scene.backgroundColor = .clear
        context.coordinator.scene = scene
        context.coordinator.update(
            ideas: ideas,
            pinnedIdeaID: pinnedIdeaID,
            reduceMotion: reduceMotion,
            onSelect: onSelect,
            onDragReleased: onDragReleased
        )
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ view: SKView, context: Context) {
        view.preferredFramesPerSecond = reduceMotion ? 30 : 60
        context.coordinator.update(
            ideas: ideas,
            pinnedIdeaID: pinnedIdeaID,
            reduceMotion: reduceMotion,
            onSelect: onSelect,
            onDragReleased: onDragReleased
        )
    }

    final class Coordinator {
        fileprivate var scene: BubblePhysicsScene?
        private var onSelect: (UUID) -> Void = { _ in }
        private var onDragReleased: (UUID) -> Void = { _ in }

        fileprivate func update(
            ideas: [Idea],
            pinnedIdeaID: UUID?,
            reduceMotion: Bool,
            onSelect: @escaping (UUID) -> Void,
            onDragReleased: @escaping (UUID) -> Void
        ) {
            self.onSelect = onSelect
            self.onDragReleased = onDragReleased
            scene?.onSelect = { [weak self] id in self?.onSelect(id) }
            scene?.onDragReleased = { [weak self] id in self?.onDragReleased(id) }
            scene?.sync(
                ideas: ideas,
                pinnedIdeaID: pinnedIdeaID,
                reduceMotion: reduceMotion
            )
        }
    }
}

/// Lets actual bubbles own the mouse while transparent space passes through to
/// `NSPanel.isMovableByWindowBackground`. Window movement is converted into a
/// counter-velocity so loose bubbles visibly lag and collide inside the cap.
final class BubbleInteractionSKView: SKView {
    private var windowMoveObserver: NSObjectProtocol?
    private var lastWindowOrigin: NSPoint?

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        containsBubble(atViewPoint: point) ? self : nil
    }

    func containsBubble(atViewPoint point: NSPoint) -> Bool {
        guard bounds.contains(point),
              let physicsScene = scene as? BubblePhysicsScene else {
            return false
        }
        let scenePoint = physicsScene.convertPoint(fromView: point)
        return physicsScene.containsBubble(at: scenePoint)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObservingWindow()
        guard let window else { return }

        lastWindowOrigin = window.frame.origin
        windowMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self, let window else { return }
            let newOrigin = window.frame.origin
            guard let oldOrigin = self.lastWindowOrigin else {
                self.lastWindowOrigin = newOrigin
                return
            }
            self.lastWindowOrigin = newOrigin
            let delta = CGVector(
                dx: newOrigin.x - oldOrigin.x,
                dy: newOrigin.y - oldOrigin.y
            )
            (self.scene as? BubblePhysicsScene)?.applyContainerMovement(
                WidgetMetrics.logicalContainerDelta(from: delta)
            )
        }
    }

    deinit {
        stopObservingWindow()
    }

    private func stopObservingWindow() {
        if let windowMoveObserver {
            NotificationCenter.default.removeObserver(windowMoveObserver)
        }
        windowMoveObserver = nil
        lastWindowOrigin = nil
    }
}

final class BubblePhysicsScene: SKScene {
    var onSelect: (UUID) -> Void = { _ in }
    var onDragReleased: (UUID) -> Void = { _ in }

    private let bubbleRadius: CGFloat = 15
    private var bubbleNodes: [UUID: IdeaBubbleNode] = [:]
    private var boundaryNode: SKNode?
    private var safeBoundaryPath: CGPath?
    private var safeBoundaryPoints: [CGPoint] = []
    private var boundaryCenter = CGPoint.zero
    private(set) var usesReferenceCapBoundary = false
    private var pinnedIdeaID: UUID?
    private weak var pressedNode: IdeaBubbleNode?
    private var pressOrigin = CGPoint.zero
    private var lastValidDragPoint = CGPoint.zero
    private var didDrag = false
    private var reduceMotionEnabled = false

    override func didMove(to view: SKView) {
        physicsWorld.gravity = CGVector(dx: 0, dy: -2.15)
        rebuildBoundary()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        rebuildBoundary()
        for node in bubbleNodes.values {
            node.position = clampedPoint(node.position)
        }
    }

    override func didSimulatePhysics() {
        super.didSimulatePhysics()
        for node in bubbleNodes.values {
            guard let body = node.physicsBody,
                  body.isDynamic,
                  !isInsideBoundary(node.position) else {
                continue
            }

            let corrected = clampedPoint(node.position)
            let inward = CGVector(
                dx: boundaryCenter.x - corrected.x,
                dy: boundaryCenter.y - corrected.y
            )
            let inwardLength = max(hypot(inward.dx, inward.dy), 1)
            let inwardNormal = CGVector(
                dx: inward.dx / inwardLength,
                dy: inward.dy / inwardLength
            )
            let inwardVelocity = body.velocity.dx * inwardNormal.dx
                + body.velocity.dy * inwardNormal.dy
            if inwardVelocity < 0 {
                body.velocity = CGVector(
                    dx: body.velocity.dx - 1.54 * inwardVelocity * inwardNormal.dx,
                    dy: body.velocity.dy - 1.54 * inwardVelocity * inwardNormal.dy
                )
            }
            node.position = corrected
        }
    }

    func sync(
        ideas: [Idea],
        pinnedIdeaID: UUID?,
        reduceMotion: Bool
    ) {
        reduceMotionEnabled = reduceMotion
        let validIDs = Set(ideas.map(\.id))
        for (id, node) in bubbleNodes where !validIDs.contains(id) {
            node.removeFromParent()
            bubbleNodes.removeValue(forKey: id)
        }

        for (index, idea) in ideas.enumerated() {
            let node: IdeaBubbleNode
            if let existing = bubbleNodes[idea.id] {
                node = existing
            } else {
                node = IdeaBubbleNode(
                    ideaID: idea.id,
                    radius: bubbleRadius,
                    color: bubbleColor(for: idea)
                )
                node.position = spawnPoint(index: index, ideaID: idea.id)
                bubbleNodes[idea.id] = node
                addChild(node)
            }
            node.setInProgress(idea.status == .testing, reduceMotion: reduceMotion)
        }

        updatePinnedIdea(pinnedIdeaID)
    }

    var debugBubbleCount: Int {
        bubbleNodes.count
    }

    var debugBubbleDiameter: CGFloat {
        bubbleRadius * 2
    }

    func debugAllBubblesInsideBoundary() -> Bool {
        bubbleNodes.values.allSatisfy { isInsideBoundary($0.position) }
    }

    func debugUsesPhysicalVolumeAndBounce() -> Bool {
        guard usesReferenceCapBoundary,
              let boundaryBody = boundaryNode?.physicsBody,
              boundaryBody.restitution > 0 else {
            return false
        }
        return bubbleNodes.values.allSatisfy { node in
            guard let body = node.physicsBody else { return false }
            return body.area > 0
                && body.usesPreciseCollisionDetection
                && body.restitution > 0
                && body.collisionBitMask & PhysicsCategory.boundary != 0
                && body.collisionBitMask & PhysicsCategory.bubble != 0
        }
    }

    func debugSelectFirstBubble() -> UUID? {
        guard let node = bubbleNodes.values.first else { return nil }
        updatePinnedIdea(node.ideaID)
        onSelect(node.ideaID)
        return node.ideaID
    }

    func debugReleasePinnedBubbleOutsideBoundary() -> UUID? {
        guard let pinnedIdeaID, let node = bubbleNodes[pinnedIdeaID] else { return nil }
        node.position = clampedPoint(CGPoint(x: -500, y: size.height + 500))
        node.physicsBody?.isDynamic = true
        self.pinnedIdeaID = nil
        onDragReleased(node.ideaID)
        return node.ideaID
    }

    func debugIsPinned(_ ideaID: UUID) -> Bool {
        pinnedIdeaID == ideaID && bubbleNodes[ideaID]?.physicsBody?.isDynamic == false
    }

    func debugIsHighlighted(_ ideaID: UUID) -> Bool {
        bubbleNodes[ideaID]?.isInProgress == true
    }

    func debugUsesSolidBubbleRendering(_ ideaID: UUID) -> Bool {
        guard let node = bubbleNodes[ideaID] else { return false }
        return node.glowWidth == 0 && node.children.isEmpty
    }

    func debugFirstBubblePosition() -> CGPoint? {
        bubbleNodes.values.first?.position
    }

    func debugMeanVelocity() -> CGVector {
        let bodies = bubbleNodes.values.compactMap(\.physicsBody).filter(\.isDynamic)
        guard !bodies.isEmpty else { return .zero }
        let total = bodies.reduce(CGVector.zero) { partial, body in
            CGVector(
                dx: partial.dx + body.velocity.dx,
                dy: partial.dy + body.velocity.dy
            )
        }
        return CGVector(
            dx: total.dx / CGFloat(bodies.count),
            dy: total.dy / CGFloat(bodies.count)
        )
    }

    func containsBubble(at point: CGPoint) -> Bool {
        bubbleNode(at: point) != nil
    }

    func applyContainerMovement(_ delta: CGVector) {
        guard abs(delta.dx) > 0.01 || abs(delta.dy) > 0.01 else { return }

        let maxStep: CGFloat = 22
        let dx = min(max(delta.dx, -maxStep), maxStep)
        let dy = min(max(delta.dy, -maxStep), maxStep)
        let movementScale: CGFloat = reduceMotionEnabled ? 1.8 : 6.5
        let maximumSpeed: CGFloat = reduceMotionEnabled ? 110 : 360

        for node in bubbleNodes.values {
            guard let body = node.physicsBody, body.isDynamic else { continue }
            body.velocity = CGVector(
                dx: min(
                    max(body.velocity.dx - dx * movementScale, -maximumSpeed),
                    maximumSpeed
                ),
                dy: min(
                    max(body.velocity.dy - dy * movementScale, -maximumSpeed),
                    maximumSpeed
                )
            )
            body.angularVelocity = min(
                max(body.angularVelocity - dx * 0.035, -3),
                3
            )
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = event.location(in: self)
        guard let node = bubbleNode(at: point) else { return }
        pressedNode = node
        pressOrigin = point
        lastValidDragPoint = node.position
        didDrag = false
        node.physicsBody?.velocity = .zero
        node.physicsBody?.angularVelocity = 0
        node.physicsBody?.isDynamic = false
        node.zPosition = 20
    }

    override func mouseDragged(with event: NSEvent) {
        guard let node = pressedNode else { return }
        let point = event.location(in: self)
        if hypot(point.x - pressOrigin.x, point.y - pressOrigin.y) > 3 {
            didDrag = true
        }
        let clamped = clampedPoint(point)
        node.position = clamped
        lastValidDragPoint = clamped
    }

    override func mouseUp(with event: NSEvent) {
        guard let node = pressedNode else { return }
        defer {
            pressedNode = nil
            node.zPosition = 2
        }

        if didDrag {
            node.position = clampedPoint(lastValidDragPoint)
            node.physicsBody?.isDynamic = true
            node.physicsBody?.velocity = .zero
            node.physicsBody?.angularVelocity = 0
            if pinnedIdeaID == node.ideaID {
                pinnedIdeaID = nil
            }
            onDragReleased(node.ideaID)
        } else {
            updatePinnedIdea(node.ideaID)
            onSelect(node.ideaID)
        }
    }

    private func rebuildBoundary() {
        boundaryNode?.removeFromParent()
        guard size.width > 0, size.height > 0 else { return }

        let geometry = CapBoundaryGeometry.make(
            sceneSize: size,
            bubbleRadius: bubbleRadius
        )
        usesReferenceCapBoundary = geometry.usesReferenceImage
        safeBoundaryPath = geometry.safePath
        safeBoundaryPoints = geometry.safePoints
        boundaryCenter = geometry.center

        let boundary = SKNode()
        boundary.physicsBody = SKPhysicsBody(edgeLoopFrom: geometry.edgePath)
        boundary.physicsBody?.friction = 0.34
        boundary.physicsBody?.restitution = 0.56
        boundary.physicsBody?.categoryBitMask = PhysicsCategory.boundary
        boundary.physicsBody?.collisionBitMask = PhysicsCategory.bubble
        addChild(boundary)
        boundaryNode = boundary

        for node in bubbleNodes.values {
            node.position = clampedPoint(node.position)
        }
    }

    private func updatePinnedIdea(_ newValue: UUID?) {
        if let oldID = pinnedIdeaID, oldID != newValue, let oldNode = bubbleNodes[oldID] {
            oldNode.physicsBody?.isDynamic = true
        }
        pinnedIdeaID = newValue
        guard let newValue, let node = bubbleNodes[newValue] else { return }
        node.position = clampedPoint(node.position)
        node.physicsBody?.velocity = .zero
        node.physicsBody?.angularVelocity = 0
        node.physicsBody?.isDynamic = false
    }

    private func bubbleNode(at point: CGPoint) -> IdeaBubbleNode? {
        for candidate in nodes(at: point) {
            var node: SKNode? = candidate
            while let current = node {
                if let bubble = current as? IdeaBubbleNode {
                    return bubble
                }
                node = current.parent
            }
        }
        return nil
    }

    private func spawnPoint(index: Int, ideaID: UUID) -> CGPoint {
        let seed = ideaID.uuidString.unicodeScalars.reduce(0) {
            ($0 &* 31 &+ Int($1.value)) & 0x7fffffff
        }
        let column = index % 7
        let row = index / 7
        let jitterX = CGFloat((seed % 13) - 6)
        let jitterY = CGFloat(((seed / 13) % 9) - 4)
        return clampedPoint(
            CGPoint(
                x: 55 + CGFloat(column) * 35 + jitterX,
                y: size.height - 34 - CGFloat(row) * 34 + jitterY
            )
        )
    }

    private func clampedPoint(_ point: CGPoint) -> CGPoint {
        guard let safeBoundaryPath, safeBoundaryPoints.count >= 3 else {
            return point
        }
        if safeBoundaryPath.contains(point) {
            return point
        }

        var closest = safeBoundaryPoints[0]
        var closestDistance = CGFloat.greatestFiniteMagnitude
        for index in safeBoundaryPoints.indices {
            let start = safeBoundaryPoints[index]
            let end = safeBoundaryPoints[(index + 1) % safeBoundaryPoints.count]
            let candidate = closestPoint(to: point, onSegmentFrom: start, to: end)
            let distance = hypot(candidate.x - point.x, candidate.y - point.y)
            if distance < closestDistance {
                closestDistance = distance
                closest = candidate
            }
        }

        let inward = CGVector(
            dx: boundaryCenter.x - closest.x,
            dy: boundaryCenter.y - closest.y
        )
        let inwardLength = max(hypot(inward.dx, inward.dy), 1)
        return CGPoint(
            x: closest.x + inward.dx / inwardLength * 2.5,
            y: closest.y + inward.dy / inwardLength * 2.5
        )
    }

    private func isInsideBoundary(_ point: CGPoint) -> Bool {
        safeBoundaryPath?.contains(point) == true
    }

    private func closestPoint(
        to point: CGPoint,
        onSegmentFrom start: CGPoint,
        to end: CGPoint
    ) -> CGPoint {
        let segment = CGVector(dx: end.x - start.x, dy: end.y - start.y)
        let lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy
        guard lengthSquared > 0 else { return start }
        let offset = CGVector(dx: point.x - start.x, dy: point.y - start.y)
        let projection = min(
            max((offset.dx * segment.dx + offset.dy * segment.dy) / lengthSquared, 0),
            1
        )
        return CGPoint(
            x: start.x + segment.dx * projection,
            y: start.y + segment.dy * projection
        )
    }

    private func bubbleColor(for idea: Idea) -> NSColor {
        let palette: [NSColor] = [
            NSColor(red: 0.67, green: 0.74, blue: 0.60, alpha: 1),
            NSColor(red: 0.89, green: 0.72, blue: 0.35, alpha: 1),
            NSColor(red: 0.76, green: 0.68, blue: 0.85, alpha: 1),
            NSColor(red: 0.91, green: 0.55, blue: 0.43, alpha: 1)
        ]
        let seed = idea.tags.first?.unicodeScalars.reduce(0) {
            $0 + Int($1.value)
        } ?? idea.id.uuidString.hashValue
        return palette[abs(seed) % palette.count]
    }

    private enum PhysicsCategory {
        static let boundary: UInt32 = 1 << 0
        static let bubble: UInt32 = 1 << 1
    }
}

private struct CapBoundaryGeometry {
    let edgePath: CGPath
    let safePath: CGPath
    let safePoints: [CGPoint]
    let center: CGPoint
    let usesReferenceImage: Bool

    static func make(sceneSize: CGSize, bubbleRadius: CGFloat) -> CapBoundaryGeometry {
        guard let normalizedPoints = normalizedReferencePoints,
              normalizedPoints.count >= 48 else {
            return fallback(sceneSize: sceneSize, bubbleRadius: bubbleRadius)
        }

        let renderedRect = alignedReferenceRect(sceneSize: sceneSize)
        let sampledEdgePoints = normalizedPoints.map { point in
            CGPoint(
                x: renderedRect.minX + point.x * renderedRect.width,
                y: renderedRect.minY + point.y * renderedRect.height
            )
        }
        let center = CGPoint(
            x: sampledEdgePoints.reduce(0) { $0 + $1.x } / CGFloat(sampledEdgePoints.count),
            y: sampledEdgePoints.reduce(0) { $0 + $1.y } / CGFloat(sampledEdgePoints.count)
        )
        let visibleGlassInset: CGFloat = 7
        let edgePoints = inset(
            points: sampledEdgePoints,
            toward: center,
            by: visibleGlassInset
        )
        let safeInset = bubbleRadius + 1.5
        let safePoints = inset(
            points: edgePoints,
            toward: center,
            by: safeInset
        )
        return CapBoundaryGeometry(
            edgePath: closedPath(points: edgePoints),
            safePath: closedPath(points: safePoints),
            safePoints: safePoints,
            center: center,
            usesReferenceImage: true
        )
    }

    private static func inset(
        points: [CGPoint],
        toward center: CGPoint,
        by distance: CGFloat
    ) -> [CGPoint] {
        points.map { point in
            let vector = CGVector(dx: point.x - center.x, dy: point.y - center.y)
            let length = max(hypot(vector.dx, vector.dy), distance + 1)
            let ratio = max((length - distance) / length, 0.05)
            return CGPoint(
                x: center.x + vector.dx * ratio,
                y: center.y + vector.dy * ratio
            )
        }
    }

    /// The user supplied the cap rim as a tight crop of the same mushroom.
    /// These measured coordinates register that crop back onto the 320 × 404
    /// mushroom asset and then into the 288 × 206 SpriteKit viewport.
    private static func alignedReferenceRect(sceneSize: CGSize) -> CGRect {
        let baselineSceneSize = CGSize(width: 288, height: 206)
        let baselineRect = CGRect(
            x: -2.83,
            y: -16.87,
            width: 277.17,
            height: 226.37
        )
        let scaleX = sceneSize.width / baselineSceneSize.width
        let scaleY = sceneSize.height / baselineSceneSize.height
        return CGRect(
            x: baselineRect.minX * scaleX,
            y: baselineRect.minY * scaleY,
            width: baselineRect.width * scaleX,
            height: baselineRect.height * scaleY
        )
    }

    private static let normalizedReferencePoints: [CGPoint]? = {
        guard let url = AppResources.bundle.url(
            forResource: "linggangu-mushroom-cap-outer-rim",
            withExtension: "png"
        ),
        let data = try? Data(contentsOf: url),
        let bitmap = NSBitmapImageRep(data: data) else {
            return nil
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else { return nil }

        let center = CGPoint(x: CGFloat(width) * 0.5, y: CGFloat(height) * 0.5)
        let maximumRadius = Int(hypot(CGFloat(width), CGFloat(height)))
        let sampleCount = 112
        let alphaThreshold: CGFloat = 0.12
        let requiredOpaqueSamples = 3
        var points: [CGPoint] = []
        points.reserveCapacity(sampleCount)

        for index in 0..<sampleCount {
            let angle = CGFloat(index) / CGFloat(sampleCount) * .pi * 2
            let direction = CGVector(dx: cos(angle), dy: sin(angle))
            var opaqueRun = 0
            var hitPoint: CGPoint?

            for step in 0...maximumRadius {
                let radius = CGFloat(step)
                let x = Int((center.x + direction.dx * radius).rounded())
                let y = Int((center.y + direction.dy * radius).rounded())
                guard x >= 0, x < width, y >= 0, y < height else { break }

                let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                if alpha >= alphaThreshold {
                    opaqueRun += 1
                    if opaqueRun >= requiredOpaqueSamples {
                        let firstOpaqueRadius = max(
                            radius - CGFloat(requiredOpaqueSamples - 1),
                            0
                        )
                        hitPoint = CGPoint(
                            x: center.x + direction.dx * firstOpaqueRadius,
                            y: center.y + direction.dy * firstOpaqueRadius
                        )
                        break
                    }
                } else {
                    opaqueRun = 0
                }
            }

            guard let hitPoint else { return nil }
            points.append(
                CGPoint(
                    x: hitPoint.x / CGFloat(width),
                    // NSBitmapImageRep addresses rows from the image top,
                    // while SpriteKit uses a bottom-left scene origin.
                    y: 1 - hitPoint.y / CGFloat(height)
                )
            )
        }
        return points
    }()

    private static func fallback(
        sceneSize: CGSize,
        bubbleRadius: CGFloat
    ) -> CapBoundaryGeometry {
        let rect = CGRect(
            x: 22,
            y: 5,
            width: max(sceneSize.width - 44, 1),
            height: max(sceneSize.height - 10, 1)
        )
        let sampleCount = 96
        let edgePoints = (0..<sampleCount).map { index in
            let angle = CGFloat(index) / CGFloat(sampleCount) * .pi * 2
            return CGPoint(
                x: rect.midX + cos(angle) * rect.width / 2,
                y: rect.midY + sin(angle) * rect.height / 2
            )
        }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let safePoints = edgePoints.map { point in
            let vector = CGVector(dx: point.x - center.x, dy: point.y - center.y)
            let distance = max(hypot(vector.dx, vector.dy), bubbleRadius + 2)
            let ratio = (distance - bubbleRadius - 1.5) / distance
            return CGPoint(
                x: center.x + vector.dx * ratio,
                y: center.y + vector.dy * ratio
            )
        }
        return CapBoundaryGeometry(
            edgePath: closedPath(points: edgePoints),
            safePath: closedPath(points: safePoints),
            safePoints: safePoints,
            center: center,
            usesReferenceImage: false
        )
    }

    private static func closedPath(points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        path.addLines(between: Array(points.dropFirst()))
        path.closeSubpath()
        return path
    }
}

private final class IdeaBubbleNode: SKShapeNode {
    let ideaID: UUID
    private var progressState = false

    var isInProgress: Bool {
        progressState
    }

    init(ideaID: UUID, radius: CGFloat, color: NSColor) {
        self.ideaID = ideaID
        super.init()

        path = CGPath(
            ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2),
            transform: nil
        )
        fillColor = color
        strokeColor = NSColor.white.withAlphaComponent(0.48)
        lineWidth = 1
        glowWidth = 0
        zPosition = 2
        name = "idea-bubble-\(ideaID.uuidString)"

        let body = SKPhysicsBody(circleOfRadius: radius)
        body.affectedByGravity = true
        body.allowsRotation = true
        body.mass = 0.022
        body.friction = 0.24
        body.restitution = 0.54
        body.linearDamping = 0.34
        body.angularDamping = 0.5
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask = 1 << 1
        body.collisionBitMask = (1 << 0) | (1 << 1)
        physicsBody = body
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    func setInProgress(_ active: Bool, reduceMotion: Bool) {
        _ = reduceMotion
        guard progressState != active else { return }
        progressState = active
        if active {
            strokeColor = NSColor(
                red: 1,
                green: 0.73,
                blue: 0.18,
                alpha: 1
            )
            lineWidth = 2.2
        } else {
            strokeColor = NSColor.white.withAlphaComponent(0.48)
            lineWidth = 1
        }
    }
}
