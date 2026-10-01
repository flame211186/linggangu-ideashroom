import Foundation
import LingGanGuCore
import SQLite3

@main
struct LingGanGuCoreChecks {
    static func main() async throws {
        if let address = ProcessInfo.processInfo.environment["LINGGANGU_REDIRECT_TEST_URL"] {
            guard let base = URL(string: address), base.host == "127.0.0.1" else { preconditionFailure("Local fixture only") }
            for code in [301, 302, 303, 307, 308] {
                let provider = try OpenAICompatibleProvider(configuration: AIProviderConfiguration(
                    baseURL: base.appending(path: "status/\(code)"), model: "mock"),
                    apiKey: "redirect-test-not-a-real-key", maximumRetries: 0)
                do {
                    try await provider.testConnection()
                    preconditionFailure("Redirect must fail")
                } catch let AIProviderError.httpStatus(status, _) { precondition(status == code) }
                do {
                    for try await _ in provider.chatStream(turns: [], ideas: []) { }
                    preconditionFailure("Stream redirect must fail")
                } catch let AIProviderError.httpStatus(status, _) { precondition(status == code) }
            }
            print("Authenticated redirect checks passed.")
            return
        }
        let secureConfiguration = AIRequestBoundary.configuration()
        let userA = InMemoryAPIKeyStore()
        let userB = InMemoryAPIKeyStore()
        await userA.setAPIKey("fake-user-A", account: "primary")
        await userB.setAPIKey("fake-user-B", account: "primary")
        let a = await userA.apiKey(account: "primary")
        let b = await userB.apiKey(account: "primary")
        precondition(a == "fake-user-A" && b == "fake-user-B")
        precondition(secureConfiguration.urlCache == nil && secureConfiguration.httpCookieStorage == nil)
        precondition(secureConfiguration.urlCredentialStorage == nil && !secureConfiguration.httpShouldSetCookies)
        precondition(secureConfiguration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        try ThemeValidator.validate(.glassSporeMushroom)
        let citationID = UUID()
        let citation = ChatCitationDisplay.render("建议 [\(citationID.uuidString)]", allowedIDs: [citationID])
        precondition(String(citation.characters) == "建议 [来源 1]")
        precondition(citation.runs.contains { $0.link?.scheme == "linggangu-source" })
        let unknown = ChatCitationDisplay.render("[\(UUID().uuidString)]", allowedIDs: [])
        precondition(String(unknown.characters) == "[来源不可用]")
        precondition(!unknown.runs.contains { $0.link != nil })
        let partial = ChatCitationDisplay.render("建议 [27D16131-", allowedIDs: [], streaming: true)
        precondition(String(partial.characters) == "建议 ")
        let wrapped = citationID.uuidString.replacingOccurrences(of: "-", with: "-\n")
        let readable = ChatCitationDisplay.render("## 今天步骤\n**建议** [\(wrapped)]", allowedIDs: [citationID])
        precondition(String(readable.characters) == "今天步骤\n建议 [来源 1]")
        let bare = ChatCitationDisplay.render(citationID.uuidString, allowedIDs: [citationID])
        precondition(String(bare.characters) == "[来源 1]")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingGanGuCoreChecks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = try SQLiteIdeaRepository(
            path: directory.appendingPathComponent("ideas.sqlite").path
        )
        let idea = try await repository.createIdea(
            rawText: "做一个能总结和筛选想法的桌面组件",
            source: .quickCapture,
            tags: ["产品", "AI"]
        )
        let activeCount = try await repository.ideaCount(includeArchived: false)
        let searchResults = try await repository.listIdeas(IdeaQuery(searchText: "总结"))
        let taggedResults = try await repository.listIdeas(IdeaQuery(tag: "ai"))
        let tagSearchResults = try await repository.listIdeas(IdeaQuery(searchText: "ai"))
        precondition(activeCount == 1)
        precondition(searchResults.first?.id == idea.id)
        precondition(taggedResults.first?.id == idea.id)
        precondition(tagSearchResults.first?.id == idea.id)

        let manualTags = TagResolver.resolve(
            manualTagText: "#产品, AI 产品",
            rawText: "正文 #设计"
        )
        precondition(manualTags == ["产品", "ai"])
        let extractedTags = TagResolver.resolve(
            manualTagText: "",
            rawText: "正文 #灵感整理 #AI-product #灵感整理"
        )
        precondition(extractedTags == ["灵感整理", "ai-product"])

        let provider = MockAIProvider()
        let annotation = try await provider.annotate(idea: idea)
        precondition(!annotation.title.isEmpty)
        var concurrentEdit = idea
        concurrentEdit.status = .testing
        concurrentEdit.tags = ["手动标签"]
        try await repository.saveIdea(concurrentEdit)
        let annotated = try await repository.saveAnnotation(annotation, for: idea.id,
            expectedText: idea.rawText, model: "mock")
        precondition(annotated.status == .testing && annotated.tags == ["手动标签"])
        concurrentEdit.rawText = "已修改的正文"
        try await repository.saveIdea(concurrentEdit)
        do {
            _ = try await repository.saveAnnotation(annotation, for: idea.id,
                expectedText: idea.rawText, model: "mock")
            preconditionFailure("Stale annotation must not overwrite edited text")
        } catch PersistenceError.invalidRecord { }
        try await repository.saveIdea(idea)

        let historyRepository = try SQLiteIdeaRepository(path: directory.appendingPathComponent("history.sqlite").path)
        for index in 0..<1_005 {
            try await historyRepository.saveConversation(Conversation(title: "History \(index)", scopeIdeaIDs: [], model: "mock"))
        }
        let allHistory = try await historyRepository.conversations(limit: .max)
        precondition(allHistory.count == 1_005, "History exports must not stop at 1000")
        let summary = try await provider.summarize(
            ideas: [idea],
            scope: .ideaIDs([idea.id])
        )
        try await repository.saveSummary(summary)
        let savedSummaries = try await repository.summaries(limit: 1)
        precondition(savedSummaries.first?.id == summary.id)

        let agent = InvestmentAgent(provider: provider)
        let evaluation = try await agent.evaluate(idea)
        try await repository.saveEvaluation(evaluation)
        let savedEvaluations = try await repository.evaluations(for: idea.id)
        precondition(savedEvaluations.first?.ideaID == idea.id)
        precondition(savedEvaluations.first?.sourceRawText == idea.rawText)
        precondition(savedEvaluations.first?.schemaVersion == 2)
        var legacyEvaluationJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(evaluation)) as! [String: Any]
        for key in ["supportingArguments", "opposingArguments", "distributionPlan", "sourceRawText", "schemaVersion"] {
            legacyEvaluationJSON.removeValue(forKey: key)
        }
        let legacyEvaluation = try JSONDecoder().decode(Evaluation.self, from: JSONSerialization.data(withJSONObject: legacyEvaluationJSON))
        precondition(legacyEvaluation.supportingArguments == nil && legacyEvaluation.schemaVersion == nil)
        precondition(idea.status == .inbox, "Agent must not mutate the source idea")

        var streamed = ""
        for try await chunk in provider.chatStream(
            turns: [AIChatTurn(role: .user, content: "如何验证？")],
            ideas: [idea]
        ) {
            streamed += chunk
        }
        precondition(streamed.contains(idea.id.uuidString))

        let envelope = IdeaExportEnvelope(
            ideas: [idea],
            summaries: [summary],
            evaluations: [evaluation]
        )
        let export = try IdeaExporter.json(envelope)
        let exportText = String(decoding: export, as: UTF8.self).lowercased()
        precondition(envelope.formatVersion == 2)
        precondition(!exportText.contains("apikey"))
        precondition(!exportText.contains("authorization"))

        var edited = idea
        edited.rawText = "修改后的中文\n多行正文"
        edited.tags = []
        edited.status = .testing
        edited.aiTitle = annotation.title
        edited.aiTopic = annotation.topic
        edited.aiSuggestedTags = annotation.tags
        edited.aiAnnotationModel = await provider.modelName
        edited.aiAnnotationPromptVersion = PromptCatalog.annotationVersion
        edited.aiAnnotatedAt = Date()
        edited.updatedAt = Date()
        try await repository.saveIdea(edited)
        let reopenedRepository = try SQLiteIdeaRepository(
            path: directory.appendingPathComponent("ideas.sqlite").path
        )
        let reopenedIdea = try await reopenedRepository.idea(id: idea.id)
        precondition(reopenedIdea?.rawText == edited.rawText)
        precondition(reopenedIdea?.tags.isEmpty == true)
        precondition(reopenedIdea?.status == .testing)
        precondition(reopenedIdea?.aiTopic == annotation.topic)
        precondition(reopenedIdea?.aiSuggestedTags == annotation.tags)

        let loopbackSettings = AISettings(
            baseURLString: "http://127.0.0.1:11434",
            model: "local-model"
        )
        precondition(loopbackSettings.isLoopback)
        _ = try loopbackSettings.validatedConfiguration()
        try await checkOpenAICompatibleProvider(idea: idea)

        let preparation = try DatabaseBootstrapper.prepareDatabase(
            at: directory.appendingPathComponent("ideas.sqlite"),
            supportedSchemaVersion: SQLiteIdeaRepository.schemaVersion + 1,
            now: Date(timeIntervalSince1970: 1_000)
        )
        precondition(
            preparation.backupURL.map {
                FileManager.default.fileExists(atPath: $0.path)
                    && $0.lastPathComponent.contains("pre-migration-v2")
            } == true
        )

        try await repository.archiveIdea(id: idea.id, at: Date())
        let remainingCount = try await repository.ideaCount(includeArchived: false)
        let totalCount = try await repository.ideaCount(includeArchived: true)
        precondition(remainingCount == 0)
        precondition(totalCount == 1)

        let legacyURL = directory.appendingPathComponent("legacy-v1.sqlite")
        let legacyIdeaID = UUID()
        var legacyDatabase: OpaquePointer?
        precondition(sqlite3_open(legacyURL.path, &legacyDatabase) == SQLITE_OK)
        let legacySQL = """
        CREATE TABLE ideas (
            id TEXT PRIMARY KEY NOT NULL, raw_text TEXT NOT NULL, ai_title TEXT,
            created_at REAL NOT NULL, updated_at REAL NOT NULL, status TEXT NOT NULL,
            source TEXT NOT NULL, tags_json TEXT NOT NULL DEFAULT '[]', archived_at REAL
        );
        CREATE TABLE summaries (
            id TEXT PRIMARY KEY NOT NULL, payload_json TEXT NOT NULL,
            source_idea_ids TEXT NOT NULL, created_at REAL NOT NULL
        );
        CREATE TABLE evaluations (
            id TEXT PRIMARY KEY NOT NULL, payload_json TEXT NOT NULL,
            idea_id TEXT NOT NULL, created_at REAL NOT NULL
        );
        CREATE TABLE conversations (
            id TEXT PRIMARY KEY NOT NULL, payload_json TEXT NOT NULL, created_at REAL NOT NULL
        );
        INSERT INTO ideas VALUES (
            '\(legacyIdeaID.uuidString)', 'v1 迁移保留正文', NULL, 100, 100,
            'inbox', 'quickCapture', '["迁移"]', NULL
        );
        PRAGMA user_version = 1;
        """
        precondition(sqlite3_exec(legacyDatabase, legacySQL, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(legacyDatabase)
        let legacyPreparation = try DatabaseBootstrapper.prepareDatabase(
            at: legacyURL,
            supportedSchemaVersion: SQLiteIdeaRepository.schemaVersion,
            now: Date(timeIntervalSince1970: 2_000)
        )
        precondition(
            legacyPreparation.backupURL?.lastPathComponent.contains("pre-migration-v1")
                == true
        )
        let migratedRepository = try SQLiteIdeaRepository(path: legacyURL.path)
        let migratedIdea = try await migratedRepository.idea(id: legacyIdeaID)
        precondition(migratedIdea?.rawText == "v1 迁移保留正文")
        precondition(migratedIdea?.aiSuggestedTags.isEmpty == true)

        print("LingGanGu core checks passed.")
    }

    private static func checkOpenAICompatibleProvider(idea: Idea) async throws {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [CoreCheckURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        let provider = try OpenAICompatibleProvider(
            configuration: AIProviderConfiguration(
                baseURL: URL(string: "https://example.com/v1")!,
                model: "check-model"
            ),
            apiKey: "core-check-secret",
            session: session,
            maximumRetries: 0
        )

        CoreCheckURLProtocol.handler = { request in
            precondition(request.url?.absoluteString == "https://example.com/v1/chat/completions")
            precondition(
                request.value(forHTTPHeaderField: "Authorization")
                    == "Bearer core-check-secret"
            )
            let object = try JSONSerialization.jsonObject(
                with: try coreCheckRequestBody(request)
            ) as? [String: Any]
            precondition(object?["max_completion_tokens"] != nil)
            return coreCheckResponse(
                request,
                status: 200,
                body: #"{"choices":[{"message":{"content":"OK"}}]}"#
            )
        }
        try await provider.testConnection()

        var structuredCount = 0
        CoreCheckURLProtocol.handler = { request in
            structuredCount += 1
            let object = try JSONSerialization.jsonObject(
                with: try coreCheckRequestBody(request)
            ) as? [String: Any]
            if object?["response_format"] != nil {
                return coreCheckResponse(
                    request,
                    status: 400,
                    body: #"{"error":{"message":"response_format unsupported"}}"#
                )
            }
            return coreCheckResponse(
                request,
                status: 200,
                body: #"{"choices":[{"message":{"content":"{\"title\":\"检查标题\",\"tags\":[\"检查\"],\"topic\":\"测试\"}"}}]}"#
            )
        }
        let annotation = try await provider.annotate(idea: idea)
        precondition(annotation.title == "检查标题")
        precondition(structuredCount == 3)

        var tokenCount = 0
        CoreCheckURLProtocol.handler = { request in
            tokenCount += 1
            let object = try JSONSerialization.jsonObject(
                with: try coreCheckRequestBody(request)
            ) as? [String: Any]
            if object?["max_completion_tokens"] != nil {
                return coreCheckResponse(
                    request,
                    status: 400,
                    body: #"{"error":{"message":"unknown max_completion_tokens"}}"#
                )
            }
            precondition(object?["max_tokens"] != nil)
            return coreCheckResponse(
                request,
                status: 200,
                body: #"{"choices":[{"message":{"content":"OK"}}]}"#
            )
        }
        try await provider.testConnection()
        precondition(tokenCount == 2)

        let summaryPayload: [String: Any] = [
            "themes": "测试主题", "repeatedDirections": NSNull(), "newDirections": [],
            "contradictions": [], "openQuestions": [], "mergeSuggestions": [],
            "actions": ["先验证"], "sourceIdeaIDs": [idea.id.uuidString, UUID().uuidString]
        ]
        let summaryJSON = String(decoding: try JSONSerialization.data(withJSONObject: summaryPayload), as: UTF8.self)
        var summaryAttempts = 0
        CoreCheckURLProtocol.handler = { request in
            summaryAttempts += 1
            let envelope: [String: Any] = ["choices": [["message": ["content": summaryAttempts == 1 ? "{broken" : summaryJSON], "finish_reason": "stop"]]]
            return coreCheckResponse(request, status: 200,
                body: String(decoding: try JSONSerialization.data(withJSONObject: envelope), as: UTF8.self))
        }
        let repairedSummary = try await provider.summarize(ideas: [idea], scope: .ideaIDs([idea.id]))
        precondition(summaryAttempts == 2)
        precondition(repairedSummary.content.themes == ["测试主题"])
        precondition(repairedSummary.sourceIdeaIDs == [idea.id])
        summaryAttempts = 0
        CoreCheckURLProtocol.handler = { request in
            summaryAttempts += 1
            return coreCheckResponse(request, status: 200,
                body: #"{"choices":[{"message":{"content":"{\"themes\":[]}"},"finish_reason":"length"}]}"#)
        }
        do {
            _ = try await provider.summarize(ideas: [idea], scope: .ideaIDs([idea.id]))
            preconditionFailure("Truncated summaries must fail")
        } catch AIProviderError.decoding { precondition(summaryAttempts == 2) }

        var evaluationPayload: [String: Any] = [
            "verdict": "observe",
            "scores": ["painSeverity": 2, "willingnessToPay": 1, "differentiation": 2, "founderFit": 1, "validationEase": 4],
            "targetUser": "学习者", "rationale": ["缺少证据"], "risks": ["需求不明"],
            "missingEvidence": ["访谈"], "confidence": 0.3, "smallestExperiment": "半天访谈三人",
            "supportingArguments": ["可低成本验证"], "opposingArguments": ["访谈不等于付费"],
            "distributionPlan": "从三位目标用户开始"
        ]
        var evaluationRequests = 0
        CoreCheckURLProtocol.handler = { request in
            evaluationRequests += 1
            let body = try JSONSerialization.jsonObject(with: coreCheckRequestBody(request)) as! [String: Any]
            if body["response_format"] != nil {
                return coreCheckResponse(request, status: 400, body: #"{"error":{"message":"response_format unsupported"}}"#)
            }
            let content = String(decoding: try JSONSerialization.data(withJSONObject: evaluationPayload), as: UTF8.self)
            let envelope: [String: Any] = ["choices": [["message": ["content": content], "finish_reason": "stop"]]]
            return coreCheckResponse(request, status: 200, body: String(decoding: try JSONSerialization.data(withJSONObject: envelope), as: UTF8.self))
        }
        let evaluated = try await InvestmentAgent(provider: provider).evaluate(idea)
        precondition(evaluationRequests == 3 && evaluated.distributionPlan == "从三位目标用户开始")
        precondition(evaluated.sourceRawText == idea.rawText && evaluated.promptVersion == PromptCatalog.investorVersion)
        evaluationPayload["confidence"] = 8
        do {
            _ = try await provider.evaluate(idea: idea)
            preconditionFailure("Invalid confidence must be rejected, not clamped")
        } catch AIProviderError.decoding { }
        evaluationPayload["confidence"] = 0.3
        evaluationPayload["smallestExperiment"] = ""
        do {
            _ = try await provider.evaluate(idea: idea)
            preconditionFailure("An evaluation requires a concrete experiment")
        } catch AIProviderError.decoding { }

        CoreCheckURLProtocol.handler = { request in
            coreCheckResponse(
                request,
                status: 200,
                body: """
                data: {"choices":[{"delta":{"content":"流式"}}]}

                data: {"choices":[{"delta":{"content":"检查"}}]}

                data: [DONE]

                """,
                contentType: "text/event-stream"
            )
        }
        var streamed = ""
        for try await chunk in provider.chatStream(
            turns: [AIChatTurn(role: .user, content: "测试")],
            ideas: [idea]
        ) {
            streamed += chunk
        }
        precondition(streamed == "流式检查")
        for brokenPayload in [
            "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n",
            "data: {\"error\":{\"message\":\"stream failed\"}}\n\ndata: [DONE]\n\n"
        ] {
            CoreCheckURLProtocol.handler = { request in
                coreCheckResponse(request, status: 200, body: brokenPayload, contentType: "text/event-stream")
            }
            do {
                for try await _ in provider.chatStream(turns: [], ideas: [idea]) { }
                preconditionFailure("Broken SSE must not report success")
            } catch is AIProviderError { }
        }
        let retryProvider = try OpenAICompatibleProvider(
            configuration: AIProviderConfiguration(baseURL: URL(string: "https://example.com")!, model: "check-model"),
            apiKey: "test-only", session: session, maximumRetries: 2)
        var retryCount = 0
        CoreCheckURLProtocol.handler = { request in
            retryCount += 1
            return coreCheckResponse(request, status: retryCount < 3 ? 503 : 200,
                body: retryCount < 3 ? "{}" : #"{"choices":[{"message":{"content":"recovered"}}]}"#)
        }
        var recovered = ""
        for try await chunk in retryProvider.chatStream(turns: [], ideas: [idea]) { recovered += chunk }
        precondition(retryCount == 3 && recovered == "recovered")
        CoreCheckURLProtocol.handler = { request in
            coreCheckResponse(request, status: 403,
                body: #"{"error":{"message":"Authorization: Bearer core-check-secret encoded-secret private-note"}}"#)
        }
        do {
            try await provider.testConnection()
            preconditionFailure("403 must fail")
        } catch {
            precondition(!String(describing: error).contains("core-check-secret"))
            precondition(!error.localizedDescription.contains("Authorization"))
            precondition(!error.localizedDescription.contains("private-note"))
        }
        CoreCheckURLProtocol.handler = { _ in
            throw NSError(domain: NSURLErrorDomain, code: URLError.timedOut.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "core-check-secret Authorization private-note"])
        }
        do {
            try await provider.testConnection()
            preconditionFailure("Transport must fail")
        } catch { precondition(!error.localizedDescription.contains("core-check-secret")) }
        do {
            for try await _ in provider.chatStream(turns: [], ideas: []) { }
            preconditionFailure("Stream transport must fail")
        } catch { precondition(!error.localizedDescription.contains("core-check-secret")) }
        CoreCheckURLProtocol.handler = nil
    }

    private static func coreCheckResponse(
        _ request: URLRequest,
        status: Int,
        body: String,
        contentType: String = "application/json"
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": contentType]
            )!,
            Data(body.utf8)
        )
    }

    private static func coreCheckRequestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else {
                throw stream.streamError ?? URLError(.cannotDecodeRawData)
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class CoreCheckURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler:
        ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
