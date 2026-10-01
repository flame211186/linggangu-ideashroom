import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private enum Constants {
        static let widgetSize = WidgetMetrics.windowSize
        static let legacyWidgetSize = WidgetMetrics.designSize
        static let captureSize = NSSize(width: 520, height: 180)
        static let workbenchSize = NSSize(width: 1040, height: 720)
        static let aiSettingsSize = NSSize(width: 520, height: 500)
        static let aiGuideSize = NSSize(width: 640, height: 620)
        static let bubbleDetailSize = NSSize(width: 320, height: 240)
        static let bubbleDetailGap: CGFloat = 10
        static let edgeInset: CGFloat = 14
        static let snapThreshold: CGFloat = 22
        static let savedX = "widget.position.x"
        static let savedY = "widget.position.y"
        static let hasSavedPosition = "widget.position.exists"
        static let layoutVersion = "widget.position.layout-version"
        static let currentLayoutVersion = 2
        static let alwaysOnTop = "widget.alwaysOnTop"
    }

    let appState: IdeaAppState
    private(set) var widgetPanel: WidgetPanel?
    private(set) var capturePanel: KeyablePanel?
    private(set) var bubbleDetailPanel: KeyablePanel?
    private(set) var workbenchWindow: NSWindow?
    private(set) var aiSettingsWindow: NSWindow?
    private(set) var aiGuideWindow: NSWindow?
    private var pendingSnap: DispatchWorkItem?
    private weak var widgetDragRecognizer: WidgetWindowDragGestureRecognizer?
    private var bubbleDetailObservation: AnyCancellable?
    private var privacyObservation: AnyCancellable?

    var isAlwaysOnTop: Bool {
        UserDefaults.standard.object(forKey: Constants.alwaysOnTop) as? Bool ?? true
    }

    init(appState: IdeaAppState) {
        self.appState = appState
        super.init()
        bubbleDetailObservation = appState.$bubbleDetailIdeaID
            .removeDuplicates()
            .sink { [weak self] selectedIdeaID in
                // `@Published` emits from `willSet`. Defer panel creation until
                // the state property and its computed `bubbleDetailIdea` agree.
                DispatchQueue.main.async { [weak self] in
                    self?.syncBubbleDetailPanel(selectedIdeaID: selectedIdeaID)
                }
            }
        privacyObservation = appState.$pendingPrivacyAction
            .sink { [weak self] action in
                guard action != nil else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.showWorkbench()
                }
            }
    }

    func showWidget() {
        let panel = widgetPanel ?? makeWidgetPanel()
        widgetPanel = panel
        panel.orderFrontRegardless()
        syncBubbleDetailPanel(selectedIdeaID: appState.bubbleDetailIdeaID)
    }

    func toggleWidget() {
        if widgetPanel?.isVisible == true {
            widgetPanel?.orderOut(nil)
            bubbleDetailPanel?.orderOut(nil)
        } else {
            showWidget()
        }
    }

    func showQuickCapture() {
        let panel = capturePanel ?? makeCapturePanel()
        capturePanel = panel
        if !panel.isVisible {
            positionCapturePanel(panel)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hideQuickCapture() {
        capturePanel?.orderOut(nil)
    }

    func showWorkbench() {
        let window = workbenchWindow ?? makeWorkbenchWindow()
        workbenchWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func showAISettings() {
        let window = aiSettingsWindow ?? makeAISettingsWindow()
        aiSettingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func showAIConfigurationGuide() {
        let window = aiGuideWindow ?? makeAIConfigurationGuideWindow()
        aiGuideWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Constants.alwaysOnTop)
        widgetPanel?.level = enabled ? .floating : .normal
        bubbleDetailPanel?.level = enabled ? .floating : .normal
    }

    func debugWindowDragAllowed(at point: NSPoint) -> Bool {
        widgetDragRecognizer?.shouldRecognizeAtPoint(point) == true
    }

    func windowDidMove(_ notification: Notification) {
        guard notification.object as? NSWindow === widgetPanel else { return }
        if bubbleDetailPanel?.isVisible == true {
            positionBubbleDetailPanel()
        }
        pendingSnap?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.snapAndRememberWidget()
        }
        pendingSnap = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === workbenchWindow {
            workbenchWindow = nil
        } else if window === aiSettingsWindow {
            aiSettingsWindow = nil
        } else if window === aiGuideWindow {
            aiGuideWindow = nil
        }
    }

    private func makeWidgetPanel() -> WidgetPanel {
        let panel = WidgetPanel(
            contentRect: NSRect(origin: .zero, size: Constants.widgetSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(
            rootView: ScaledWidgetRoot(
                content: WidgetView(
                    appState: appState,
                    openQuickCapture: { [weak self] in self?.showQuickCapture() },
                    openWorkbench: { [weak self] in self?.showWorkbench() }
                )
            )
        )
        let eventRootView = WidgetEventRootView(
            frame: NSRect(origin: .zero, size: Constants.widgetSize)
        )
        hostingView.frame = eventRootView.bounds
        hostingView.autoresizingMask = [.width, .height]
        eventRootView.addSubview(hostingView)
        panel.contentView = eventRootView
        panel.setContentSize(Constants.widgetSize)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.level = isAlwaysOnTop ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.delegate = self
        panel.setAccessibilityLabel("灵感菇桌面组件")
        let dragRecognizer = WidgetWindowDragGestureRecognizer(
            target: self,
            action: #selector(handleWidgetDrag(_:))
        )
        dragRecognizer.delaysPrimaryMouseButtonEvents = true
        dragRecognizer.shouldRecognizeAtPoint = { [weak eventRootView] point in
            eventRootView?.containsIdeaBubble(at: point) != true
        }
        eventRootView.addGestureRecognizer(dragRecognizer)
        widgetDragRecognizer = dragRecognizer
        restoreWidgetPosition(panel)
        return panel
    }

    private func makeCapturePanel() -> KeyablePanel {
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: Constants.captureSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = NSHostingController(
            rootView: QuickCaptureView(
                appState: appState,
                save: { [weak self] draft in
                    guard let self else { return false }
                    let didSave = await self.appState.capture(draft)
                    if didSave {
                        self.hideQuickCapture()
                        self.showWidget()
                    }
                    return didSave
                },
                cancel: { [weak self] in self?.hideQuickCapture() }
            )
        )
        panel.setContentSize(Constants.captureSize)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setAccessibilityLabel("快速记录想法")
        return panel
    }

    private func makeBubbleDetailPanel() -> KeyablePanel {
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: Constants.bubbleDetailSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = NSHostingController(
            rootView: BubbleDetailPanelView(
                appState: appState,
                openWorkbench: { [weak self] in self?.showWorkbench() }
            )
        )
        panel.setContentSize(Constants.bubbleDetailSize)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.level = isAlwaysOnTop ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setAccessibilityLabel("灵感详情")
        return panel
    }

    private func makeWorkbenchWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Constants.workbenchSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "灵感菇工作台"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        window.minSize = NSSize(width: 920, height: 620)
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: WorkbenchView(
                appState: appState,
                openQuickCapture: { [weak self] in self?.showQuickCapture() },
                openAISettings: { [weak self] in self?.showAISettings() }
            )
        )
        window.setContentSize(Constants.workbenchSize)
        window.center()
        window.setAccessibilityLabel("灵感菇完整工作台")
        return window
    }

    private func makeAISettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Constants.aiSettingsSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "灵感菇 AI 设置"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: AISettingsView(
                appState: appState,
                showGuide: { [weak self] in self?.showAIConfigurationGuide() },
                close: { [weak window] in window?.close() }
            )
        )
        window.setContentSize(Constants.aiSettingsSize)
        window.center()
        window.setAccessibilityLabel("灵感菇 AI 设置")
        return window
    }

    private func makeAIConfigurationGuideWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Constants.aiGuideSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "灵感菇 AI 配置指南"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: AIConfigurationGuideView(
                close: { [weak window] in window?.close() }
            )
        )
        window.setContentSize(Constants.aiGuideSize)
        window.center()
        window.setAccessibilityLabel("灵感菇 AI 配置指南")
        return window
    }

    private func positionCapturePanel(_ panel: NSWindow) {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            panel.center()
            return
        }
        let origin = NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.maxY - panel.frame.height - 82
        )
        panel.setFrameOrigin(origin)
    }

    private func syncBubbleDetailPanel(selectedIdeaID: UUID?) {
        guard selectedIdeaID != nil,
              widgetPanel?.isVisible == true else {
            bubbleDetailPanel?.orderOut(nil)
            return
        }

        let panel = bubbleDetailPanel ?? makeBubbleDetailPanel()
        bubbleDetailPanel = panel
        panel.level = isAlwaysOnTop ? .floating : .normal
        positionBubbleDetailPanel()
        panel.makeKeyAndOrderFront(nil)
    }

    private func positionBubbleDetailPanel() {
        guard let widget = widgetPanel,
              let detail = bubbleDetailPanel,
              let visible = (widget.screen ?? NSScreen.main)?.visibleFrame else {
            return
        }

        let rightX = widget.frame.maxX + Constants.bubbleDetailGap
        let leftX = widget.frame.minX - detail.frame.width - Constants.bubbleDetailGap
        let preferredX = rightX + detail.frame.width <= visible.maxX
            ? rightX
            : leftX
        let y = min(
            max(widget.frame.maxY - detail.frame.height, visible.minY),
            visible.maxY - detail.frame.height
        )
        detail.setFrameOrigin(
            NSPoint(
                x: min(max(preferredX, visible.minX), visible.maxX - detail.frame.width),
                y: y
            )
        )
    }

    private func restoreWidgetPosition(_ panel: NSWindow) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Constants.hasSavedPosition) else {
            guard let visible = NSScreen.main?.visibleFrame else {
                panel.center()
                return
            }
            panel.setFrameOrigin(
                NSPoint(
                    x: visible.maxX - panel.frame.width - Constants.edgeInset,
                    y: visible.maxY - panel.frame.height - Constants.edgeInset
                )
            )
            return
        }

        var saved = NSPoint(
            x: defaults.double(forKey: Constants.savedX),
            y: defaults.double(forKey: Constants.savedY)
        )
        if defaults.integer(forKey: Constants.layoutVersion) < Constants.currentLayoutVersion {
            saved = migratedWidgetOrigin(saved, for: panel.frame.size)
            defaults.set(saved.x, forKey: Constants.savedX)
            defaults.set(saved.y, forKey: Constants.savedY)
            defaults.set(Constants.currentLayoutVersion, forKey: Constants.layoutVersion)
        }
        panel.setFrameOrigin(clampedOrigin(saved, for: panel.frame.size))
    }

    private func snapAndRememberWidget() {
        guard let panel = widgetPanel, let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var origin = panel.frame.origin

        let left = visible.minX + Constants.edgeInset
        let right = visible.maxX - panel.frame.width - Constants.edgeInset
        let bottom = visible.minY + Constants.edgeInset
        let top = visible.maxY - panel.frame.height - Constants.edgeInset

        if abs(origin.x - left) <= Constants.snapThreshold {
            origin.x = left
        } else if abs(origin.x - right) <= Constants.snapThreshold {
            origin.x = right
        }

        if abs(origin.y - bottom) <= Constants.snapThreshold {
            origin.y = bottom
        } else if abs(origin.y - top) <= Constants.snapThreshold {
            origin.y = top
        }

        origin = clampedOrigin(origin, for: panel.frame.size)
        if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
        }

        let defaults = UserDefaults.standard
        defaults.set(origin.x, forKey: Constants.savedX)
        defaults.set(origin.y, forKey: Constants.savedY)
        defaults.set(true, forKey: Constants.hasSavedPosition)
        defaults.set(Constants.currentLayoutVersion, forKey: Constants.layoutVersion)
    }

    @objc private func handleWidgetDrag(_ recognizer: WidgetWindowDragGestureRecognizer) {
        guard let panel = widgetPanel else { return }
        switch recognizer.state {
        case .began, .changed:
            let translation = recognizer.screenTranslation
            panel.setFrameOrigin(
                NSPoint(
                    x: recognizer.windowOriginAtMouseDown.x + translation.width,
                    y: recognizer.windowOriginAtMouseDown.y + translation.height
                )
            )
        case .ended:
            snapAndRememberWidget()
        default:
            break
        }
    }

    private func migratedWidgetOrigin(_ saved: NSPoint, for newSize: NSSize) -> NSPoint {
        let oldFrame = NSRect(origin: saved, size: Constants.legacyWidgetSize)
        let visible = NSScreen.screens.first(where: { $0.visibleFrame.intersects(oldFrame) })?
            .visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(origin: .zero, size: newSize)

        let leftMargin = max(saved.x - visible.minX, 0)
        let rightMargin = max(visible.maxX - oldFrame.maxX, 0)
        let bottomMargin = max(saved.y - visible.minY, 0)
        let topMargin = max(visible.maxY - oldFrame.maxY, 0)

        let x = leftMargin <= rightMargin
            ? visible.minX + leftMargin
            : visible.maxX - newSize.width - rightMargin
        let y = bottomMargin <= topMargin
            ? visible.minY + bottomMargin
            : visible.maxY - newSize.height - topMargin
        return clampedOrigin(NSPoint(x: x, y: y), for: newSize)
    }

    private func clampedOrigin(_ origin: NSPoint, for size: NSSize) -> NSPoint {
        let screens = NSScreen.screens
        let visible = screens.first(where: { $0.visibleFrame.contains(origin) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: size.width, height: size.height)

        return NSPoint(
            x: min(max(origin.x, visible.minX), visible.maxX - size.width),
            y: min(max(origin.y, visible.minY), visible.maxY - size.height)
        )
    }
}

