import AppKit
import Darwin
import LingGanGuCore
import SpriteKit
import SQLite3

@main
struct LingGanGuMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--ui-smoke") {
            do {
                try UIRuntimeSmokeCheck.run()
                print("LingGanGu UI smoke checks passed.")
            } catch {
                FileHandle.standardError.write(
                    Data("UI smoke check failed: \(error.localizedDescription)\n".utf8)
                )
                exit(1)
            }
            return
        }

        let application = NSApplication.shared
        let presentation: AppLaunchPresentation
        if CommandLine.arguments.contains("--show-detail") {
            presentation = .widgetDetail
        } else if CommandLine.arguments.contains("--show-capture") {
            presentation = .capture
        } else if CommandLine.arguments.contains("--show-workbench") {
            presentation = .workbench
        } else if CommandLine.arguments.contains("--show-ai-settings") {
            presentation = .aiSettings
        } else if CommandLine.arguments.contains("--show-ai-guide") {
            presentation = .aiGuide
        } else {
            presentation = .widget
        }
        let delegate = AppDelegate(presentation: presentation)
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
private enum UIRuntimeSmokeCheck {
    static func run() throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingGanGuUISmoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteIdeaRepository(
            path: directory.appendingPathComponent("ui-smoke.sqlite").path
        )
        let smokeSettingsStore = InMemoryAISettingsStore(
            settings: AISettings(
                baseURLString: "http://127.0.0.1:11434",
                model: "mock-linggangu",
                privacyConsentHost: "127.0.0.1"
            )
        )
        let state = IdeaAppState(
            repository: repository,
            automaticallyLoads: false,
            settingsStore: smokeSettingsStore,
            keyStore: InMemoryAPIKeyStore(),
            providerOverride: MockAIProvider()
        )
        let startupKeys = InMemoryAPIKeyStore()
        let startupState = IdeaAppState(repository: repository, automaticallyLoads: false,
            keyStore: startupKeys, providerOverride: MockAIProvider())
        var startupChecked = false
        Task {
            await startupKeys.setAPIKey("startup-test-only", account: AISettings.primaryKeychainAccount)
            await startupState.loadAIConfiguration()
            let startupReads = await startupKeys.secretReadCount
            precondition(startupReads == 0)
            precondition(startupState.hasStoredAPIKey)
            startupChecked = true
        }
        guard waitUntil({ startupChecked }) else { throw SmokeError.persistence }
        let seedIdeas = makeSmokeIdeas()
        var preloadError: Error?
        Task {
            do {
                for idea in seedIdeas {
                    try await repository.saveIdea(idea)
                }
                await state.loadIdeas()
                await state.loadAIState()
            } catch {
                preloadError = error
            }
        }
        guard waitUntil({
            (state.ideas.count == seedIdeas.count
                && state.aiSettings.model == "mock-linggangu")
                || preloadError != nil
        }),
              preloadError == nil else {
            throw preloadError ?? SmokeError.persistence
        }
        let initialCount = state.activeIdeas.count
        let windows = WindowCoordinator(appState: state)

