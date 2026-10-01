import AppKit
import LingGanGuCore
import SwiftUI
import UniformTypeIdentifiers

struct WorkbenchView: View {
    @ObservedObject var appState: IdeaAppState
    let openQuickCapture: () -> Void
    let openAISettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 232)

            Divider().opacity(0.45)

            ideaWorkspace
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.45)

            insightPanel
                .frame(width: 306)
        }
        .frame(minWidth: 920, minHeight: 620)
        .background(AppPalette.canvas)
        .foregroundStyle(AppPalette.primaryText)
        .overlay(alignment: .bottom) {
            if let message = appState.activityMessage {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: AppPalette.primaryText.opacity(0.16), radius: 10, y: 5)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture {
                        withAnimation { appState.activityMessage = nil }
                    }
            }
        }
        .alert(
            "本地数据错误",
            isPresented: Binding(
                get: { appState.persistenceError != nil },
                set: { if !$0 { appState.persistenceError = nil } }
            )
        ) {
            Button("知道了") {
                appState.persistenceError = nil
            }
        } message: {
            Text(appState.persistenceError ?? "")
        }
        .alert(
            "AI 请求失败",
            isPresented: Binding(
                get: { appState.aiError != nil },
                set: { if !$0 { appState.aiError = nil } }
            )
        ) {
            Button("打开 AI 设置", action: openAISettings)
            Button("知道了") {
                appState.aiError = nil
            }
        } message: {
            Text(appState.aiError ?? "")
        }
        .alert(
            "发送灵感前确认",
            isPresented: Binding(
                get: { appState.pendingPrivacyAction != nil },
                set: { if !$0 { appState.cancelPrivacyConfirmation() } }
            )
        ) {
            Button("取消", role: .cancel) {
                appState.cancelPrivacyConfirmation()
            }
            Button("同意并发送") {
                appState.confirmPrivacyAndContinue()
            }
        } message: {
            Text(appState.privacyPromptText)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(AppPalette.moss.opacity(0.15))
                    Image(systemName: "sparkles")
                        .foregroundStyle(AppPalette.mossDeep)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text("灵感菇")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("\(appState.activeIdeas.count) 个想法在生长")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppPalette.secondaryText)
                }
            }

            Button(action: openQuickCapture) {
                Label("记录新想法", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .foregroundStyle(.white)
                    .background(AppPalette.moss, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(" ", modifiers: [.command, .shift])

            HStack(spacing: 7) {
                Button {
                    export(.markdown)
                } label: {
                    Label("Markdown", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .foregroundStyle(AppPalette.primaryText)
                        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(AppPalette.primaryText.opacity(0.12))
                        }
                }
                Button {
                    export(.json)
                } label: {
                    Label("JSON", systemImage: "curlybraces")
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .foregroundStyle(AppPalette.primaryText)
                        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(AppPalette.primaryText.opacity(0.12))
                        }
                }
            }
            .font(.system(size: 10.5, weight: .semibold))
            .buttonStyle(.plain)
            .disabled(appState.isLoading || appState.isSaving)

            Text("状态")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(AppPalette.secondaryText)
                .textCase(.uppercase)
                .tracking(1.1)

            VStack(spacing: 4) {
                SidebarFilterRow(
                    title: "全部灵感",
                    symbol: "square.stack.3d.up",
                    count: appState.ideas.count,
                    selected: appState.selectedStatus == nil
                ) {
                    appState.selectedStatus = nil
                }

                ForEach(IdeaStatus.workflowCases, id: \.self) { status in
                    SidebarFilterRow(
                        title: status.localizedName,
                        symbol: status.symbolName,
                        count: appState.count(for: status),
                        selected: appState.selectedStatus == status
                    ) {
                        appState.selectedStatus = status
                    }
                    .help(status.explanation)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 7) {
                Label("本地优先", systemImage: "externaldrive")
                Label(
                    appState.aiSettings.automaticAnnotationEnabled
                        ? "AI 自动整理已开启"
                        : "AI 自动整理已关闭",
                    systemImage: appState.aiSettings.automaticAnnotationEnabled
                        ? "sparkles"
                        : "lock"
                )
                if appState.isAnnotating {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text(
                            "\(appState.annotationCompletedCount)/\(appState.annotationTotalCount)"
                        )
                        Button("停止") {
                            appState.cancelAnnotationBatch()
                        }
                        .buttonStyle(.link)
                    }
                }
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(AppPalette.secondaryText)
        }
        .padding(18)
        .frame(maxHeight: .infinity)
        .background(AppPalette.glassTint.opacity(0.7))
    }

    private var ideaWorkspace: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppPalette.secondaryText)
                    TextField("搜索想法或标签", text: $appState.searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(AppPalette.primaryText.opacity(0.08))
                }

                Text("\(appState.visibleIdeas.count) 条")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppPalette.secondaryText)
            }
            .padding(16)

            Divider().opacity(0.42)

            HStack(spacing: 0) {
                ideaList
                    .frame(width: 282)

                Divider().opacity(0.4)

                ideaDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var ideaList: some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                ForEach(appState.visibleIdeas) { idea in
                    HStack(spacing: 7) {
                        if appState.aiScopeKind == .selected {
                            Button {
                                if appState.aiSelectedIdeaIDs.contains(idea.id) {
                                    appState.aiSelectedIdeaIDs.remove(idea.id)
                                } else {
                                    appState.aiSelectedIdeaIDs.insert(idea.id)
                                }
                            } label: {
                                Image(
                                    systemName: appState.aiSelectedIdeaIDs.contains(idea.id)
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                                .foregroundStyle(AppPalette.moss)
                            }
                            .buttonStyle(.plain)
                        }

                        IdeaRow(
                            idea: idea,
                            hasEvaluation: appState.evaluations.contains { $0.ideaID == idea.id },
                            selected: appState.selectedIdeaID == idea.id,
                            color: color(for: idea)
                        ) {
                            appState.select(idea)
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(Color.white.opacity(0.24))
        .overlay {
            if appState.visibleIdeas.isEmpty {
                if appState.isLoading {
                    ProgressView("正在读取本地想法…")
                } else if appState.ideas.isEmpty {
                    ContentUnavailableView(
                        "种下第一颗灵感",
                        systemImage: "sparkles",
                        description: Text("按 ⌘⇧Space，随手记下现在的想法")
                    )
                } else {
                    ContentUnavailableView(
                        appState.searchText.isEmpty ? "暂无\(appState.selectedStatus?.localizedName ?? "")灵感" : "没有找到灵感",
                        systemImage: "magnifyingglass",
                        description: Text(appState.searchText.isEmpty
                            ? (appState.selectedStatus?.explanation ?? "记录新灵感后会显示在这里")
                            : "换个关键词，或清空搜索查看此分类")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var ideaDetail: some View {
        if let idea = appState.selectedIdea {
            IdeaDetailEditor(appState: appState, idea: idea)
                .id(idea.id)
        } else {
            ContentUnavailableView(
                "选择一条想法",
                systemImage: "sparkles",
                description: Text("在左侧选择后查看详情")
            )
        }
    }

    private var insightPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("智能工作台")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
                Button(action: openAISettings) {
                    Image(systemName: "gearshape")
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help("AI 设置")
            }

            Picker("智能模式", selection: $appState.insightMode) {
                ForEach(IdeaAppState.InsightMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.symbolName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch appState.insightMode {
            case .summary:
                summaryPreview
            case .chat:
                chatPanel
            case .investment:
                InvestmentPanelView(appState: appState) { aiScopeControls }
            }
        }
        .padding(18)
        .background(AppPalette.glassTint.opacity(0.52))
    }

    private var summaryPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            aiScopeControls

            HStack {
                Text("总结历史")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppPalette.secondaryText)
                Spacer()
                Menu("\(appState.summaries.count) 份") {
                    ForEach(appState.summaries) { summary in
                        Button(summary.createdAt.formatted(date: .abbreviated, time: .shortened)) {
                            appState.selectedSummaryID = summary.id
                        }
                    }
                }
                .menuStyle(.borderlessButton)
            }

            ScrollView {
                if let summary = appState.selectedSummary {
                    VStack(alignment: .leading, spacing: 9) {
                        summaryCard(
                            "核心主题",
                            symbol: "point.3.connected.trianglepath.dotted",
                            color: AppPalette.lavender,
                            lines: summary.content.themes
                        )
                        summaryCard(
                            "重复方向",
                            symbol: "arrow.triangle.2.circlepath",
                            color: AppPalette.amber,
                            lines: summary.content.repeatedDirections
                        )
                        summaryCard(
                            "新方向",
                            symbol: "lightbulb",
                            color: AppPalette.sage,
                            lines: summary.content.newDirections
                        )
                        summaryCard(
                            "矛盾",
                            symbol: "arrow.left.arrow.right",
                            color: AppPalette.coral,
                            lines: summary.content.contradictions
                        )
                        summaryCard(
                            "未解决问题",
                            symbol: "questionmark.bubble",
                            color: AppPalette.lavender,
                            lines: summary.content.openQuestions
                        )
                        summaryCard(
                            "合并建议",
                            symbol: "arrow.triangle.merge",
                            color: AppPalette.amber,
                            lines: summary.content.mergeSuggestions
                        )
                        summaryCard(
                            "行动建议",
                            symbol: "figure.walk.motion",
                            color: AppPalette.sage,
                            lines: summary.content.actions
                        )
                        sourceIdeas(summary.sourceIdeaIDs)
                    }
                } else {
                    ContentUnavailableView(
                        "还没有阶段总结",
                        systemImage: "sparkles",
                        description: Text("选择范围后主动生成")
                    )
                }
            }

            Button {
                if appState.isSummarizing {
                    appState.cancelSummary()
                } else {
                    appState.requestSummary()
                }
            } label: {
                Label(
                    appState.isSummarizing ? "停止生成" : "生成阶段总结",
                    systemImage: appState.isSummarizing ? "stop.fill" : "sparkles"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(appState.isSummarizing ? AppPalette.coral : AppPalette.moss)
            .disabled(appState.currentAIScopeIdeas.isEmpty)
        }
    }

    private var chatPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Menu {
                    ForEach(appState.conversations) { conversation in
                        Button(conversation.title) {
                            appState.selectConversation(conversation)
                        }
                    }
                } label: {
                    Label(
                        appState.selectedConversation?.title ?? "新对话",
                        systemImage: "clock.arrow.circlepath"
                    )
                    .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                Spacer()
                Button {
                    appState.startNewConversation()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.plain)
                .help("新建对话")
            }
            .disabled(!appState.canSwitchConversation)

            if appState.selectedConversation == nil {
                aiScopeControls
            } else {
                Text("\(appState.selectedConversation?.evaluationID == nil ? "对话范围" : "评估讨论 · 已关联历史报告") · \(appState.selectedConversation?.scopeIdeaIDs.count ?? 0) 条")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppPalette.secondaryText)
            }

            ScrollView {
                LazyVStack(spacing: 9) {
                    if let conversation = appState.selectedConversation {
                        ForEach(conversation.messages) { message in
                            ChatMessageBubble(message: message) { id in
                                if let idea = appState.ideas.first(where: { $0.id == id }) {
                                    appState.select(idea)
                                }
                            }
                        }
                    }
                    if !appState.streamingChatText.isEmpty {
                        ChatMessageBubble(
                            message: ConversationMessage(
                                role: .assistant,
                                content: appState.streamingChatText,
                                sourceIdeaIDs: appState.selectedConversation?.scopeIdeaIDs ?? []
                            ),
                            isStreaming: true,
                            selectSource: { id in
                                if let idea = appState.ideas.first(where: { $0.id == id }) { appState.select(idea) }
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))

            TextField(
                "围绕这些灵感提问…",
                text: $appState.chatDraft,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...5)
            .disabled(appState.isStreamingChat || appState.hasUnsavedReply)

            Button {
                if appState.isStreamingChat {
                    appState.stopChat()
                } else {
                    appState.sendChat()
                }
            } label: {
                Label(
                    appState.isStreamingChat
                        ? "停止生成"
                        : (appState.hasUnsavedReply ? "重新保存回复" : (appState.chatCanRetry ? "重试" : "发送")),
                    systemImage: appState.isStreamingChat ? "stop.fill" : "paperplane.fill"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .tint(appState.isStreamingChat ? AppPalette.coral : AppPalette.moss)
            .disabled(
                !appState.isStreamingChat
                    && appState.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
    }

    private var aiScopeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("发送范围", selection: $appState.aiScopeKind) {
                ForEach(IdeaAppState.AIScopeKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.menu)

            switch appState.aiScopeKind {
            case .custom:
                DatePicker(
                    "开始",
                    selection: $appState.aiCustomStartDate,
                    displayedComponents: .date
                )
                DatePicker(
                    "结束",
                    selection: $appState.aiCustomEndDate,
                    displayedComponents: .date
                )
            case .tag:
                Picker("标签", selection: $appState.aiSelectedTag) {
                    Text("请选择").tag("")
                    ForEach(appState.availableTags, id: \.self) { tag in
                        Text("#\(tag)").tag(tag)
                    }
                }
                .pickerStyle(.menu)
            case .topic:
                Picker("AI 主题", selection: $appState.aiSelectedTopic) {
                    Text("请选择").tag("")
                    ForEach(appState.availableTopics, id: \.self) { topic in
                        Text(topic).tag(topic)
                    }
                }
                .pickerStyle(.menu)
            case .selected:
                Text("在中间列表勾选需要发送的灵感；可明确选择归档记录。")
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.secondaryText)
            default:
                EmptyView()
            }

            Text(appState.currentAIScopeDescription)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(AppPalette.secondaryText)
        }
        .padding(10)
        .background(Color.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func summaryCard(
        _ title: String,
        symbol: String,
        color: Color,
        lines: [String]
    ) -> some View {
        if !lines.isEmpty {
            InsightCard(title: title, symbol: symbol, color: color, lines: lines)
        }
    }

    @ViewBuilder
    private func sourceIdeas(_ ids: [UUID]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("来源记录")
                .font(.system(size: 11, weight: .semibold))
            if ids.isEmpty {
                Text("未找到对应原始记录")
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppPalette.secondaryText)
            } else {
                ForEach(ids, id: \.self) { id in
                    Button {
                        if let idea = appState.ideas.first(where: { $0.id == id }) {
                            appState.select(idea)
                        }
                    } label: {
                        Text(
                            appState.ideas.first(where: { $0.id == id })?.displayTitle
                                ?? String(id.uuidString.prefix(8))
                        )
                        .lineLimit(1)
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 12))
    }

    private func color(for idea: Idea) -> Color {
        let value = idea.tags.first?.unicodeScalars.reduce(0) { $0 + Int($1.value) } ?? 0
        return AppPalette.bubbleColors[value % AppPalette.bubbleColors.count]
    }

    private func export(_ format: IdeaExportFormat) {
        Task {
            do {
                let data = try await appState.exportData(format)
                let savePanel = NSSavePanel()
                savePanel.title = "导出 \(format.displayName)"
                savePanel.nameFieldStringValue = "灵感菇导出.\(format.fileExtension)"
                if let type = UTType(filenameExtension: format.fileExtension) {
                    savePanel.allowedContentTypes = [type]
                }
                guard savePanel.runModal() == .OK, let url = savePanel.url else { return }
                try data.write(to: url, options: .atomic)
                appState.activityMessage = "已导出 \(appState.ideas.count) 条想法"
            } catch {
                appState.presentPersistenceError(error, context: "导出失败")
            }
        }
    }
}

private struct IdeaDetailEditor: View {
    @ObservedObject var appState: IdeaAppState
    let idea: Idea

    @State private var isEditing = false
    @State private var draftText: String
    @State private var draftTags: String
    @State private var selectedSuggestedTags = Set<String>()

    init(appState: IdeaAppState, idea: Idea) {
        self.appState = appState
        self.idea = idea
        _draftText = State(initialValue: idea.rawText)
        _draftTags = State(initialValue: idea.tags.map { "#\($0)" }.joined(separator: " "))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("原始想法")
                            .font(.system(size: 10.5, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(AppPalette.secondaryText)
                    }

                    Spacer()

                    if isEditing {
                        Button("取消", action: cancelEditing)
                            .buttonStyle(.bordered)
                        Button("保存") {
                            Task {
                                let saved = await appState.updateIdea(
                                    id: idea.id,
                                    rawText: draftText,
                                    tags: TagResolver.parseManualTags(draftTags)
                                )
                                if saved { isEditing = false }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppPalette.moss)
                        .disabled(
                            draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || appState.isSaving
                        )
                    } else {
                        Button("编辑", action: beginEditing)
                            .buttonStyle(.bordered)

                        Menu {
                            if idea.status == .archived {
                                Button("恢复到待处理") {
                                    Task { await appState.restoreArchivedIdea(idea.id) }
                                }
                            } else {
                                ForEach(IdeaStatus.workflowCases, id: \.self) { status in
                                    Button(status.localizedName) {
                                        Task { await appState.setStatus(status, for: idea.id) }
                                    }
                                }
                            }
                        } label: {
                            Label(idea.status.localizedName, systemImage: idea.status.symbolName)
                                .font(.system(size: 11.5, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppPalette.moss.opacity(0.12), in: Capsule())
                        }
                        .menuStyle(.borderlessButton)
                        .disabled(appState.isSaving)
                    }
                }

                Text(idea.displayTitle)
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .textSelection(.enabled)

                if isEditing {
                    VStack(alignment: .leading, spacing: 12) {
                        TextEditor(text: $draftText)
                            .font(.system(size: 15))
                            .lineSpacing(6)
                            .frame(minHeight: 150)
                            .scrollContentBackground(.hidden)

                        Divider()

                        HStack(spacing: 8) {
                            Image(systemName: "number")
                                .foregroundStyle(AppPalette.secondaryText)
                            TextField(
                                "标签；空格、逗号或 # 分隔。保存空值会清空标签",
                                text: $draftTags
                            )
                            .textFieldStyle(.plain)
                        }
                        .font(.system(size: 12))
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.8))
                    }
                } else {
                    Text(idea.rawText)
                        .font(.system(size: 15))
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.8))
                        }

                    if !idea.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("标签")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppPalette.secondaryText)
                            FlowTags(tags: idea.tags)
                        }
                    }

                    VStack(alignment: .leading, spacing: 11) {
                        HStack {
                            Label("AI 整理", systemImage: "sparkles")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Button(idea.aiAnnotatedAt == nil ? "AI 整理" : "重新整理") {
                                appState.requestAnnotation(for: idea.id)
                            }
                            .buttonStyle(.bordered)
                            .disabled(appState.isAnnotating)
                        }

                        if let topic = idea.aiTopic, !topic.isEmpty {
                            Label(topic, systemImage: "point.3.connected.trianglepath.dotted")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(AppPalette.mossDeep)
                        }

                        if !idea.aiSuggestedTags.isEmpty {
                            Text("标签建议（确认后才会合并）")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(AppPalette.secondaryText)

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 76), alignment: .leading)],
                                alignment: .leading,
                                spacing: 7
                            ) {
                                ForEach(idea.aiSuggestedTags, id: \.self) { tag in
                                    Button {
                                        if selectedSuggestedTags.contains(tag) {
                                            selectedSuggestedTags.remove(tag)
                                        } else {
                                            selectedSuggestedTags.insert(tag)
                                        }
                                    } label: {
                                        Label(
                                            "#\(tag)",
                                            systemImage: selectedSuggestedTags.contains(tag)
                                                ? "checkmark.circle.fill"
                                                : "circle"
                                        )
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.system(size: 10.5))
                                }
                            }

                            Button("应用选中的标签") {
                                let selected = selectedSuggestedTags
                                Task {
                                    await appState.applySuggestedTags(selected, to: idea.id)
                                    selectedSuggestedTags.removeAll()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppPalette.moss)
                            .disabled(selectedSuggestedTags.isEmpty)
                        } else if idea.aiAnnotatedAt == nil {
                            Text("尚未发送给 AI；原始正文始终保留。")
                                .font(.system(size: 10.5))
                                .foregroundStyle(AppPalette.secondaryText)
                        }

                        if let model = idea.aiAnnotationModel,
                           let annotatedAt = idea.aiAnnotatedAt {
                            Text(
                                "\(model) · \(annotatedAt.formatted(date: .abbreviated, time: .shortened))"
                            )
                            .font(.system(size: 9.5))
                            .foregroundStyle(AppPalette.secondaryText)
                        }
                    }
                    .padding(14)
                    .background(
                        AppPalette.lavender.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }

                HStack(spacing: 18) {
                    Label(
                        idea.createdAt.formatted(date: .abbreviated, time: .shortened),
                        systemImage: "clock"
                    )
                    Label("Idea \(idea.id.uuidString.prefix(8))", systemImage: "number")
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppPalette.secondaryText)
            }
            .padding(22)
        }
    }

    private func beginEditing() {
        draftText = idea.rawText
        draftTags = idea.tags.map { "#\($0)" }.joined(separator: " ")
        isEditing = true
    }

    private func cancelEditing() {
        draftText = idea.rawText
        draftTags = idea.tags.map { "#\($0)" }.joined(separator: " ")
        isEditing = false
    }
}

private struct FlowTags: View {
    let tags: [String]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 72), alignment: .leading)],
            alignment: .leading,
            spacing: 7
        ) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AppPalette.lavender.opacity(0.2), in: Capsule())
            }
        }
    }
}