/// Keeps the complete transparent widget surface interactive. `NSHostingView`
/// can return no hit target when SwiftUI only draws hit-testing-disabled images
/// and there are no SpriteKit bubbles, so the permanent AppKit root becomes the
/// fallback receiver for all non-control, non-bubble points.
final class WidgetEventRootView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(point) else {
            return nil
        }
        return super.hitTest(point) ?? self
    }
}

private struct ScaledWidgetRoot<Content: View>: View {
    let content: Content

    var body: some View {
        content
            .frame(
                width: WidgetMetrics.designSize.width,
                height: WidgetMetrics.designSize.height,
                alignment: .topLeading
            )
            .scaleEffect(WidgetMetrics.displayScale, anchor: .topLeading)
            .frame(
                width: WidgetMetrics.windowSize.width,
                height: WidgetMetrics.windowSize.height,
                alignment: .topLeading
            )
            .clipped()
    }
}

final class WidgetWindowDragGestureRecognizer: NSGestureRecognizer {
    var shouldRecognizeAtPoint: (NSPoint) -> Bool = { _ in true }
    private(set) var screenTranslation = CGSize.zero
    private(set) var windowOriginAtMouseDown = NSPoint.zero

    private var initialScreenLocation = NSPoint.zero

    override func mouseDown(with event: NSEvent) {
        guard let view else {
            state = .failed
            return
        }
        let location = view.convert(event.locationInWindow, from: nil)
        guard shouldRecognizeAtPoint(location) else {
            state = .failed
            return
        }

        initialScreenLocation = NSEvent.mouseLocation
        windowOriginAtMouseDown = view.window?.frame.origin ?? .zero
        screenTranslation = .zero
        state = .possible
    }

