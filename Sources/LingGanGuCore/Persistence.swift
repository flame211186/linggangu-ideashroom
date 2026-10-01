import Foundation
import SQLite3

public struct IdeaQuery: Sendable, Equatable {
    public var searchText: String?
    public var statuses: Set<IdeaStatus>
    public var tag: String?
    public var includeArchived: Bool
    public var limit: Int
    public var offset: Int

    public init(
        searchText: String? = nil,
        statuses: Set<IdeaStatus> = [],
        tag: String? = nil,
        includeArchived: Bool = false,
        limit: Int = 200,
        offset: Int = 0
    ) {
        self.searchText = searchText
        self.statuses = statuses
        self.tag = tag
        self.includeArchived = includeArchived
        self.limit = min(max(limit, 1), 1_000)
        self.offset = max(offset, 0)
    }
}

public enum PersistenceError: Error, Equatable, LocalizedError {
    case cannotCreateDirectory(String)
    case backupFailed(String)
    case openFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case stepFailed(String)
    case unsupportedSchema(Int)
    case invalidRecord(String)
    case notFound

    public var errorDescription: String? {
        switch self {
        case .cannotCreateDirectory(let message):
            "无法创建数据目录：\(message)"
        case .backupFailed(let message):
            "无法备份本地数据库：\(message)"
        case .openFailed(let message):
            "无法打开本地数据库：\(message)"
        case .prepareFailed(let message):
            "无法准备数据库操作：\(message)"
        case .bindFailed(let message):
            "无法写入数据库参数：\(message)"
        case .stepFailed(let message):
            "数据库操作失败：\(message)"
        case .unsupportedSchema(let version):
            "数据库版本 \(version) 高于当前应用支持的版本"
        case .invalidRecord(let message):
            "数据库记录无效：\(message)"
        case .notFound:
            "没有找到对应记录"
        }
    }
}

public protocol IdeaRepository: Sendable {
    func saveAnnotation(_ annotation: AIAnnotation, for id: UUID, expectedText: String, model: String) async throws -> Idea
    func createIdea(
        rawText: String,
        source: IdeaSource,
        tags: [String]
    ) async throws -> Idea
    func saveIdea(_ idea: Idea) async throws
    func idea(id: UUID) async throws -> Idea?
    func listIdeas(_ query: IdeaQuery) async throws -> [Idea]
    func archiveIdea(id: UUID, at date: Date) async throws
    func deleteIdea(id: UUID) async throws
    func ideaCount(includeArchived: Bool) async throws -> Int
    func saveSummary(_ summary: Summary) async throws
    func summaries(limit: Int) async throws -> [Summary]
    func saveEvaluation(_ evaluation: Evaluation) async throws
    func evaluations(for ideaID: UUID) async throws -> [Evaluation]
    func saveConversation(_ conversation: Conversation) async throws
    func conversations(limit: Int) async throws -> [Conversation]
}