private struct SidebarFilterRow: View {
    let title: String
    let symbol: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol)
                    .frame(width: 18)
                Text(title)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppPalette.secondaryText)
            }
            .font(.system(size: 12, weight: selected ? .semibold : .medium))
            .padding(.horizontal, 9)
            .frame(height: 31)
            .contentShape(Rectangle())
            .background(
                selected ? AppPalette.moss.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppPalette.primaryText)
    }
}

private struct IdeaRow: View {
    let idea: Idea
    let hasEvaluation: Bool
    let selected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(Color.white.opacity(0.85)))
                    .shadow(color: color.opacity(0.4), radius: 3)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 6) {
                    Text(idea.displayTitle)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack {
                        Text(idea.status.localizedName)
                        Spacer()
                        Text(idea.createdAt, style: .relative)
                    }
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(AppPalette.secondaryText)
                    if idea.aiAnnotatedAt != nil || hasEvaluation {
                        HStack(spacing: 8) {
                            if idea.aiAnnotatedAt != nil { Text("已整理") }
                            if hasEvaluation { Text("已评估") }
                        }
                        .font(.system(size: 9))
                        .foregroundStyle(AppPalette.secondaryText)
                    }
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? Color.white.opacity(0.82) : Color.white.opacity(0.34),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        selected ? AppPalette.moss.opacity(0.36) : Color.white.opacity(0.45),
                        lineWidth: selected ? 1.2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppPalette.primaryText)
        .accessibilityLabel("\(idea.displayTitle)，\(idea.status.localizedName)")
    }
}

