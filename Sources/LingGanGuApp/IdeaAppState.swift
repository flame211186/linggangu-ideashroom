import Combine
import Foundation
import LingGanGuCore

struct QuickCaptureDraft: Equatable {
    var rawText: String
    var manualTagText: String
}

enum IdeaExportFormat {
    case markdown
    case json

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .json: "json"
        }
    }

    var displayName: String {
        switch self {
        case .markdown: "Markdown"
        case .json: "JSON"
        }
    }
}

@MainActor
final class IdeaAppState: ObservableObject {
    @Published private(set) var ideas: [Idea] = []
    @Published var selectedIdeaID: UUID?
    @Published var bubbleDetailIdeaID: UUID?
    @Published var searchText = "" { didSet { normalizeSelection() } }
    @Published var selectedStatus: IdeaStatus? { didSet { normalizeSelection() } }
    @Published var insightMode: InsightMode = .summary
    @Published var activityMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var persistenceError: String?
    @Published private(set) var aiSettings = AISettings()
    @Published private(set) var hasStoredAPIKey = false
    @Published private(set) var keychainStatusUnavailable = false
    @Published private(set) var isTestingAIConnection = false
    @Published private(set) var isSummarizing = false
    @Published private(set) var isStreamingChat = false
    @Published private(set) var chatCanRetry = false
    @Published private(set) var isAnnotating = false
    @Published private(set) var annotationCompletedCount = 0
    @Published private(set) var annotationTotalCount = 0
    @Published private(set) var annotationFailureCount = 0
    @Published private(set) var summaries: [Summary] = []
    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var evaluations: [Evaluation] = []
    @Published var selectedEvaluationID: UUID?
    @Published private(set) var isEvaluating = false
    @Published private(set) var evaluationCompletedCount = 0
    @Published private(set) var evaluationTotalCount = 0
    @Published private(set) var evaluationFailures: [UUID: String] = [:]
    private var evaluationTask: Task<Void, Never>?
    @Published var selectedSummaryID: UUID?
    @Published var selectedConversationID: UUID?
    @Published var aiError: String?
    @Published var chatDraft = ""
    @Published private(set) var streamingChatText = ""
    @Published var aiScopeKind: AIScopeKind = .current
    @Published var aiSelectedIdeaIDs = Set<UUID>()
    @Published var aiCustomStartDate = Calendar.current.startOfDay(for: Date())
    @Published var aiCustomEndDate = Date()
    @Published var aiSelectedTag = ""
    @Published var aiSelectedTopic = ""
    @Published private(set) var pendingPrivacyAction: PendingAIAction?

    private let repository: (any IdeaRepository)?
    private let settingsStore: any AISettingsStoring
    private let keyStore: any APIKeyStoring
    private let providerFactory: AIProviderFactory
    private let providerOverride: (any AIProvider)?
    private var annotationQueue: [UUID] = []
    private var annotationTask: Task<Void, Never>?
    private var summaryTask: Task<Void, Never>?
    private var chatTask: Task<Void, Never>?
    private var chatStopRequested = false
    private var unsavedConversation: Conversation?
    var canSwitchConversation: Bool { !isStreamingChat && unsavedConversation == nil }
    var hasUnsavedReply: Bool { unsavedConversation != nil }

    init(
        repository: (any IdeaRepository)?,
        startupError: String? = nil,
        automaticallyLoads: Bool = true,
        settingsStore: (any AISettingsStoring)? = nil,
        keyStore: (any APIKeyStoring)? = nil,
        providerOverride: (any AIProvider)? = nil
    ) {
        let resolvedSettingsStore = settingsStore ?? InMemoryAISettingsStore()
        let resolvedKeyStore = keyStore ?? InMemoryAPIKeyStore()
        self.repository = repository
        self.settingsStore = resolvedSettingsStore
        self.keyStore = resolvedKeyStore
        self.providerFactory = AIProviderFactory(
            settingsStore: resolvedSettingsStore,
            keyStore: resolvedKeyStore
        )
        self.providerOverride = providerOverride
        persistenceError = startupError

        if repository != nil, automaticallyLoads {
            isLoading = true
            Task {
                await loadIdeas()
                await loadAIState()
            }
        } else {
            Task { await loadAIConfiguration() }
        }
    }

