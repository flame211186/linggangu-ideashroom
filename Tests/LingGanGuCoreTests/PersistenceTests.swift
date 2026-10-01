import Foundation
import SQLite3
import XCTest
@testable import LingGanGuCore

final class PersistenceTests: XCTestCase {
    private func makeRepository() throws -> (SQLiteIdeaRepository, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingGanGuTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let databaseURL = directory.appendingPathComponent("ideas.sqlite")
        return (try SQLiteIdeaRepository(path: databaseURL.path), directory)
    }

    func testCreateSearchArchiveAndDelete() async throws {
        let (repository, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try await repository.createIdea(
            rawText: "做一个能总结想法的桌面组件",
            source: .quickCapture,
            tags: ["产品", "AI"]
        )
        _ = try await repository.createIdea(
            rawText: "研究玻璃蘑菇的视觉效果",
            source: .widget,
            tags: ["设计"]
        )

        let initialCount = try await repository.ideaCount(includeArchived: false)
        XCTAssertEqual(initialCount, 2)
        let searchResult = try await repository.listIdeas(
            IdeaQuery(searchText: "总结")
        )
        XCTAssertEqual(searchResult.map(\.id), [first.id])

        let tagged = try await repository.listIdeas(IdeaQuery(tag: "ai"))
        XCTAssertEqual(tagged.map(\.id), [first.id])
        let searchByTag = try await repository.listIdeas(IdeaQuery(searchText: "ai"))
        XCTAssertEqual(searchByTag.map(\.id), [first.id])

        try await repository.archiveIdea(
            id: first.id,
            at: Date(timeIntervalSince1970: 1_000)
        )
        let activeCount = try await repository.ideaCount(includeArchived: false)
        let totalCount = try await repository.ideaCount(includeArchived: true)
        XCTAssertEqual(activeCount, 1)
        XCTAssertEqual(totalCount, 2)

        let archived = try await repository.idea(id: first.id)
        XCTAssertEqual(archived?.status, .archived)
        XCTAssertNotNil(archived?.archivedAt)

        try await repository.deleteIdea(id: first.id)
        let deleted = try await repository.idea(id: first.id)
        XCTAssertNil(deleted)
    }

    func testEditStatusClearTagsAndReopenDatabase() async throws {
        let (repository, directory) = try makeRepository()
        let databaseURL = directory.appendingPathComponent("ideas.sqlite")

        var idea = try await repository.createIdea(
            rawText: "第一版正文",
            source: .quickCapture,
            tags: ["自动标签"]
        )
        idea.rawText = "修改后的中文\n多行正文"
        idea.tags = []
        idea.status = .testing
        idea.aiTitle = "AI 标题"
        idea.aiTopic = "产品验证"
        idea.aiSuggestedTags = ["建议", "验证"]
        idea.aiAnnotationModel = "mock"
        idea.aiAnnotationPromptVersion = PromptCatalog.annotationVersion
        idea.aiAnnotatedAt = Date(timeIntervalSince1970: 1_900)
        idea.updatedAt = Date(timeIntervalSince1970: 2_000)
        try await repository.saveIdea(idea)

        let reopened = try SQLiteIdeaRepository(path: databaseURL.path)
        let loaded = try await reopened.idea(id: idea.id)
        XCTAssertEqual(loaded?.rawText, "修改后的中文\n多行正文")
        XCTAssertEqual(loaded?.tags, [])
        XCTAssertEqual(loaded?.status, .testing)
        XCTAssertEqual(loaded?.aiTopic, "产品验证")
        XCTAssertEqual(loaded?.aiSuggestedTags, ["建议", "验证"])
        XCTAssertEqual(loaded?.aiAnnotationModel, "mock")

        try? FileManager.default.removeItem(at: directory)
    }

    func testBootstrapCreatesTimestampedBackupBeforeUpgrade() async throws {
        let (repository, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("ideas.sqlite")
        _ = try await repository.createIdea(
            rawText: "升级前必须保留",
            source: .quickCapture,
            tags: []
        )

        let preparation = try DatabaseBootstrapper.prepareDatabase(
            at: databaseURL,
            supportedSchemaVersion: SQLiteIdeaRepository.schemaVersion + 1,
            now: Date(timeIntervalSince1970: 1_000)
        )
        let backupURL = try XCTUnwrap(preparation.backupURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertTrue(backupURL.lastPathComponent.contains("pre-migration-v2"))
    }

    func testMigratesV1IdeaToV2WithoutLosingData() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingGanGuV1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("ideas.sqlite")
        let ideaID = UUID()
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        let sql = """
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
            '\(ideaID.uuidString)', '升级前正文', NULL, 100, 100,
            'inbox', 'quickCapture', '["旧标签"]', NULL
        );
        PRAGMA user_version = 1;
        """
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        let preparation = try DatabaseBootstrapper.prepareDatabase(
            at: databaseURL,
            supportedSchemaVersion: SQLiteIdeaRepository.schemaVersion,
            now: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertTrue(
            preparation.backupURL?.lastPathComponent.contains("pre-migration-v1") == true
        )
        let repository = try SQLiteIdeaRepository(path: databaseURL.path)
        let loaded = try await repository.idea(id: ideaID)
        XCTAssertEqual(loaded?.rawText, "升级前正文")
        XCTAssertEqual(loaded?.tags, ["旧标签"])
        XCTAssertNil(loaded?.aiTopic)
        XCTAssertEqual(loaded?.aiSuggestedTags, [])
    }

    func testPersistsSummaryEvaluationAndConversation() async throws {
        let (repository, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }

        let idea = try await repository.createIdea(
            rawText: "一个可以被验证的想法",
            source: .workbench,
            tags: []
        )
        let summary = Summary(
            scope: .ideaIDs([idea.id]),
            content: SummaryContent(themes: ["验证"]),
            sourceIdeaIDs: [idea.id],
            model: "mock",
            promptVersion: "summary-v1"
        )
        let evaluation = Evaluation(
            ideaID: idea.id,
            verdict: .validateNow,
            scores: EvaluationScores(
                painSeverity: 4,
                willingnessToPay: 3,
                differentiation: 3,
                founderFit: 5,
                validationEase: 5
            ),
            targetUser: "创作者",
            rationale: ["问题明确"],
            risks: ["样本不足"],
            missingEvidence: ["付费证据"],
            confidence: 0.6,
            smallestExperiment: "访谈 3 人",
            model: "mock",
            promptVersion: "investor-v1"
        )
        let conversation = Conversation(
            title: "讨论验证方式",
            scopeIdeaIDs: [idea.id],
            model: "mock"
        )

        try await repository.saveSummary(summary)
        try await repository.saveEvaluation(evaluation)
        try await repository.saveConversation(conversation)

        let summaries = try await repository.summaries(limit: 10)
        let evaluations = try await repository.evaluations(for: idea.id)
        let conversations = try await repository.conversations(limit: 10)
        XCTAssertEqual(summaries, [summary])
        XCTAssertEqual(evaluations, [evaluation])
        XCTAssertEqual(conversations, [conversation])
    }
}