    override func mouseDragged(with event: NSEvent) {
        let location = NSEvent.mouseLocation
        screenTranslation = CGSize(
            width: location.x - initialScreenLocation.x,
            height: location.y - initialScreenLocation.y
        )
        let distance = hypot(screenTranslation.width, screenTranslation.height)
        switch state {
        case .possible where distance > WidgetMetrics.dragThreshold:
            state = .began
        case .began, .changed:
            state = .changed
        default:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch state {
        case .began, .changed:
            state = .ended
        case .possible:
            state = .failed
        default:
            break
        }
    }

    override func reset() {
        screenTranslation = .zero
        initialScreenLocation = .zero
        windowOriginAtMouseDown = .zero
        super.reset()
    }
}

private extension NSView {
    func containsIdeaBubble(at point: NSPoint) -> Bool {
        if let bubbleView = self as? BubbleInteractionSKView {
            return bubbleView.containsBubble(atViewPoint: point)
        }
        for subview in subviews {
            let localPoint = subview.convert(point, from: self)
            if subview.containsIdeaBubble(at: localPoint) {
                return true
            }
        }
        return false
    }
}

final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let windows: WindowCoordinator
    private weak var topItem: NSMenuItem?

    init(windows: WindowCoordinator) {
        self.windows = windows
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "mushroom.fill",
                accessibilityDescription: "灵感菇"
            ) ?? NSImage(
                systemSymbolName: "sparkles",
                accessibilityDescription: "灵感菇"
            )
            button.toolTip = "灵感菇"
        }

        let menu = NSMenu()
        menu.addItem(item("快速记录…", action: #selector(showQuickCapture), key: " "))
        menu.addItem(item("显示或隐藏灵感菇", action: #selector(toggleWidget)))
        menu.addItem(item("打开完整工作台", action: #selector(showWorkbench), key: "o"))
        menu.addItem(item("AI 设置…", action: #selector(showAISettings), key: ","))
        menu.addItem(item("AI 配置指南…", action: #selector(showAIConfigurationGuide)))
        if Bundle.main.bundleURL.pathExtension == "app" {
            menu.addItem(item("在访达中显示灵感菇", action: #selector(revealApplication)))
        }
        menu.addItem(.separator())

        let alwaysOnTop = item("窗口置顶", action: #selector(toggleAlwaysOnTop))
        alwaysOnTop.state = windows.isAlwaysOnTop ? .on : .off
        topItem = alwaysOnTop
        menu.addItem(alwaysOnTop)

        menu.addItem(.separator())
        menu.addItem(item("退出灵感菇", action: #selector(quit), key: "q"))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        let versionItem = NSMenuItem(title: "灵感菇 \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        statusItem.menu = menu
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if action == #selector(showQuickCapture) {
            item.keyEquivalentModifierMask = [.command, .shift]
        }
        return item
    }

    @objc private func showQuickCapture() {
        windows.showQuickCapture()
    }

    @objc private func toggleWidget() {
        windows.toggleWidget()
    }

    @objc private func showWorkbench() {
        windows.showWorkbench()
    }

    @objc private func showAISettings() {
        windows.showAISettings()
    }

    @objc private func showAIConfigurationGuide() {
        windows.showAIConfigurationGuide()
    }

    @objc private func revealApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    @objc private func toggleAlwaysOnTop() {
        let newValue = !windows.isAlwaysOnTop
        windows.setAlwaysOnTop(newValue)
        topItem?.state = newValue ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

final class GlobalShortcutMonitor {
    fileprivate let action: () -> Void
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private(set) var isRegistered = false

    init(action: @escaping () -> Void) {
        self.action = action
        var event = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            lingGanGuHotKeyHandler,
            1,
            &event,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x4C474755), id: 1)
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        isRegistered = handlerStatus == noErr && hotKeyStatus == noErr
    }

    deinit {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let handler {
            RemoveEventHandler(handler)
        }
    }
}

private func lingGanGuHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        monitor.action()
    }
    return noErr
}