    enum InsightMode: String, CaseIterable, Identifiable {
        case summary = "AI 归纳"
        case chat = "AI 讨论"
        case investment = "投资 Agent"

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .summary: "sparkles"
            case .chat: "message"
            case .investment: "scope"
            }
        }
    }

    enum AIScopeKind: String, CaseIterable, Identifiable {
        case current = "当前灵感"
        case selected = "手动多选"
        case today = "今天"
        case week = "本周"
        case month = "本月"
        case custom = "自定义日期"
        case tag = "指定标签"
        case topic = "AI 主题"

        var id: String { rawValue }
    }

    enum PendingAIAction {
        case annotation([UUID])
        case summary
        case chat(String)
        case evaluation([Idea])
    }

    var selectedIdea: Idea? {
        guard let selectedIdeaID else { return visibleIdeas.first }
        return visibleIdeas.first { $0.id == selectedIdeaID } ?? visibleIdeas.first
    }

    var activeIdeas: [Idea] {
        ideas.filter { $0.status != .archived }
    }

    var archivedIdeas: [Idea] {
        ideas.filter { $0.status == .archived }
    }

    var bubbleIdeas: [Idea] {
        activeIdeas.filter { $0.status != .executed }
    }

    var bubbleDetailIdea: Idea? {
        guard let bubbleDetailIdeaID else { return nil }
        return ideas.first { $0.id == bubbleDetailIdeaID }
    }

    var visibleIdeas: [Idea] {
        let statusFiltered: [Idea]
        if let selectedStatus {
            statusFiltered = ideas.filter { $0.status.workflowStatus == selectedStatus.workflowStatus }
        } else {
            statusFiltered = ideas
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return statusFiltered }
        return statusFiltered.filter { idea in
            idea.rawText.localizedCaseInsensitiveContains(query)
                || idea.aiTitle?.localizedCaseInsensitiveContains(query) == true
                || idea.aiTopic?.localizedCaseInsensitiveContains(query) == true
                || idea.tags.contains { $0.localizedCaseInsensitiveContains(query) }
                || idea.aiSuggestedTags.contains {
                    $0.localizedCaseInsensitiveContains(query)
                }
        }
    }

    var weeklyCount: Int {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
        return bubbleIdeas.filter { $0.createdAt >= start }.count
    }

    var recentIdeas: [Idea] {
        Array(bubbleIdeas.prefix(14))
    }

    var selectedSummary: Summary? {
        guard let selectedSummaryID else { return summaries.first }
        return summaries.first { $0.id == selectedSummaryID } ?? summaries.first
    }

    var selectedConversation: Conversation? {
        guard let selectedConversationID else { return nil }
        return conversations.first { $0.id == selectedConversationID }
    }

    var currentEvaluationHistory: [Evaluation] {
        evaluations.filter { $0.ideaID == selectedIdea?.id }.sorted { $0.createdAt > $1.createdAt }
    }

    var selectedEvaluation: Evaluation? {
        currentEvaluationHistory.first { $0.id == selectedEvaluationID } ?? currentEvaluationHistory.first
    }

    var investmentScopeIdeas: [Idea] {
        currentAIScopeIdeas.filter { $0.status != .archived }
    }

    var investmentCandidates: [Evaluation] {
        var latest: [UUID: Evaluation] = [:]
        for evaluation in evaluations.sorted(by: { $0.createdAt > $1.createdAt }) {
            if latest[evaluation.ideaID] == nil { latest[evaluation.ideaID] = evaluation }
        }
        let eligible = Set(ideas.filter { $0.status != .archived && $0.status != .executed }.map(\.id))
        return latest.values.filter { result in
            eligible.contains(result.ideaID) && result.verdict != .archive
                && result.sourceRawText == ideas.first(where: { $0.id == result.ideaID })?.rawText
        }.sorted {
            if $0.verdict != $1.verdict {
                return InvestmentAgent.verdictRank($0.verdict) < InvestmentAgent.verdictRank($1.verdict)
            }
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            return $0.createdAt > $1.createdAt
        }
    }

    func selectEvaluation(_ evaluation: Evaluation) {
        revealIdea(evaluation.ideaID)
        selectedEvaluationID = evaluation.id
    }

    func revealIdea(_ id: UUID) {
        if !visibleIdeas.contains(where: { $0.id == id }) {
            searchText = ""
            selectedStatus = nil
        }
        selectedIdeaID = id
    }

    var availableTags: [String] {
        Array(Set(ideas.flatMap(\.tags))).sorted()
    }

    var availableTopics: [String] {
        Array(
            Set(
                ideas.compactMap(\.aiTopic).filter {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            )
        ).sorted()
    }

    var currentAIScopeIdeas: [Idea] {
        let calendar = Calendar.current
        let active = ideas.filter { $0.status != .archived }
        switch aiScopeKind {
        case .current:
            return selectedIdea.map { [$0] } ?? []
        case .selected:
            return ideas.filter { aiSelectedIdeaIDs.contains($0.id) }
        case .today:
            let start = calendar.startOfDay(for: Date())
            return active.filter { $0.createdAt >= start }
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else {
                return []
            }
            return active.filter { interval.contains($0.createdAt) }
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: Date()) else {
                return []
            }
            return active.filter { interval.contains($0.createdAt) }
        case .custom:
            let start = calendar.startOfDay(for: min(aiCustomStartDate, aiCustomEndDate))
            let endDay = calendar.startOfDay(for: max(aiCustomStartDate, aiCustomEndDate))
            let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: endDay) ?? .distantFuture
            return active.filter { $0.createdAt >= start && $0.createdAt < exclusiveEnd }
        case .tag:
            let normalized = aiSelectedTag.lowercased()
            return active.filter { $0.tags.contains(normalized) }
        case .topic:
            return active.filter {
                $0.aiTopic?.localizedCaseInsensitiveCompare(aiSelectedTopic) == .orderedSame
            }
        }
    }

    var currentAIScopeDescription: String {
        "\(aiScopeKind.rawValue) · \(currentAIScopeIdeas.count) 条"
    }

    var privacyPromptText: String {
        let host = aiSettings.normalizedHost ?? "未知服务"
        let count: Int
        switch pendingPrivacyAction {
        case .annotation(let ids):
            count = ids.count
        case .evaluation(let snapshots):
            count = snapshots.count
        case .summary:
            count = currentAIScopeIdeas.count
        case .chat:
            count = selectedConversation.map {
                Set($0.scopeIdeaIDs).count
            } ?? currentAIScopeIdeas.count
        case nil:
            count = 0
        }
        return "将向 \(host) 发送所选的 \(count) 条灵感正文及必要的标签、状态和时间信息。对话还会发送会话消息及关联的历史评估快照。API 服务可能按其政策处理这些数据。"
    }

    var isAIConfigured: Bool {
        aiSettings.baseURL != nil && !aiSettings.model.isEmpty
    }

    func count(for status: IdeaStatus) -> Int {
        ideas.filter { $0.status.workflowStatus == status.workflowStatus }.count
    }

    func select(_ idea: Idea) {
        selectedIdeaID = idea.id
    }

    func showBubbleDetail(_ idea: Idea) {
        selectedIdeaID = idea.id
        bubbleDetailIdeaID = idea.id
    }

    func toggleBubbleDetail(_ idea: Idea) {
        if bubbleDetailIdeaID == idea.id {
            dismissBubbleDetail()
        } else {
            showBubbleDetail(idea)
        }
    }

    func dismissBubbleDetail() {
        bubbleDetailIdeaID = nil
    }

    func loadIdeas() async {
        guard let repository else {
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            var loaded: [Idea] = []
            let pageSize = 500
            var offset = 0
            while true {
                let page = try await repository.listIdeas(
                    IdeaQuery(
                        includeArchived: true,
                        limit: pageSize,
                        offset: offset
                    )
                )
                loaded.append(contentsOf: page)
                guard page.count == pageSize else { break }
                offset += page.count
            }
            ideas = loaded.sorted { $0.createdAt > $1.createdAt }
            normalizeSelection()
            persistenceError = nil
        } catch {
            presentPersistenceError(error, context: "读取想法失败")
        }
    }

    func loadAIConfiguration() async {
        aiSettings = await settingsStore.load()
        let presence = await keyStore.presence(account: AISettings.primaryKeychainAccount)
        hasStoredAPIKey = presence == .present
        keychainStatusUnavailable = presence == .unavailable
    }

    func loadAIState() async {
        await loadAIConfiguration()
        guard let repository else { return }
        do {
            summaries = try await repository.summaries(limit: .max)
            conversations = try await repository.conversations(limit: .max)
                .sorted { $0.updatedAt > $1.updatedAt }
            selectedSummaryID = summaries.first?.id
            var loadedEvaluations: [Evaluation] = []
            for idea in ideas {
                loadedEvaluations.append(contentsOf: try await repository.evaluations(for: idea.id))
            }
            evaluations = loadedEvaluations.sorted { $0.createdAt > $1.createdAt }
            if aiSettings.automaticAnnotationEnabled,
               aiSettings.hasPrivacyConsent,
               let enabledAt = aiSettings.automaticAnnotationEnabledAt {
                let pending = ideas.filter {
                    $0.status != .archived
                        && $0.aiAnnotatedAt == nil
                        && $0.createdAt >= enabledAt
                }.map(\.id)
                enqueueAnnotations(pending)
            }
        } catch {
            presentPersistenceError(error, context: "读取 AI 历史失败")
        }
    }

    @discardableResult
    func capture(
        _ draft: QuickCaptureDraft,
        source: IdeaSource = .quickCapture
    ) async -> Bool {
        guard let repository, !isSaving else { return false }
        let rawText = draft.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else { return false }

        isSaving = true
        defer { isSaving = false }
        do {
            let tags = TagResolver.resolve(
                manualTagText: draft.manualTagText,
                rawText: draft.rawText
            )
            let idea = try await repository.createIdea(
                rawText: draft.rawText,
                source: source,
                tags: tags
            )
            ideas.insert(idea, at: 0)
            selectedIdeaID = idea.id
            persistenceError = nil
            activityMessage = tags.isEmpty
                ? "已收进灵感菇"
                : "已收进灵感菇 · \(tags.map { "#\($0)" }.joined(separator: " "))"
            if aiSettings.automaticAnnotationEnabled {
                requestAIAction(.annotation([idea.id]))
            }
            return true
        } catch {
            presentPersistenceError(error, context: "保存失败，草稿仍然保留")
            return false
        }
    }

    @discardableResult
    func updateIdea(id: UUID, rawText: String, tags: [String]) async -> Bool {
        guard let repository,
              !isSaving,
              let existing = ideas.first(where: { $0.id == id }) else {
            return false
        }

        var updated = existing
        updated.rawText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.tags = Idea.normalize(tags: tags)
        updated.updatedAt = Date()
        guard updated.isValid else {
            persistenceError = "保存失败：想法内容不能为空"
            return false
        }

        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.saveIdea(updated)
            replaceIdea(updated)
            persistenceError = nil
            activityMessage = "想法已保存"
            return true
        } catch {
            presentPersistenceError(error, context: "保存修改失败")
            return false
        }
    }

    @discardableResult
    func setStatus(_ status: IdeaStatus, for ideaID: UUID) async -> Bool {
        guard let repository,
              !isSaving,
              let existing = ideas.first(where: { $0.id == ideaID }) else {
            return false
        }

        isSaving = true
        defer { isSaving = false }
        do {
            var updated = existing
            let now = Date()
            if status == .archived {
                try await repository.archiveIdea(id: ideaID, at: now)
                updated.status = .archived
                updated.archivedAt = now
            } else {
                updated.status = status
                updated.archivedAt = nil
                updated.updatedAt = now
                try await repository.saveIdea(updated)
            }
            updated.updatedAt = now
            replaceIdea(updated)
            persistenceError = nil
            normalizeSelection()
            return true
        } catch {
            presentPersistenceError(error, context: "状态更新失败")
            return false
        }
    }

    @discardableResult
    func restoreArchivedIdea(_ ideaID: UUID) async -> Bool {
        let restored = await setStatus(.inbox, for: ideaID)
        if restored {
            activityMessage = "灵感已恢复到待处理"
        }
        return restored
    }

    func completeBubbleIdea(_ ideaID: UUID) async {
        guard await setStatus(.executed, for: ideaID) else { return }
        bubbleDetailIdeaID = nil
        activityMessage = "灵感已完成"
    }

    func discardBubbleIdea(_ ideaID: UUID) async {
        guard await setStatus(.archived, for: ideaID) else { return }
        bubbleDetailIdeaID = nil
        activityMessage = "灵感已抛弃，可在已归档中恢复"
    }

    func startCompletingBubbleIdea(_ ideaID: UUID) async {
        guard let idea = ideas.first(where: { $0.id == ideaID }) else { return }
        if idea.status == .testing {
            guard await setStatus(.inbox, for: ideaID) else { return }
            activityMessage = "已取消进行中，灵感已回到待处理"
        } else {
            guard await setStatus(.testing, for: ideaID) else { return }
            activityMessage = "已标记为进行中，气泡会持续高亮"
        }
    }

    func prepareAIDiscussion(for ideaID: UUID) {
        guard !isStreamingChat, unsavedConversation == nil else { return }
        revealIdea(ideaID)
        aiScopeKind = .current
        selectedConversationID = nil
        insightMode = .chat
        bubbleDetailIdeaID = nil
        activityMessage = "已将当前灵感带入 AI 讨论区"
    }

    func exportData(_ format: IdeaExportFormat) async throws -> Data {
        guard let repository else {
            throw PersistenceError.openFailed("本地数据库不可用")
        }
        switch format {
        case .markdown:
            return Data(IdeaExporter.markdown(ideas: ideas).utf8)
        case .json:
            let summaries = try await repository.summaries(limit: .max)
            let conversations = try await repository.conversations(limit: .max)
            var evaluations: [Evaluation] = []
            for idea in ideas {
                evaluations.append(contentsOf: try await repository.evaluations(for: idea.id))
            }
            return try IdeaExporter.json(
                IdeaExportEnvelope(
                    ideas: ideas,
                    summaries: summaries,
                    evaluations: evaluations,
                    conversations: conversations
                )
            )
        }
    }

    func presentPersistenceError(_ error: Error, context: String) {
        let description = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        persistenceError = "\(context)：\(description)"
        activityMessage = persistenceError
    }

    @discardableResult
    func saveAISettings(
        _ draft: AISettings,
        apiKey: String,
        backfillChoice: AnnotationBackfillChoice
    ) async -> Bool {
        guard !isAnnotating, !isSummarizing, !isStreamingChat, !isTestingAIConnection, !isEvaluating else {
            aiError = "请先停止或等待正在运行的 AI 任务，再修改配置"
            return false
        }
        var normalized = draft
        let oldHost = aiSettings.normalizedHost
        if normalized.normalizedHost != oldHost {
            normalized.privacyConsentHost = nil
        } else {
            normalized.privacyConsentHost = aiSettings.privacyConsentHost
        }
        let newlyEnabled = !aiSettings.automaticAnnotationEnabled
            && normalized.automaticAnnotationEnabled
        if newlyEnabled {
            normalized.automaticAnnotationEnabledAt = Date()
        } else if !normalized.automaticAnnotationEnabled {
            normalized.automaticAnnotationEnabledAt = nil
        } else if normalized.automaticAnnotationEnabledAt == nil {
            normalized.automaticAnnotationEnabledAt = aiSettings.automaticAnnotationEnabledAt
                ?? Date()
        }

        do {
            _ = try normalized.validatedConfiguration()
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let destinationChanged = normalized.baseURL?.host != aiSettings.baseURL?.host
                || normalized.baseURL?.port != aiSettings.baseURL?.port
                || normalized.baseURL?.scheme != aiSettings.baseURL?.scheme
            if destinationChanged {
                if trimmedKey.isEmpty && !normalized.isLoopback {
                    throw AIProviderError.invalidConfiguration("更换服务地址后，请填写新服务的 API Key")
                }
                // Fail closed: remove the old credential before switching destinations.
                try await keyStore.deleteAPIKey(account: AISettings.primaryKeychainAccount)
                hasStoredAPIKey = false
            }
            try await settingsStore.save(normalized)
            aiSettings = normalized
            if !trimmedKey.isEmpty {
                try await keyStore.setAPIKey(
                    trimmedKey,
                    account: AISettings.primaryKeychainAccount
                )
                hasStoredAPIKey = true
                keychainStatusUnavailable = false
            }
            aiSettings = normalized
            aiError = nil
            activityMessage = "AI 设置已保存"
            if !normalized.automaticAnnotationEnabled {
                cancelAnnotationBatch()
                activityMessage = "AI 设置已保存"
            } else if newlyEnabled {
                requestAnnotationBackfill(backfillChoice)
            }
            return true
        } catch {
            presentAIError(error, context: "保存 AI 设置失败")
            return false
        }
    }

    func deleteStoredAPIKey() async {
        do {
            try await keyStore.deleteAPIKey(account: AISettings.primaryKeychainAccount)
            hasStoredAPIKey = false
            keychainStatusUnavailable = false
            activityMessage = "已从 Keychain 删除 API Key"
        } catch {
            presentAIError(error, context: "删除 API Key 失败")
        }
    }

    func testAIConnection() {
        guard !isTestingAIConnection else { return }
        isTestingAIConnection = true
        aiError = nil
        Task {
            defer { isTestingAIConnection = false }
            do {
                let provider = try await makeProvider()
                try await provider.testConnection()
                activityMessage = "AI 连接测试成功"
            } catch {
                presentAIError(error, context: "连接测试失败")
            }
        }
    }

    func requestAnnotation(for ideaID: UUID) {
        requestAIAction(.annotation([ideaID]))
    }

    func requestAnnotationBackfill(_ choice: AnnotationBackfillChoice) {
        guard choice != .futureOnly else { return }
        let now = Date()
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)
            ?? .distantPast
        let ids = ideas.filter {
            $0.status != .archived
                && $0.aiAnnotatedAt == nil
                && (choice == .allActive || $0.createdAt >= sevenDaysAgo)
        }.map(\.id)
        guard !ids.isEmpty else {
            activityMessage = "没有需要补充整理的灵感"
            return
        }
        requestAIAction(.annotation(ids))
    }

    func applySuggestedTags(_ selectedTags: Set<String>, to ideaID: UUID) async {
        guard let repository,
              let existing = ideas.first(where: { $0.id == ideaID }),
              !selectedTags.isEmpty else {
            return
        }
        var updated = existing
        updated.tags = Idea.normalize(tags: updated.tags + Array(selectedTags))
        updated.updatedAt = Date()
        do {
            try await repository.saveIdea(updated)
            replaceIdea(updated)
            activityMessage = "已合并 \(selectedTags.count) 个 AI 标签"
        } catch {
            presentPersistenceError(error, context: "应用 AI 标签失败")
        }
    }

    func cancelAnnotationBatch() {
        annotationQueue.removeAll()
        annotationTask?.cancel()
        activityMessage = "已停止 AI 整理"
    }

    func requestSummary() {
        guard !currentAIScopeIdeas.isEmpty else {
            aiError = "当前范围内没有可以总结的灵感"
            return
        }
        requestAIAction(.summary)
    }

    func cancelSummary() {
        summaryTask?.cancel()
        activityMessage = "已停止生成总结"
    }

    func startNewConversation() {
        guard !isStreamingChat, unsavedConversation == nil else { return }
        selectedConversationID = nil
        streamingChatText = ""
        chatDraft = ""
        aiError = nil
        chatCanRetry = false
    }

    func selectConversation(_ conversation: Conversation) {
        guard !isStreamingChat, unsavedConversation == nil else { return }
        selectedConversationID = conversation.id
        streamingChatText = ""
    }

    func sendChat() {
        if let pending = unsavedConversation {
            guard !isStreamingChat else { return }
            isStreamingChat = true
            Task {
                defer { isStreamingChat = false }
                if await persistConversation(pending) {
                    unsavedConversation = nil
                    streamingChatText = ""
                    chatDraft = ""
                    chatCanRetry = false
                    activityMessage = "对话已重新保存"
                }
            }
            return
        }
        let text = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreamingChat else { return }
        let scopeIdeas = conversationScopeIdeas()
        guard !scopeIdeas.isEmpty else {
            aiError = "当前对话范围内没有可发送的灵感"
            return
        }
        requestAIAction(.chat(text))
    }

    func stopChat() {
        guard isStreamingChat else { return }
        chatStopRequested = true
        chatTask?.cancel()
    }

    func cancelPrivacyConfirmation() {
        pendingPrivacyAction = nil
    }

    func confirmPrivacyAndContinue() {
        guard let action = pendingPrivacyAction else { return }
        pendingPrivacyAction = nil
        Task {
            do {
                var settings = aiSettings
                settings.privacyConsentHost = settings.normalizedHost
                try await settingsStore.save(settings)
                aiSettings = settings
                executeAIAction(action)
            } catch {
                presentAIError(error, context: "保存隐私确认失败")
            }
        }
    }

    private func requestAIAction(_ action: PendingAIAction) {
        guard isAIConfigured || providerOverride != nil else {
            aiError = "请先在 AI 设置中填写 Base URL 和模型"
            return
        }
        if aiSettings.hasPrivacyConsent || providerOverride != nil {
            executeAIAction(action)
        } else {
            pendingPrivacyAction = action
        }
    }

    private func executeAIAction(_ action: PendingAIAction) {
        switch action {
        case .annotation(let ids):
            enqueueAnnotations(ids)
        case .summary:
            generateSummary()
        case .chat(let text):
            beginStreamingChat(text)
        case .evaluation(let snapshots):
            beginInvestmentReview(snapshots)
        }
    }

    private func enqueueAnnotations(_ ids: [UUID]) {
        guard annotationTask?.isCancelled != true else {
            activityMessage = "正在停止整理，请稍后重试"
            return
        }
        let existingIDs = Set(annotationQueue)
        let candidates = ids.filter { ideaID in
            !existingIDs.contains(ideaID)
                && ideas.contains(where: { $0.id == ideaID })
        }
        guard !candidates.isEmpty else { return }
        annotationQueue.append(contentsOf: candidates)
        if annotationTask == nil {
            annotationCompletedCount = 0
            annotationFailureCount = 0
            annotationTotalCount = annotationQueue.count
            isAnnotating = true
            annotationTask = Task { [weak self] in
                await self?.runAnnotationQueue()
            }
        } else {
            annotationTotalCount += candidates.count
        }
    }

    private func runAnnotationQueue() async {
        defer {
            annotationTask = nil
            isAnnotating = false
            annotationQueue.removeAll()
        }
        while !annotationQueue.isEmpty {
            if Task.isCancelled { return }
            let ideaID = annotationQueue.removeFirst()
            do {
                try await annotateIdea(ideaID)
                annotationCompletedCount += 1
            } catch is CancellationError {
                return
            } catch {
                annotationFailureCount += 1
                presentAIError(error, context: "整理灵感失败")
            }
        }
        activityMessage = annotationFailureCount == 0
            ? "AI 整理完成"
            : "AI 整理完成，\(annotationFailureCount) 条失败"
    }

    private func annotateIdea(_ ideaID: UUID) async throws {
        guard let repository,
              let existing = ideas.first(where: { $0.id == ideaID }) else {
            throw PersistenceError.notFound
        }
        let provider = try await makeProvider()
        let annotation = try await provider.annotate(idea: existing)
        try Task.checkCancellation()
        let updated = try await repository.saveAnnotation(
            annotation, for: ideaID, expectedText: existing.rawText, model: provider.modelName
        )
        replaceIdea(updated)
    }

    private func generateSummary() {
        guard !isSummarizing else { return }
        let scopedIdeas = currentAIScopeIdeas
        guard !scopedIdeas.isEmpty else { return }
        let scope = currentSummaryScope()
        isSummarizing = true
        aiError = nil
        summaryTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isSummarizing = false
                self.summaryTask = nil
            }
            do {
                let provider = try await self.makeProvider()
                let summary = try await provider.summarize(
                    ideas: scopedIdeas,
                    scope: scope
                )
                try Task.checkCancellation()
                guard let repository = self.repository else {
                    throw PersistenceError.openFailed("本地数据库不可用")
                }
                try await repository.saveSummary(summary)
                self.summaries.removeAll { $0.id == summary.id }
                self.summaries.insert(summary, at: 0)
                self.selectedSummaryID = summary.id
                self.activityMessage = "阶段总结已生成并保存"
            } catch is CancellationError {
                self.activityMessage = "已停止生成总结"
            } catch {
                self.presentAIError(error, context: "生成总结失败")
            }
        }
    }

    private func beginStreamingChat(_ text: String) {
        guard !isStreamingChat else { return }
        let scopeIdeas = conversationScopeIdeas()
        guard !scopeIdeas.isEmpty else { return }
        let originalConversation = selectedConversation
        let retrying = chatCanRetry
        isStreamingChat = true
        chatCanRetry = false
        chatStopRequested = false
        streamingChatText = ""
        aiError = nil
        chatTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isStreamingChat = false
                self.chatTask = nil
            }
            do {
                let provider = try await self.makeProvider()
                var conversation = originalConversation ?? Conversation(
                    title: String(text.prefix(32)),
                    scopeIdeaIDs: scopeIdeas.map(\.id),
                    model: provider.modelName
                )
                if !retrying || conversation.messages.last?.role != .user
                    || conversation.messages.last?.content != text {
                    conversation.messages.append(ConversationMessage(role: .user, content: text))
                }
                conversation.updatedAt = Date()
                guard await self.persistConversation(conversation) else { return }

                let turns = conversation.messages.map {
                    AIChatTurn(role: $0.role, content: $0.content)
                }
                var responseText = ""
                do {
                    for try await chunk in provider.chatStream(
                        turns: turns,
                        ideas: scopeIdeas
                    ) {
                        try Task.checkCancellation()
                        responseText += chunk
                        self.streamingChatText = responseText
                    }
                } catch where Task.isCancelled || self.chatStopRequested {
                    if !responseText.isEmpty {
                        conversation.messages.append(
                            ConversationMessage(
                                role: .assistant,
                                content: responseText,
                                sourceIdeaIDs: self.citedIdeaIDs(
                                    in: responseText,
                                    allowed: scopeIdeas
                                ),
                                model: provider.modelName,
                                promptVersion: PromptCatalog.chatVersion,
                                deliveryState: .stopped
                            )
                        )
                        conversation.updatedAt = Date()
                        guard await self.persistConversation(conversation) else {
                            self.unsavedConversation = conversation
                            self.chatCanRetry = true
                            return
                        }
                    }
                    self.streamingChatText = ""
                    self.chatDraft = ""
                    self.chatCanRetry = false
                    self.activityMessage = "AI 回复已停止"
                    return
                }

                if self.chatStopRequested {
                    if !responseText.isEmpty {
                        conversation.messages.append(
                            ConversationMessage(
                                role: .assistant,
                                content: responseText,
                                sourceIdeaIDs: self.citedIdeaIDs(
                                    in: responseText,
                                    allowed: scopeIdeas
                                ),
                                model: provider.modelName,
                                promptVersion: PromptCatalog.chatVersion,
                                deliveryState: .stopped
                            )
                        )
                        conversation.updatedAt = Date()
                        guard await self.persistConversation(conversation) else {
                            self.unsavedConversation = conversation
                            self.chatCanRetry = true
                            return
                        }
                    }
                    self.streamingChatText = ""
                    self.chatDraft = ""
                    self.chatCanRetry = false
                    self.activityMessage = "AI 回复已停止"
                    return
                }

                guard !responseText.isEmpty else {
                    throw AIProviderError.emptyContent
                }
                conversation.messages.append(
                    ConversationMessage(
                        role: .assistant,
                        content: responseText,
                        sourceIdeaIDs: self.citedIdeaIDs(
                            in: responseText,
                            allowed: scopeIdeas
                        ),
                        model: provider.modelName,
                        promptVersion: PromptCatalog.chatVersion
                    )
                )
                conversation.model = provider.modelName
                conversation.updatedAt = Date()
                guard await self.persistConversation(conversation) else {
                    self.unsavedConversation = conversation
                    self.chatCanRetry = true
                    return
                }
                self.streamingChatText = ""
                self.chatDraft = ""
                self.chatCanRetry = false
            } catch is CancellationError {
                self.streamingChatText = ""
            } catch {
                self.chatCanRetry = true
                self.presentAIError(error, context: "AI 对话失败，可直接重试")
            }
        }
    }

    private func persistConversation(_ conversation: Conversation) async -> Bool {
        guard let repository else {
            presentPersistenceError(
                PersistenceError.openFailed("本地数据库不可用"),
                context: "保存对话失败"
            )
            return false
        }
        do {
            try await repository.saveConversation(conversation)
            conversations.removeAll { $0.id == conversation.id }
            conversations.insert(conversation, at: 0)
            conversations.sort { $0.updatedAt > $1.updatedAt }
            selectedConversationID = conversation.id
            persistenceError = nil
            return true
        } catch {
            presentPersistenceError(error, context: "保存对话失败")
            return false
        }
    }

    private func conversationScopeIdeas() -> [Idea] {
        if let selectedConversation {
            let ids = Set(selectedConversation.scopeIdeaIDs)
            return ideas.filter { ids.contains($0.id) }
        }
        return currentAIScopeIdeas
    }

    private func currentSummaryScope() -> SummaryScope {
        let scopedIDs = currentAIScopeIdeas.map(\.id)
        let calendar = Calendar.current
        let now = Date()
        switch aiScopeKind {
        case .current, .selected:
            return .ideaIDs(scopedIDs)
        case .today:
            return .dateRange(
                start: calendar.startOfDay(for: now),
                end: now
            )
        case .week:
            return .dateRange(
                start: calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now,
                end: now
            )
        case .month:
            return .dateRange(
                start: calendar.dateInterval(of: .month, for: now)?.start ?? now,
                end: now
            )
        case .custom:
            let start = calendar.startOfDay(for: min(aiCustomStartDate, aiCustomEndDate))
            let endDay = calendar.startOfDay(for: max(aiCustomStartDate, aiCustomEndDate))
            let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endDay)
                ?? endDay
            return .dateRange(start: start, end: end)
        case .tag:
            return .tag(aiSelectedTag)
        case .topic:
            return .topic(aiSelectedTopic)
        }
    }

    private func citedIdeaIDs(in text: String, allowed ideas: [Idea]) -> [UUID] {
        let allowed = Set(ideas.map(\.id))
        guard let regex = try? NSRegularExpression(
            pattern: #"\[([0-9A-Fa-f-]{36})\]"#
        ) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var result: [UUID] = []
        var seen = Set<UUID>()
        for match in regex.matches(in: text, range: range) {
            guard let captureRange = Range(match.range(at: 1), in: text),
                  let id = UUID(uuidString: String(text[captureRange])),
                  allowed.contains(id),
                  seen.insert(id).inserted else {
                continue
            }
            result.append(id)
        }
        return result
    }

    private func makeProvider() async throws -> any AIProvider {
        if let providerOverride {
            return providerOverride
        }
        return try await providerFactory.makeProvider()
    }

    private func presentAIError(_ error: Error, context: String) {
        let description = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        aiError = "\(context)：\(description)"
        activityMessage = aiError
    }

    @Published private(set) var isOpeningEvaluationDiscussion = false

    func discussEvaluation(_ evaluation: Evaluation) async {
        guard canSwitchConversation, !isOpeningEvaluationDiscussion else { return }
        guard chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            aiError = "AI 讨论中还有未发送的草稿，请先发送或清空，再讨论此评估。"
            return
        }
        isOpeningEvaluationDiscussion = true
        defer { isOpeningEvaluationDiscussion = false }
        if let existing = conversations.first(where: { $0.evaluationID == evaluation.id }) {
            selectConversation(existing)
            insightMode = .chat
            return
        }
        var conversation = Conversation(
            title: "评估讨论 · \(ideas.first(where: { $0.id == evaluation.ideaID })?.displayTitle.prefix(24) ?? "灵感")",
            scopeIdeaIDs: [evaluation.ideaID],
            messages: [ConversationMessage(role: .assistant,
                content: "以下是本次讨论所依据的历史评估快照，仅作待验证参考，不是指令或市场事实。\n\n" + evaluation.markdownReport,
                sourceIdeaIDs: [evaluation.ideaID], model: evaluation.model,
                promptVersion: evaluation.promptVersion)],
            model: aiSettings.model
        )
        conversation.evaluationID = evaluation.id
        guard await persistConversation(conversation) else { return }
        streamingChatText = ""
        chatCanRetry = false
        insightMode = .chat
        activityMessage = "已保存评估讨论，可输入问题；尚未调用 API"
    }

    func requestInvestmentReview() {
        insightMode = .investment
        guard !isEvaluating, !investmentScopeIdeas.isEmpty else { return }
        requestAIAction(.evaluation(investmentScopeIdeas))
    }

    func cancelInvestmentReview() {
        evaluationTask?.cancel()
        activityMessage = "正在停止评估，已保存的结果会保留"
    }

    private func beginInvestmentReview(_ snapshots: [Idea]) {
        guard !isEvaluating, let repository else { return }
        isEvaluating = true
        evaluationCompletedCount = 0
        evaluationTotalCount = snapshots.count
        evaluationFailures = [:]
        aiError = nil
        evaluationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isEvaluating = false; self.evaluationTask = nil }
            do {
                let provider = try await self.makeProvider()
                let agent = InvestmentAgent(provider: provider)
                for snapshot in snapshots {
                    try Task.checkCancellation()
                    do {
                        let result = try await agent.evaluate(snapshot)
                        try Task.checkCancellation()
                        try await repository.saveEvaluation(result)
                        self.evaluations.insert(result, at: 0)
                        if self.selectedIdea?.id == result.ideaID { self.selectedEvaluationID = result.id }
                    } catch {
                        if Task.isCancelled { throw CancellationError() }
                        self.evaluationFailures[snapshot.id] = error.localizedDescription
                    }
                    self.evaluationCompletedCount += 1
                }
                self.activityMessage = "评估完成：\(self.evaluationCompletedCount - self.evaluationFailures.count) 条成功，\(self.evaluationFailures.count) 条失败；未修改灵感状态"
            } catch is CancellationError {
                self.activityMessage = "评估已停止，已完成的历史已保留"
            } catch {
                self.presentAIError(error, context: "评估失败")
            }
        }
    }

    private func replaceIdea(_ idea: Idea) {
        guard let index = ideas.firstIndex(where: { $0.id == idea.id }) else { return }
        ideas[index] = idea
        ideas.sort { $0.createdAt > $1.createdAt }
    }

    private func normalizeSelection() {
        if let selectedIdeaID, visibleIdeas.contains(where: { $0.id == selectedIdeaID }) {
            return
        }
        selectedIdeaID = visibleIdeas.first?.id
    }
}