public actor SQLiteIdeaRepository: IdeaRepository {
    public func saveAnnotation(_ annotation: AIAnnotation, for id: UUID, expectedText: String, model: String) throws -> Idea {
        guard var current = try idea(id: id) else { throw PersistenceError.notFound }
        guard current.rawText == expectedText else {
            throw PersistenceError.invalidRecord("灵感正文已修改，请重新整理")
        }
        current.aiTitle = annotation.title
        current.aiTopic = annotation.topic
        current.aiSuggestedTags = annotation.tags
        current.aiAnnotationModel = model
        current.aiAnnotationPromptVersion = PromptCatalog.annotationVersion
        current.aiAnnotatedAt = Date()
        current.updatedAt = Date()
        try saveIdea(current)
        return current
    }
    public static let schemaVersion = 2

    private let databasePath: String
    private let handle: SQLiteHandle
    private var database: OpaquePointer? { handle.pointer }
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(path: String) throws {
        databasePath = path
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw PersistenceError.cannotCreateDirectory(error.localizedDescription)
        }

        var pointer: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &pointer, flags, nil) == SQLITE_OK, let pointer else {
            let message = pointer.flatMap { sqlite3_errmsg($0) }.map(String.init(cString:))
                ?? "unknown sqlite error"
            sqlite3_close(pointer)
            throw PersistenceError.openFailed(message)
        }
        handle = SQLiteHandle(pointer)

        do {
            try Self.execute(on: pointer, sql: "PRAGMA foreign_keys = ON")
            try Self.execute(on: pointer, sql: "PRAGMA journal_mode = WAL")
            try Self.migrate(handle: pointer)
        } catch {
            throw error
        }
    }

    public static func defaultDatabaseURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let base = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw PersistenceError.cannotCreateDirectory("Application Support 不可用")
        }
        return base
            .appendingPathComponent("LingGanGu", isDirectory: true)
            .appendingPathComponent("linggangu.sqlite", isDirectory: false)
    }

    public func createIdea(
        rawText: String,
        source: IdeaSource = .quickCapture,
        tags: [String] = []
    ) throws -> Idea {
        let idea = Idea(rawText: rawText, source: source, tags: tags)
        guard idea.isValid else {
            throw PersistenceError.invalidRecord("想法内容不能为空")
        }
        try saveIdea(idea)
        return idea
    }

    public func saveIdea(_ idea: Idea) throws {
        guard idea.isValid else {
            throw PersistenceError.invalidRecord("想法内容不能为空")
        }
        let tagsData = try encoder.encode(Idea.normalize(tags: idea.tags))
        guard let tagsJSON = String(data: tagsData, encoding: .utf8) else {
            throw PersistenceError.invalidRecord("标签编码失败")
        }
        let suggestedTagsData = try encoder.encode(Idea.normalize(tags: idea.aiSuggestedTags))
        guard let suggestedTagsJSON = String(data: suggestedTagsData, encoding: .utf8) else {
            throw PersistenceError.invalidRecord("AI 标签建议编码失败")
        }

        let sql = """
        INSERT INTO ideas (
            id, raw_text, ai_title, created_at, updated_at, status, source, tags_json,
            archived_at, ai_topic, ai_suggested_tags_json, ai_annotation_model,
            ai_annotation_prompt_version, ai_annotated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            raw_text = excluded.raw_text,
            ai_title = excluded.ai_title,
            updated_at = excluded.updated_at,
            status = excluded.status,
            source = excluded.source,
            tags_json = excluded.tags_json,
            archived_at = excluded.archived_at,
            ai_topic = excluded.ai_topic,
            ai_suggested_tags_json = excluded.ai_suggested_tags_json,
            ai_annotation_model = excluded.ai_annotation_model,
            ai_annotation_prompt_version = excluded.ai_annotation_prompt_version,
            ai_annotated_at = excluded.ai_annotated_at
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(idea.id.uuidString, at: 1, in: statement)
        try bind(idea.rawText, at: 2, in: statement)
        try bind(idea.aiTitle, at: 3, in: statement)
        try bind(idea.createdAt.timeIntervalSince1970, at: 4, in: statement)
        try bind(idea.updatedAt.timeIntervalSince1970, at: 5, in: statement)
        try bind(idea.status.rawValue, at: 6, in: statement)
        try bind(idea.source.rawValue, at: 7, in: statement)
        try bind(tagsJSON, at: 8, in: statement)
        try bind(idea.archivedAt?.timeIntervalSince1970, at: 9, in: statement)
        try bind(idea.aiTopic, at: 10, in: statement)
        try bind(suggestedTagsJSON, at: 11, in: statement)
        try bind(idea.aiAnnotationModel, at: 12, in: statement)
        try bind(idea.aiAnnotationPromptVersion, at: 13, in: statement)
        try bind(idea.aiAnnotatedAt?.timeIntervalSince1970, at: 14, in: statement)
        try stepDone(statement)
    }

    public func idea(id: UUID) throws -> Idea? {
        let statement = try prepare(
            """
            SELECT id, raw_text, ai_title, created_at, updated_at, status, source, tags_json,
                archived_at, ai_topic, ai_suggested_tags_json, ai_annotation_model,
                ai_annotation_prompt_version, ai_annotated_at
            FROM ideas WHERE id = ? LIMIT 1
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return try decodeIdea(statement)
    }

    public func listIdeas(_ query: IdeaQuery = IdeaQuery()) throws -> [Idea] {
        var clauses: [String] = []
        var values: [SQLiteValue] = []

        if !query.includeArchived {
            clauses.append("status != ?")
            values.append(.text(IdeaStatus.archived.rawValue))
        }
        if !query.statuses.isEmpty {
            let statuses = query.statuses.sorted { $0.rawValue < $1.rawValue }
            clauses.append("status IN (\(Array(repeating: "?", count: statuses.count).joined(separator: ", ")))")
            values.append(contentsOf: statuses.map { .text($0.rawValue) })
        }
        if let search = normalizedOptional(query.searchText) {
            clauses.append(
                """
                (raw_text LIKE ? ESCAPE '\\'
                    OR COALESCE(ai_title, '') LIKE ? ESCAPE '\\'
                    OR tags_json LIKE ? ESCAPE '\\'
                    OR COALESCE(ai_topic, '') LIKE ? ESCAPE '\\'
                    OR ai_suggested_tags_json LIKE ? ESCAPE '\\')
                """
            )
            let pattern = "%\(escapeLike(search))%"
            values.append(.text(pattern))
            values.append(.text(pattern))
            values.append(.text(pattern))
            values.append(.text(pattern))
            values.append(.text(pattern))
        }
        if let tag = normalizedOptional(query.tag)?.lowercased() {
            clauses.append("tags_json LIKE ? ESCAPE '\\'")
            values.append(.text("%\"\(escapeLike(tag))\"%"))
        }

        let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        let sql = """
        SELECT id, raw_text, ai_title, created_at, updated_at, status, source, tags_json,
            archived_at, ai_topic, ai_suggested_tags_json, ai_annotation_model,
            ai_annotation_prompt_version, ai_annotated_at
        FROM ideas
        \(whereClause)
        ORDER BY created_at DESC
        LIMIT ? OFFSET ?
        """
        values.append(.int64(Int64(query.limit)))
        values.append(.int64(Int64(query.offset)))

        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            try bind(value, at: Int32(offset + 1), in: statement)
        }

        var ideas: [Idea] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                ideas.append(try decodeIdea(statement))
            case SQLITE_DONE:
                return ideas
            default:
                throw stepError()
            }
        }
    }

    public func archiveIdea(id: UUID, at date: Date = Date()) throws {
        let statement = try prepare(
            "UPDATE ideas SET status = ?, archived_at = ?, updated_at = ? WHERE id = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bind(IdeaStatus.archived.rawValue, at: 1, in: statement)
        try bind(date.timeIntervalSince1970, at: 2, in: statement)
        try bind(date.timeIntervalSince1970, at: 3, in: statement)
        try bind(id.uuidString, at: 4, in: statement)
        try stepDone(statement)
        guard sqlite3_changes(database) > 0 else {
            throw PersistenceError.notFound
        }
    }

    public func deleteIdea(id: UUID) throws {
        let statement = try prepare("DELETE FROM ideas WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, at: 1, in: statement)
        try stepDone(statement)
        guard sqlite3_changes(database) > 0 else {
            throw PersistenceError.notFound
        }
    }

    public func ideaCount(includeArchived: Bool = false) throws -> Int {
        let sql = includeArchived
            ? "SELECT COUNT(*) FROM ideas"
            : "SELECT COUNT(*) FROM ideas WHERE status != ?"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        if !includeArchived {
            try bind(IdeaStatus.archived.rawValue, at: 1, in: statement)
        }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw stepError()
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    public func saveSummary(_ summary: Summary) throws {
        try saveCodableRecord(
            table: "summaries",
            id: summary.id,
            payload: summary,
            createdAt: summary.createdAt,
            extraColumn: ("source_idea_ids", summary.sourceIdeaIDs.map(\.uuidString).joined(separator: ","))
        )
    }

    public func summaries(limit: Int = 100) throws -> [Summary] {
        try loadCodableRecords(table: "summaries", limit: limit, as: Summary.self)
    }

    public func saveEvaluation(_ evaluation: Evaluation) throws {
        try saveCodableRecord(
            table: "evaluations",
            id: evaluation.id,
            payload: evaluation,
            createdAt: evaluation.createdAt,
            extraColumn: ("idea_id", evaluation.ideaID.uuidString)
        )
    }

    public func evaluations(for ideaID: UUID) throws -> [Evaluation] {
        try loadCodableRecords(
            table: "evaluations",
            whereColumn: "idea_id",
            equals: ideaID.uuidString,
            limit: .max,
            as: Evaluation.self
        )
    }

    public func saveConversation(_ conversation: Conversation) throws {
        try saveCodableRecord(
            table: "conversations",
            id: conversation.id,
            payload: conversation,
            createdAt: conversation.createdAt,
            extraColumn: nil
        )
    }

    public func conversations(limit: Int = 100) throws -> [Conversation] {
        try loadCodableRecords(table: "conversations", limit: limit, as: Conversation.self)
    }

    private static func migrate(handle: OpaquePointer) throws {
        let current = try scalarInt(on: handle, sql: "PRAGMA user_version")
        guard current <= schemaVersion else {
            throw PersistenceError.unsupportedSchema(current)
        }
        guard current < schemaVersion else {
            return
        }

        try execute(on: handle, sql: "BEGIN IMMEDIATE TRANSACTION")
        do {
            if current < 1 {
                try execute(
                    on: handle,
                    sql: """
                    CREATE TABLE IF NOT EXISTS ideas (
                        id TEXT PRIMARY KEY NOT NULL,
                        raw_text TEXT NOT NULL,
                        ai_title TEXT,
                        created_at REAL NOT NULL,
                        updated_at REAL NOT NULL,
                        status TEXT NOT NULL,
                        source TEXT NOT NULL,
                        tags_json TEXT NOT NULL DEFAULT '[]',
                        archived_at REAL
                    );
                    CREATE INDEX IF NOT EXISTS ideas_created_at_idx ON ideas(created_at DESC);
                    CREATE INDEX IF NOT EXISTS ideas_status_idx ON ideas(status);

                    CREATE TABLE IF NOT EXISTS summaries (
                        id TEXT PRIMARY KEY NOT NULL,
                        payload_json TEXT NOT NULL,
                        source_idea_ids TEXT NOT NULL,
                        created_at REAL NOT NULL
                    );
                    CREATE INDEX IF NOT EXISTS summaries_created_at_idx ON summaries(created_at DESC);

                    CREATE TABLE IF NOT EXISTS evaluations (
                        id TEXT PRIMARY KEY NOT NULL,
                        payload_json TEXT NOT NULL,
                        idea_id TEXT NOT NULL,
                        created_at REAL NOT NULL,
                        FOREIGN KEY(idea_id) REFERENCES ideas(id) ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS evaluations_idea_id_idx ON evaluations(idea_id, created_at DESC);

                    CREATE TABLE IF NOT EXISTS conversations (
                        id TEXT PRIMARY KEY NOT NULL,
                        payload_json TEXT NOT NULL,
                        created_at REAL NOT NULL
                    );
                    CREATE INDEX IF NOT EXISTS conversations_created_at_idx ON conversations(created_at DESC);

                    PRAGMA user_version = 1;
                    """
                )
            }
            if current < 2 {
                try execute(
                    on: handle,
                    sql: """
                    ALTER TABLE ideas ADD COLUMN ai_topic TEXT;
                    ALTER TABLE ideas ADD COLUMN ai_suggested_tags_json TEXT NOT NULL DEFAULT '[]';
                    ALTER TABLE ideas ADD COLUMN ai_annotation_model TEXT;
                    ALTER TABLE ideas ADD COLUMN ai_annotation_prompt_version TEXT;
                    ALTER TABLE ideas ADD COLUMN ai_annotated_at REAL;
                    PRAGMA user_version = 2;
                    """
                )
            }
            try execute(on: handle, sql: "COMMIT")
        } catch {
            try? execute(on: handle, sql: "ROLLBACK")
            throw error
        }
    }

    private static func execute(on handle: OpaquePointer, sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorPointer)
        guard result == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(handle))
            sqlite3_free(errorPointer)
            throw PersistenceError.stepFailed(message)
        }
    }

    private static func scalarInt(on handle: OpaquePointer, sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw PersistenceError.prepareFailed(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw PersistenceError.stepFailed(String(cString: sqlite3_errmsg(handle)))
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else {
            throw PersistenceError.openFailed("数据库已经关闭")
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw PersistenceError.prepareFailed(String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    private enum SQLiteValue {
        case text(String)
        case int64(Int64)
        case double(Double)
        case null
    }

    private func bind(_ value: SQLiteValue, at index: Int32, in statement: OpaquePointer) throws {
        let result: Int32
        switch value {
        case .text(let text):
            result = sqlite3_bind_text(statement, index, text, -1, Self.sqliteTransient)
        case .int64(let number):
            result = sqlite3_bind_int64(statement, index, number)
        case .double(let number):
            result = sqlite3_bind_double(statement, index, number)
        case .null:
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else {
            throw PersistenceError.bindFailed(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func bind(_ value: String?, at index: Int32, in statement: OpaquePointer) throws {
        try bind(value.map(SQLiteValue.text) ?? .null, at: index, in: statement)
    }

    private func bind(_ value: Double?, at index: Int32, in statement: OpaquePointer) throws {
        try bind(value.map(SQLiteValue.double) ?? .null, at: index, in: statement)
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw stepError()
        }
    }

    private func stepError() -> PersistenceError {
        PersistenceError.stepFailed(
            database.map { String(cString: sqlite3_errmsg($0)) } ?? "数据库已经关闭"
        )
    }

    private func decodeIdea(_ statement: OpaquePointer) throws -> Idea {
        guard let idText = columnString(statement, 0),
              let id = UUID(uuidString: idText),
              let rawText = columnString(statement, 1),
              let statusText = columnString(statement, 5),
              let status = IdeaStatus(rawValue: statusText),
              let sourceText = columnString(statement, 6),
              let source = IdeaSource(rawValue: sourceText),
              let tagsJSON = columnString(statement, 7),
              let tagsData = tagsJSON.data(using: .utf8) else {
            throw PersistenceError.invalidRecord("Idea 字段缺失")
        }
        let tags = try decoder.decode([String].self, from: tagsData)
        let suggestedTags: [String]
        if let suggestedJSON = columnString(statement, 10),
           let suggestedData = suggestedJSON.data(using: .utf8) {
            suggestedTags = (try? decoder.decode([String].self, from: suggestedData)) ?? []
        } else {
            suggestedTags = []
        }
        return Idea(
            id: id,
            rawText: rawText,
            aiTitle: columnString(statement, 2),
            aiTopic: columnString(statement, 9),
            aiSuggestedTags: suggestedTags,
            aiAnnotationModel: columnString(statement, 11),
            aiAnnotationPromptVersion: columnString(statement, 12),
            aiAnnotatedAt: sqlite3_column_type(statement, 13) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 13)),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
            status: status,
            source: source,
            tags: tags,
            archivedAt: sqlite3_column_type(statement, 8) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 8))
        )
    }

    private func columnString(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }

    private func saveCodableRecord<T: Encodable>(
        table: String,
        id: UUID,
        payload: T,
        createdAt: Date,
        extraColumn: (name: String, value: String)?
    ) throws {
        let data = try encoder.encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw PersistenceError.invalidRecord("JSON 编码失败")
        }
        let columns = extraColumn == nil
            ? "id, payload_json, created_at"
            : "id, payload_json, \(extraColumn!.name), created_at"
        let placeholders = extraColumn == nil ? "?, ?, ?" : "?, ?, ?, ?"
        let sql = "INSERT OR REPLACE INTO \(table) (\(columns)) VALUES (\(placeholders))"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, at: 1, in: statement)
        try bind(json, at: 2, in: statement)
        if let extraColumn {
            try bind(extraColumn.value, at: 3, in: statement)
            try bind(createdAt.timeIntervalSince1970, at: 4, in: statement)
        } else {
            try bind(createdAt.timeIntervalSince1970, at: 3, in: statement)
        }
        try stepDone(statement)
    }

    private func loadCodableRecords<T: Decodable>(
        table: String,
        whereColumn: String? = nil,
        equals value: String? = nil,
        limit: Int,
        as type: T.Type
    ) throws -> [T] {
        let predicate = whereColumn == nil ? "" : "WHERE \(whereColumn!) = ?"
        let sql = """
        SELECT payload_json FROM \(table)
        \(predicate)
        ORDER BY created_at DESC
        LIMIT ?
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        var index: Int32 = 1
        if let value {
            try bind(value, at: index, in: statement)
            index += 1
        }
        try bind(.int64(limit == .max ? -1 : Int64(max(limit, 1))), at: index, in: statement)

        var records: [T] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let json = columnString(statement, 0),
                      let data = json.data(using: .utf8) else {
                    throw PersistenceError.invalidRecord("JSON 记录缺失")
                }
                records.append(try decoder.decode(T.self, from: data))
            case SQLITE_DONE:
                return records
            default:
                throw stepError()
            }
        }
    }

    private func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func escapeLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private static let sqliteTransient = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )
}

public enum DatabaseBootstrapper {
    public struct Preparation: Equatable, Sendable {
        public var databaseURL: URL
        public var backupURL: URL?

        public init(databaseURL: URL, backupURL: URL?) {
            self.databaseURL = databaseURL
            self.backupURL = backupURL
        }
    }

    public static func openDefaultRepository(
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> SQLiteIdeaRepository {
        let databaseURL = try SQLiteIdeaRepository.defaultDatabaseURL(fileManager: fileManager)
        _ = try prepareDatabase(
            at: databaseURL,
            supportedSchemaVersion: SQLiteIdeaRepository.schemaVersion,
            fileManager: fileManager,
            now: now
        )
        return try SQLiteIdeaRepository(path: databaseURL.path)
    }

    @discardableResult
    public static func prepareDatabase(
        at databaseURL: URL,
        supportedSchemaVersion: Int,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> Preparation {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return Preparation(databaseURL: databaseURL, backupURL: nil)
        }

        let currentVersion = try schemaVersion(at: databaseURL)
        guard currentVersion < supportedSchemaVersion else {
            return Preparation(databaseURL: databaseURL, backupURL: nil)
        }

        let backupDirectory = databaseURL
            .deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: backupDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw PersistenceError.backupFailed(error.localizedDescription)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let basename = "linggangu-pre-migration-v\(currentVersion)-\(formatter.string(from: now))"
        let backupURL = backupDirectory.appendingPathComponent("\(basename).sqlite")

        do {
            try fileManager.copyItem(at: databaseURL, to: backupURL)
            for suffix in ["-wal", "-shm"] {
                let sidecar = URL(fileURLWithPath: databaseURL.path + suffix)
                guard fileManager.fileExists(atPath: sidecar.path) else { continue }
                try fileManager.copyItem(
                    at: sidecar,
                    to: URL(fileURLWithPath: backupURL.path + suffix)
                )
            }
        } catch {
            try? fileManager.removeItem(at: backupURL)
            throw PersistenceError.backupFailed(error.localizedDescription)
        }

        return Preparation(databaseURL: databaseURL, backupURL: backupURL)
    }

    private static func schemaVersion(at databaseURL: URL) throws -> Int {
        var pointer: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &pointer,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let pointer else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) }
                ?? "unknown sqlite error"
            sqlite3_close(pointer)
            throw PersistenceError.openFailed(message)
        }
        defer { sqlite3_close(pointer) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(pointer, "PRAGMA user_version", -1, &statement, nil)
                == SQLITE_OK,
              let statement else {
            throw PersistenceError.prepareFailed(String(cString: sqlite3_errmsg(pointer)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw PersistenceError.stepFailed(String(cString: sqlite3_errmsg(pointer)))
        }
        return Int(sqlite3_column_int(statement, 0))
    }
}

private final class SQLiteHandle: @unchecked Sendable {
    let pointer: OpaquePointer

    init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        sqlite3_close(pointer)
    }
}
