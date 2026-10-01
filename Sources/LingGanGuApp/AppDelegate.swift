import AppKit
import LingGanGuCore

enum AppLaunchPresentation {
    case widget
    case widgetDetail
    case capture
    case workbench
    case aiSettings
    case aiGuide
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState: IdeaAppState
    private let presentation: AppLaunchPresentation
    private var windows: WindowCoordinator?
    private var statusItem: StatusItemController?
    private var shortcut: GlobalShortcutMonitor?

    init(presentation: AppLaunchPresentation = .widget) {
        self.presentation = presentation
        let settingsStore = UserDefaultsAISettingsStore()
        let keyStore = KeychainAPIKeyStore()
        do {
            appState = IdeaAppState(
                repository: try DatabaseBootstrapper.openDefaultRepository(),
                settingsStore: settingsStore,
                keyStore: keyStore
            )
        } catch {
            appState = IdeaAppState(
                repository: nil,
                startupError: "本地数据库无法打开，已停止写入：\(error.localizedDescription)",
                settingsStore: settingsStore,
                keyStore: keyStore
            )
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let windows = WindowCoordinator(appState: appState)
        self.windows = windows
        statusItem = StatusItemController(windows: windows)
        shortcut = GlobalShortcutMonitor { [weak windows] in
            windows?.showQuickCapture()
        }
        switch presentation {
        case .widget:
            windows.showWidget()
        case .widgetDetail:
            windows.showWidget()
            Task { [weak self] in
                guard let self else { return }
                while self.appState.isLoading {
                    try? await Task.sleep(for: .milliseconds(20))
                }
                guard let idea = self.appState.recentIdeas.first else { return }
                self.appState.showBubbleDetail(idea)
            }
        case .capture:
            windows.showQuickCapture()
        case .workbench:
            windows.showWorkbench()
        case .aiSettings:
            windows.showAISettings()
        case .aiGuide:
            windows.showAIConfigurationGuide()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