private struct InsightCard: View {
    let title: String
    let symbol: String
    let color: Color
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11.5, weight: .semibold))

            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 7) {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                        .padding(.top, 4)
                    Text(line)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(AppPalette.primaryText.opacity(0.9))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.7))
        }
    }
}

private struct ChatMessageBubble: View {
    let message: ConversationMessage
    var isStreaming = false
    let selectSource: (UUID) -> Void

    var body: some View {
        VStack(
            alignment: message.role == .user ? .trailing : .leading,
            spacing: 6
        ) {
            Text(message.role == .assistant
                ? ChatCitationDisplay.render(message.content, allowedIDs: message.sourceIdeaIDs, streaming: isStreaming)
                : AttributedString(message.content))
                .font(.system(size: 11.5))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == "linggangu-source", let host = url.host,
                          let id = UUID(uuidString: host), message.sourceIdeaIDs.contains(id) else { return .discarded }
                    selectSource(id)
                    return .handled
                })

            if message.role == .assistant {
                if message.deliveryState == .stopped {
                    Label("已停止", systemImage: "stop.circle")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(AppPalette.coral)
                }
                if message.sourceIdeaIDs.isEmpty && !isStreaming {
                    Text("本回复未附原始记录引用；建议内容请自行验证")
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppPalette.secondaryText)
                } else if !isStreaming {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(message.sourceIdeaIDs, id: \.self) { id in
                            Button("来源 \((message.sourceIdeaIDs.firstIndex(of: id) ?? 0) + 1) · 查看灵感") {
                                selectSource(id)
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 9.5))
                        }
                    }
                }
            }
        }
        .padding(9)
        .background(
            message.role == .user
                ? AppPalette.moss.opacity(0.14)
                : Color.white.opacity(0.58),
            in: RoundedRectangle(cornerRadius: 11)
        )
        .frame(
            maxWidth: .infinity,
            alignment: message.role == .user ? .trailing : .leading
        )
    }
}