        windows.showWidget()
        guard let widget = windows.widgetPanel,
              widget.isVisible,
              widget.frame.size == WidgetMetrics.windowSize,
              widget.level == (windows.isAlwaysOnTop ? .floating : .normal) else {
            throw SmokeError.widget
        }
        widget.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        guard let spriteView = widget.contentView?.firstDescendant(of: SKView.self),
              let physicsScene = spriteView.scene as? BubblePhysicsScene else {
            throw SmokeError.physicsBoundary
        }
        guard
              spriteView is BubbleInteractionSKView,
              spriteView.mouseDownCanMoveWindow == false,
              !widget.isMovableByWindowBackground else {
            throw SmokeError.physicsWindowIsolation
        }
        guard let bubbleScenePoint = physicsScene.debugFirstBubblePosition() else {
            throw SmokeError.physicsWindowIsolation
        }
        let bubbleViewPoint = physicsScene.convertPoint(toView: bubbleScenePoint)
        let emptyViewPoint = physicsScene.convertPoint(
            toView: CGPoint(x: physicsScene.size.width / 2, y: physicsScene.size.height - 2)
        )
        guard spriteView.hitTest(bubbleViewPoint) === spriteView,
              spriteView.hitTest(emptyViewPoint) == nil else {
            throw SmokeError.physicsWindowIsolation
        }
        let bubblePointInContent = spriteView.convert(
            bubbleViewPoint,
            to: widget.contentView
        )
        guard !windows.debugWindowDragAllowed(at: bubblePointInContent) else {
            throw SmokeError.physicsWindowIsolation
        }
        let nonBubbleSamples = [
            NSPoint(x: 4, y: 4),
            NSPoint(x: widget.frame.width - 4, y: 4),
            NSPoint(x: widget.frame.width / 2, y: widget.frame.height - 4),
            NSPoint(x: widget.frame.width / 2, y: 26)
        ]
        guard nonBubbleSamples.allSatisfy(windows.debugWindowDragAllowed(at:)) else {
            throw SmokeError.windowDragCoverage
        }
        guard
              physicsScene.debugBubbleCount == state.recentIdeas.count,
              abs(
                physicsScene.debugBubbleDiameter * WidgetMetrics.displayScale - 20
              ) < 0.01,
              physicsScene.usesReferenceCapBoundary,
              physicsScene.debugUsesPhysicalVolumeAndBounce(),
              physicsScene.debugAllBubblesInsideBoundary() else {
            throw SmokeError.physicsBoundary
        }
        let velocityBeforeWindowMove = physicsScene.debugMeanVelocity()
        let originalWidgetOrigin = widget.frame.origin
        widget.setFrameOrigin(
            NSPoint(x: originalWidgetOrigin.x - 12, y: originalWidgetOrigin.y)
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        let velocityAfterWindowMove = physicsScene.debugMeanVelocity()
        widget.setFrameOrigin(originalWidgetOrigin)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        guard velocityAfterWindowMove.dx > velocityBeforeWindowMove.dx + 20 else {
            throw SmokeError.physicsWindowInertia
        }
        let initialBubbleCount = physicsScene.debugBubbleCount
        guard let selectedBubbleID = physicsScene.debugSelectFirstBubble() else {
            throw SmokeError.physicsSelection
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        guard state.bubbleDetailIdeaID == selectedBubbleID,
              physicsScene.debugIsPinned(selectedBubbleID) else {
            throw SmokeError.physicsSelection
        }
        guard windows.bubbleDetailPanel?.isVisible == true,
              windows.bubbleDetailPanel?.frame.size == NSSize(width: 320, height: 240) else {
            throw SmokeError.bubbleDetailPanel
        }
        guard physicsScene.debugSelectFirstBubble() == selectedBubbleID else {
            throw SmokeError.physicsDetailToggle
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        guard state.bubbleDetailIdeaID == nil,
              !physicsScene.debugIsPinned(selectedBubbleID),
              windows.bubbleDetailPanel?.isVisible != true else {
            throw SmokeError.physicsDetailToggle
        }
        guard physicsScene.debugSelectFirstBubble() == selectedBubbleID else {
            throw SmokeError.physicsDetailToggle
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        guard state.bubbleDetailIdeaID == selectedBubbleID,
              physicsScene.debugIsPinned(selectedBubbleID),
              windows.bubbleDetailPanel?.isVisible == true else {
            throw SmokeError.physicsDetailToggle
        }
        Task { await state.startCompletingBubbleIdea(selectedBubbleID) }
        _ = waitUntil({ state.ideas.first(where: { $0.id == selectedBubbleID })?.status == .testing })
        guard physicsScene.debugIsHighlighted(selectedBubbleID) else {
            throw SmokeError.physicsHighlight
        }
        Task { await state.startCompletingBubbleIdea(selectedBubbleID) }
        _ = waitUntil({
            state.ideas.first(where: { $0.id == selectedBubbleID })?.status == .inbox
        })
        guard !physicsScene.debugIsHighlighted(selectedBubbleID) else {
            throw SmokeError.physicsHighlightToggle
        }
        Task { await state.startCompletingBubbleIdea(selectedBubbleID) }
        _ = waitUntil({
            state.ideas.first(where: { $0.id == selectedBubbleID })?.status == .testing
        })
        guard physicsScene.debugIsHighlighted(selectedBubbleID) else {
            throw SmokeError.physicsHighlightToggle
        }
        guard physicsScene.debugUsesSolidBubbleRendering(selectedBubbleID) else {
            throw SmokeError.physicsRenderingArtifact
        }
        guard physicsScene.debugReleasePinnedBubbleOutsideBoundary() == selectedBubbleID else {
            throw SmokeError.physicsDrag
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        guard state.bubbleDetailIdeaID == nil,
              physicsScene.debugAllBubblesInsideBoundary() else {
            throw SmokeError.physicsDrag
        }
        Task { await state.completeBubbleIdea(selectedBubbleID) }
        _ = waitUntil({ physicsScene.debugBubbleCount == initialBubbleCount - 1 })
        guard physicsScene.debugBubbleCount == initialBubbleCount - 1 else {
            throw SmokeError.physicsRemoval
        }

        windows.showQuickCapture()
        guard let capture = windows.capturePanel,
              capture.isVisible,
              capture.frame.size == NSSize(width: 520, height: 180),
              capture.canBecomeKey else {
            throw SmokeError.capture
        }

        capture.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        guard let textView = capture.contentView?.firstDescendant(of: NSTextView.self) else {
            throw SmokeError.editor
        }
        textView.insertText(
            "UI smoke check idea #smoke",
            replacementRange: NSRange(location: 0, length: 0)
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let enterHandled = textView.delegate?.textView?(
            textView,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ) ?? false
        _ = waitUntil({ !capture.isVisible && state.activeIdeas.count == initialCount + 1 })
        guard enterHandled,
              !capture.isVisible,
              state.activeIdeas.count == initialCount + 1,
              state.selectedIdea?.rawText == "UI smoke check idea #smoke",
              state.selectedIdea?.tags == ["smoke"] else {
            throw SmokeError.save
        }
        let capturedID = try unwrap(state.selectedIdea?.id, or: SmokeError.persistence)
        Task {
            _ = await state.updateIdea(
                id: capturedID,
                rawText: "修改后的中文\n多行正文 #不会重新提取",
                tags: []
            )
        }
        guard waitUntil({
            state.ideas.first(where: { $0.id == capturedID })?.rawText
                == "修改后的中文\n多行正文 #不会重新提取"
                && state.ideas.first(where: { $0.id == capturedID })?.tags == []
        }) else {
            throw SmokeError.persistence
        }
        Task { _ = await state.setStatus(.archived, for: capturedID) }
        guard waitUntil({
            state.ideas.first(where: { $0.id == capturedID })?.status == .archived
        }) else {
            throw SmokeError.persistence
        }
        Task { _ = await state.restoreArchivedIdea(capturedID) }
        guard waitUntil({
            state.ideas.first(where: { $0.id == capturedID })?.status == .inbox
        }) else {
            throw SmokeError.persistence
        }

        let reloadedState = IdeaAppState(repository: repository, automaticallyLoads: false)
        Task { await reloadedState.loadIdeas() }
        guard waitUntil({
            reloadedState.ideas.first(where: { $0.id == capturedID })?.tags == []
                && reloadedState.ideas.first(where: { $0.id == capturedID })?.status == .inbox
        }) else {
            throw SmokeError.persistence
        }

        state.select(
            try unwrap(
                state.ideas.first(where: { $0.id == capturedID }),
                or: SmokeError.aiAnnotation
            )
        )
        state.requestAnnotation(for: capturedID)
        guard waitUntil({
            state.ideas.first(where: { $0.id == capturedID })?.aiAnnotatedAt != nil
        }),
        let annotatedIdea = state.ideas.first(where: { $0.id == capturedID }),
        annotatedIdea.aiAnnotationModel == "mock-linggangu",
        annotatedIdea.aiSuggestedTags == ["待整理"] else {
            throw SmokeError.aiAnnotation
        }
        Task {
            await state.applySuggestedTags(["待整理"], to: capturedID)
        }
        guard waitUntil({
            state.ideas.first(where: { $0.id == capturedID })?.tags.contains("待整理") == true
        }) else {
            throw SmokeError.aiAnnotation
        }

        let annotationDateBeforeArchive = annotatedIdea.aiAnnotatedAt
        Task { _ = await state.setStatus(.archived, for: capturedID) }
        guard waitUntil({
            state.ideas.first(where: { $0.id == capturedID })?.status == .archived
        }) else {
            throw SmokeError.archivedManualAIAnnotation
        }
        state.requestAnnotation(for: capturedID)
        guard waitUntil({
            guard let current = state.ideas.first(where: { $0.id == capturedID }) else {
                return false
            }
            return current.status == .archived
                && current.aiAnnotatedAt != annotationDateBeforeArchive
                && current.rawText == "修改后的中文\n多行正文 #不会重新提取"
                && current.tags.contains("待整理")
        }) else {
            throw SmokeError.archivedManualAIAnnotation
        }
        Task { _ = await state.restoreArchivedIdea(capturedID) }
        guard waitUntil({
            state.ideas.first(where: { $0.id == capturedID })?.status == .inbox
        }) else {
            throw SmokeError.archivedManualAIAnnotation
        }

        state.aiScopeKind = .current
        state.requestSummary()
        guard waitUntil({ !state.isSummarizing && state.selectedSummary != nil }),
              state.selectedSummary?.sourceIdeaIDs == [capturedID] else {
            throw SmokeError.aiSummary
        }

        state.insightMode = .chat
        state.startNewConversation()
        state.chatDraft = "如何做最小验证？"
        state.sendChat()
        guard waitUntil({
            !state.isStreamingChat
                && state.selectedConversation?.messages.contains(where: {
                    $0.role == .assistant && $0.deliveryState == .complete
                }) == true
        }) else {
            throw SmokeError.aiChat
        }
        guard state.selectedConversation?.messages.last?.sourceIdeaIDs == [capturedID] else {
            throw SmokeError.aiChat
        }

        state.startNewConversation()
        state.chatDraft = "停止这个回复"
        state.sendChat()
        guard waitUntil({ state.isStreamingChat && !state.streamingChatText.isEmpty }) else {
            throw SmokeError.aiChatStop
        }
        state.stopChat()
        guard waitUntil({
            !state.isStreamingChat
                && state.selectedConversation?.messages.last?.deliveryState == .stopped
        }) else {
            throw SmokeError.aiChatStop
        }

        // A running response must remain attached to its original conversation.
        state.chatDraft = "会话锁定检查"
        state.sendChat()
        guard waitUntil({ state.isStreamingChat && !state.streamingChatText.isEmpty }) else {
            throw SmokeError.aiChat
        }
        let lockedID = state.selectedConversationID
        state.startNewConversation()
        state.prepareAIDiscussion(for: capturedID)
        guard state.selectedConversationID == lockedID else { throw SmokeError.aiChat }
        state.stopChat()
        guard waitUntil({ !state.isStreamingChat }) else { throw SmokeError.aiChatStop }

        let isolatedKeys = InMemoryAPIKeyStore()
        let isolatedSettings = InMemoryAISettingsStore(settings: AISettings(
            baseURLString: "https://old.example", model: "mock"))
        let settingsState = IdeaAppState(repository: repository, automaticallyLoads: false,
            settingsStore: isolatedSettings, keyStore: isolatedKeys)
        var checkedCredentials = false
        Task {
            await isolatedKeys.setAPIKey("old-test-key", account: AISettings.primaryKeychainAccount)
            await settingsState.loadAIConfiguration()
            let blocked = await settingsState.saveAISettings(
                AISettings(baseURLString: "https://new.example", model: "mock"),
                apiKey: "", backfillChoice: .futureOnly)
            precondition(!blocked && settingsState.aiSettings.normalizedHost == "old.example")
            let saved = await settingsState.saveAISettings(
                AISettings(baseURLString: "https://new.example", model: "mock"),
                apiKey: "new-test-key", backfillChoice: .futureOnly)
            let stored = await isolatedKeys.apiKey(account: AISettings.primaryKeychainAccount)
            precondition(saved && stored == "new-test-key")
            checkedCredentials = true
        }
        guard waitUntil({ checkedCredentials }) else { throw SmokeError.aiChat }

        let delayedState = IdeaAppState(repository: repository, automaticallyLoads: false,
            settingsStore: smokeSettingsStore, keyStore: InMemoryAPIKeyStore(),
            providerOverride: MockAIProvider(simulatedDelay: .milliseconds(100)))
        var delayedLoaded = false
        Task {
            await delayedState.loadIdeas()
            delayedState.selectedIdeaID = capturedID
            delayedState.aiScopeKind = .current
            delayedLoaded = true
        }
        guard waitUntil({ delayedLoaded }) else { throw SmokeError.persistence }
        delayedState.requestAnnotation(for: capturedID)
        delayedState.cancelAnnotationBatch()
        delayedState.requestAnnotation(for: capturedID)
        guard waitUntil({ !delayedState.isAnnotating }) else { throw SmokeError.aiChat }
        delayedState.requestAnnotation(for: capturedID)
        guard waitUntil({ !delayedState.isAnnotating && delayedState.annotationCompletedCount == 1 }) else {
            throw SmokeError.aiChat
        }
        delayedState.requestSummary()
        delayedState.cancelSummary()
        delayedState.requestSummary()
        guard waitUntil({ !delayedState.isSummarizing }) else { throw SmokeError.aiSummary }
        delayedState.requestSummary()
        guard waitUntil({ !delayedState.isSummarizing && delayedState.selectedSummary != nil }) else {
            throw SmokeError.aiSummary
        }

        // Simulate disk failure after the user message is saved but before the reply is saved.
        state.startNewConversation()
        state.chatDraft = "保存失败必须保留的回复"
        state.sendChat()
        guard waitUntil({ state.isStreamingChat && !state.streamingChatText.isEmpty }) else {
            throw SmokeError.aiChat
        }
        var failureDB: OpaquePointer?
        guard sqlite3_open(directory.appendingPathComponent("ui-smoke.sqlite").path, &failureDB) == SQLITE_OK else {
            throw SmokeError.persistence
        }
        defer { sqlite3_close(failureDB) }
        let failureSQL = "CREATE TRIGGER fail_reply BEFORE INSERT ON conversations BEGIN SELECT RAISE(ABORT, 'test save failure'); END;"
        guard sqlite3_exec(failureDB, failureSQL, nil, nil, nil) == SQLITE_OK else { throw SmokeError.persistence }
        guard waitUntil({ !state.isStreamingChat }), state.hasUnsavedReply,
              !state.streamingChatText.isEmpty, !state.chatDraft.isEmpty else { throw SmokeError.aiChat }
        guard sqlite3_exec(failureDB, "DROP TRIGGER fail_reply", nil, nil, nil) == SQLITE_OK else { throw SmokeError.persistence }
        state.sendChat()
        guard waitUntil({ !state.isStreamingChat && !state.hasUnsavedReply }),
              state.selectedConversation?.messages.filter({ $0.role == .user }).count == 1,
              state.selectedConversation?.messages.filter({ $0.role == .assistant }).count == 1 else {
            throw SmokeError.aiChat
        }

        // The native investment agent is opt-in, read-only and persists every version.
        state.selectedIdeaID = capturedID
        state.aiScopeKind = .current
        let sourceBeforeEvaluation = state.selectedIdea
        state.requestInvestmentReview()
        guard waitUntil({ !state.isEvaluating && state.currentEvaluationHistory.count == 1 }),
              state.selectedIdea == sourceBeforeEvaluation,
              state.selectedEvaluation?.sourceRawText == sourceBeforeEvaluation?.rawText,
              state.selectedEvaluation?.opposingArguments?.isEmpty == false,
              state.investmentCandidates.contains(where: { $0.ideaID == capturedID }) else {
            throw SmokeError.persistence
        }
        state.requestInvestmentReview()
        guard waitUntil({ !state.isEvaluating && state.currentEvaluationHistory.count == 2 }) else {
            throw SmokeError.persistence
        }
        let evaluationCount = state.evaluations.count
        guard sqlite3_exec(failureDB, "CREATE TRIGGER fail_evaluation BEFORE INSERT ON evaluations BEGIN SELECT RAISE(ABORT, 'test evaluation save failure'); END;", nil, nil, nil) == SQLITE_OK else { throw SmokeError.persistence }
        state.requestInvestmentReview()
        guard waitUntil({ !state.isEvaluating }), state.evaluations.count == evaluationCount,
              state.evaluationFailures[capturedID] != nil, state.selectedIdea == sourceBeforeEvaluation else {
            throw SmokeError.persistence
        }
        guard sqlite3_exec(failureDB, "DROP TRIGGER fail_evaluation", nil, nil, nil) == SQLITE_OK else { throw SmokeError.persistence }
        delayedState.requestInvestmentReview()
        delayedState.cancelInvestmentReview()
        guard waitUntil({ !delayedState.isEvaluating }), delayedState.evaluations.isEmpty else { throw SmokeError.persistence }
        var evaluationsReloaded = false
        Task {
            await reloadedState.loadAIState()
            evaluationsReloaded = true
        }
        guard waitUntil({ evaluationsReloaded }),
              reloadedState.evaluations.filter({ $0.ideaID == capturedID }).count == 2 else { throw SmokeError.persistence }
        // A saved report opens a persistent discussion without a network request.
        guard let report = state.selectedEvaluation else { throw SmokeError.persistence }
        state.chatDraft = ""
        var discussionOpened = false
        Task {
            await state.discussEvaluation(report)
            discussionOpened = true
        }
        guard waitUntil({ discussionOpened }),
              let discussion = state.selectedConversation,
              discussion.evaluationID == report.id,
              discussion.messages.count == 1,
              discussion.messages[0].content.contains(report.smallestExperiment),
              report.markdownReport.contains(report.sourceRawText ?? "missing") else { throw SmokeError.persistence }
        state.chatDraft = "请讨论报告中的最小实验，如何降低验证成本？"
        state.sendChat()
        guard waitUntil({ !state.isStreamingChat && state.selectedConversation?.messages.count == 3 }),
              state.selectedConversation?.messages.first == discussion.messages.first else { throw SmokeError.persistence }
        let savedDiscussionID = state.selectedConversationID
        discussionOpened = false
        Task {
            await reloadedState.loadAIState()
            await state.discussEvaluation(report)
            discussionOpened = true
        }
        guard waitUntil({ discussionOpened }), state.selectedConversationID == savedDiscussionID,
              reloadedState.conversations.first(where: { $0.id == savedDiscussionID })?.evaluationID == report.id,
              reloadedState.conversations.first(where: { $0.id == savedDiscussionID })?.messages.count == 3 else { throw SmokeError.persistence }
        // Legacy conversations decode without the new optional association.
        let legacyData = try JSONEncoder().encode(Conversation(title: "旧对话", scopeIdeaIDs: [], model: "mock"))
        guard try JSONDecoder().decode(Conversation.self, from: legacyData).evaluationID == nil else { throw SmokeError.persistence }
        state.insightMode = .investment

        // Five workflow filters preserve legacy raw states and include archives in All.
        guard IdeaStatus.workflowCases.count == 5,
              !IdeaStatus.workflowCases.contains(.clarified),
              IdeaStatus.clarified.workflowStatus == .inbox else { throw SmokeError.persistence }
        state.selectedStatus = nil
        state.searchText = ""
        guard state.visibleIdeas.count == state.ideas.count else { throw SmokeError.persistence }
        for status in IdeaStatus.workflowCases {
            state.selectedStatus = status
            guard state.visibleIdeas.count == state.count(for: status),
                  state.visibleIdeas.allSatisfy({ $0.status.workflowStatus == status }) else { throw SmokeError.persistence }
            if state.visibleIdeas.isEmpty {
                guard state.selectedIdea == nil else { throw SmokeError.persistence }
            } else {
                guard state.selectedIdea?.id == state.selectedIdeaID else { throw SmokeError.persistence }
            }
        }
        state.searchText = "no-matching-idea-\(UUID())"
        guard state.visibleIdeas.isEmpty, state.selectedIdea == nil else { throw SmokeError.persistence }
        state.revealIdea(capturedID)
        guard state.selectedIdea?.id == capturedID, state.selectedStatus == nil,
              state.searchText.isEmpty else { throw SmokeError.persistence }

        var jsonExport: Data?
        var markdownExport: Data?
        var exportError: Error?
        Task {
            do {
                jsonExport = try await state.exportData(.json)
                markdownExport = try await state.exportData(.markdown)
            } catch {
                exportError = error
            }
        }
        guard waitUntil({
            (jsonExport != nil && markdownExport != nil) || exportError != nil
        }),
        exportError == nil,
        let jsonExport,
        let markdownExport else {
            throw exportError ?? SmokeError.export
        }
        let jsonText = String(decoding: jsonExport, as: UTF8.self).lowercased()
        let markdownText = String(decoding: markdownExport, as: UTF8.self)
        guard jsonText.contains(capturedID.uuidString.lowercased()),
              markdownText.contains(capturedID.uuidString),
              !jsonText.contains("apikey"),
              !jsonText.contains("authorization") else {
            throw SmokeError.export
        }

        windows.showQuickCapture()
        capture.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        guard let reopenedEditor = capture.contentView?.firstDescendant(of: NSTextView.self),
              reopenedEditor.delegate?.textView?(
                reopenedEditor,
                doCommandBy: #selector(NSResponder.cancelOperation(_:))
              ) == true,
              !capture.isVisible else {
            throw SmokeError.cancel
        }

        let unavailableState = IdeaAppState(
            repository: nil,
            startupError: "测试：数据库不可用"
        )
        let unavailableWindows = WindowCoordinator(appState: unavailableState)
        unavailableWindows.showQuickCapture()
        guard let unavailableCapture = unavailableWindows.capturePanel else {
            throw SmokeError.persistenceFailureSafety
        }
        unavailableCapture.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        guard let unavailableEditor = unavailableCapture.contentView?
            .firstDescendant(of: NSTextView.self) else {
            throw SmokeError.persistenceFailureSafety
        }
        unavailableEditor.insertText(
            "数据库失败时必须保留的草稿",
            replacementRange: NSRange(location: 0, length: 0)
        )
        let unavailableEnterHandled = unavailableEditor.delegate?.textView?(
            unavailableEditor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ) ?? false
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        guard unavailableEnterHandled,
              unavailableCapture.isVisible,
              unavailableEditor.string == "数据库失败时必须保留的草稿",
              unavailableState.ideas.isEmpty else {
            throw SmokeError.persistenceFailureSafety
        }
        unavailableCapture.orderOut(nil)

        let emptyState = IdeaAppState(repository: nil)
        let emptyWindows = WindowCoordinator(appState: emptyState)
        emptyWindows.showWidget()
        guard let emptyWidget = emptyWindows.widgetPanel,
              let emptyContentView = emptyWidget.contentView else {
            throw SmokeError.emptyWidgetDrag
        }
        emptyContentView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let emptyDragSamples = [
            NSPoint(x: 18, y: emptyWidget.frame.height - 28),
            NSPoint(x: emptyWidget.frame.width / 2, y: emptyWidget.frame.height - 52),
            NSPoint(x: emptyWidget.frame.width - 18, y: emptyWidget.frame.height / 2),
            NSPoint(x: emptyWidget.frame.width / 2, y: 82)
        ]
        guard emptyDragSamples.allSatisfy({
            emptyContentView.hitTest($0) != nil
                && emptyWindows.debugWindowDragAllowed(at: $0)
        }) else {
            throw SmokeError.emptyWidgetDrag
        }
        emptyWidget.orderOut(nil)

        windows.showWorkbench()
        guard let workbench = windows.workbenchWindow,
              workbench.isVisible,
              workbench.contentView?.frame.size == NSSize(width: 1040, height: 720) else {
            throw SmokeError.workbench
        }
        if CommandLine.arguments.contains("--qa-investment"), let view = workbench.contentView {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(
                    to: URL(fileURLWithPath: "/private/tmp/linggangu-investment-qa.png"), options: .atomic)
            }
        }
        windows.showAISettings()
        guard let aiSettings = windows.aiSettingsWindow,
              aiSettings.isVisible,
              aiSettings.contentView?.frame.size == NSSize(width: 520, height: 500) else {
            throw SmokeError.aiSettings
        }
        windows.showAIConfigurationGuide()
        guard let aiGuide = windows.aiGuideWindow,
              aiGuide.isVisible,
              aiGuide.contentView?.frame.size == NSSize(width: 640, height: 620) else {
            throw SmokeError.aiGuide
        }

        let shortcut = GlobalShortcutMonitor {}
        guard shortcut.isRegistered else {
            throw SmokeError.shortcut
        }

        guard !QuickCaptureExitPolicy.hasUnsavedContent(
            text: " \n",
            manualTags: " "
        ),
        QuickCaptureExitPolicy.hasUnsavedContent(
            text: "未保存正文",
            manualTags: ""
        ),
        QuickCaptureExitPolicy.hasUnsavedContent(
            text: "",
            manualTags: "#仅有标签"
        ) else {
            throw SmokeError.captureExitGuard
        }

        let privacyState = IdeaAppState(
            repository: nil,
            settingsStore: InMemoryAISettingsStore(
                settings: AISettings(
                    baseURLString: "https://example.com",
                    model: "privacy-test"
                )
            ),
            keyStore: InMemoryAPIKeyStore()
        )
        guard waitUntil({ privacyState.aiSettings.model == "privacy-test" }) else {
            throw SmokeError.aiPrivacy
        }
        privacyState.requestAnnotation(for: UUID())
        guard privacyState.pendingPrivacyAction != nil,
              privacyState.privacyPromptText.contains("example.com") else {
            throw SmokeError.aiPrivacy
        }
        privacyState.cancelPrivacyConfirmation()

        let guardedExitState = IdeaAppState(repository: nil)
        let guardedExitWindows = WindowCoordinator(appState: guardedExitState)
        guardedExitWindows.showQuickCapture()
        guard let guardedCapture = guardedExitWindows.capturePanel else {
            throw SmokeError.captureExitGuard
        }
        guardedCapture.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        guard let guardedEditor = guardedCapture.contentView?
            .firstDescendant(of: NSTextView.self) else {
            throw SmokeError.captureExitGuard
        }
        guardedEditor.insertText(
            "退出前需要确认",
            replacementRange: NSRange(location: 0, length: 0)
        )
        let guardedEscapeHandled = guardedEditor.delegate?.textView?(
            guardedEditor,
            doCommandBy: #selector(NSResponder.cancelOperation(_:))
        ) ?? false
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        guard guardedEscapeHandled,
              guardedCapture.isVisible,
              guardedEditor.string == "退出前需要确认" else {
            throw SmokeError.captureExitGuard
        }
        guardedCapture.orderOut(nil)

        widget.orderOut(nil)
        capture.orderOut(nil)
        workbench.orderOut(nil)
        aiSettings.orderOut(nil)
        aiGuide.orderOut(nil)
    }

    private static func makeSmokeIdeas() -> [Idea] {
        [
            Idea(
                rawText: "做一个能筛选想法的 Agent",
                status: .candidate,
                source: .widget,
                tags: ["agent", "产品"]
            ),
            Idea(
                rawText: "把每天零散记录自动合并成主题脉络",
                status: .clarified,
                source: .widget,
                tags: ["AI", "整理"]
            ),
            Idea(
                rawText: "测试用户是否愿意为私人灵感分析付费",
                status: .testing,
                source: .widget,
                tags: ["商业", "验证"]
            )
        ]
    }

    @discardableResult
    private static func waitUntil(
        _ condition: @escaping () -> Bool,
        timeout: TimeInterval = 2
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    private static func unwrap<T>(_ value: T?, or error: Error) throws -> T {
        guard let value else { throw error }
        return value
    }

    private enum SmokeError: LocalizedError {
        case widget
        case physicsBoundary
        case physicsWindowIsolation
        case windowDragCoverage
        case physicsWindowInertia
        case physicsSelection
        case physicsDetailToggle
        case bubbleDetailPanel
        case physicsHighlight
        case physicsHighlightToggle
        case physicsRenderingArtifact
        case physicsDrag
        case physicsRemoval
        case capture
        case editor
        case save
        case cancel
        case workbench
        case shortcut
        case persistence
        case export
        case persistenceFailureSafety
        case emptyWidgetDrag
        case captureExitGuard
        case aiSettings
        case aiGuide
        case aiAnnotation
        case archivedManualAIAnnotation
        case aiSummary
        case aiChat
        case aiChatStop
        case aiPrivacy

        var errorDescription: String? {
            switch self {
            case .widget: "悬浮组件窗口状态或尺寸不正确"
            case .physicsBoundary: "气泡物理场未加载或有气泡越过蘑菇帽边界"
            case .physicsWindowIsolation: "气泡和透明空白没有正确分配拖动行为"
            case .windowDragCoverage: "非球体区域没有全部交给窗口拖动识别器"
            case .physicsWindowInertia: "移动蘑菇窗口时气泡没有产生惯性响应"
            case .physicsSelection: "点击气泡后没有固定并显示对应灵感"
            case .physicsDetailToggle: "再次点击同一气泡没有关闭详情并释放气泡"
            case .bubbleDetailPanel: "放大的 320 × 240 灵感详情面板未显示"
            case .physicsHighlight: "正在完成的气泡没有进入高亮状态"
            case .physicsHighlightToggle: "再次点击正在完成后没有取消或重新恢复高亮"
            case .physicsRenderingArtifact: "气泡仍带有外部光晕、子图层或拖影来源"
            case .physicsDrag: "拖动释放后气泡没有回到物理场内"
            case .physicsRemoval: "完成灵感后对应气泡没有移除"
            case .capture: "快速输入窗口状态或尺寸不正确"
            case .editor: "快速输入编辑器未加载"
            case .save: "快速记录状态更新失败"
            case .cancel: "Esc 取消快速输入失败"
            case .workbench: "完整工作台状态或尺寸不正确"
            case .shortcut: "⌘⇧Space 全局快捷键注册失败"
            case .persistence: "UI smoke 的 SQLite 状态接线失败"
            case .export: "Markdown 或 JSON 导出检查失败"
            case .persistenceFailureSafety: "数据库失败时输入窗口关闭或草稿丢失"
            case .emptyWidgetDrag: "零气泡状态下透明蘑菇区域无法接收窗口拖动"
            case .captureExitGuard: "快速记录退出按钮未正确区分空白与未保存草稿"
            case .aiSettings: "AI 设置窗口状态或尺寸不正确"
            case .aiGuide: "AI 配置指南窗口状态或尺寸不正确"
            case .aiAnnotation: "AI 标题、主题或标签建议没有安全持久化"
            case .archivedManualAIAnnotation: "归档灵感的单条手动 AI 整理失败"
            case .aiSummary: "阶段总结没有生成、引用或持久化"
            case .aiChat: "AI 对话没有流式生成、引用或持久化"
            case .aiChatStop: "停止流式回复后没有保存部分内容"
            case .aiPrivacy: "首次发送前没有显示服务域名和发送范围确认"
            }
        }
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        if let match = self as? T {
            return match
        }
        for subview in subviews {
            if let match = subview.firstDescendant(of: type) {
                return match
            }
        }
        return nil
    }
}
