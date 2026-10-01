import Foundation

public enum IdeaStatus: String, Codable, CaseIterable, Sendable {
    case inbox
    case clarified
    case candidate
    case testing
    case executed
    case archived

    /// Keep legacy persisted values intact; expose only five user-facing states.
    public static var workflowCases: [IdeaStatus] { [.inbox, .candidate, .testing, .executed, .archived] }
    public var workflowStatus: IdeaStatus { self == .clarified ? .inbox : self }
}

public enum IdeaSource: String, Codable, CaseIterable, Sendable {
    case quickCapture
    case widget
    case workbench
    case imported
}

public struct Idea: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var rawText: String
    public var aiTitle: String?
    public var aiTopic: String?
    public var aiSuggestedTags: [String]
    public var aiAnnotationModel: String?
    public var aiAnnotationPromptVersion: String?
    public var aiAnnotatedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var status: IdeaStatus
    public var source: IdeaSource
    public var tags: [String]
    public var archivedAt: Date?

    public init(
        id: UUID = UUID(),
        rawText: String,
        aiTitle: String? = nil,
        aiTopic: String? = nil,
        aiSuggestedTags: [String] = [],
        aiAnnotationModel: String? = nil,
        aiAnnotationPromptVersion: String? = nil,
        aiAnnotatedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        status: IdeaStatus = .inbox,
        source: IdeaSource = .quickCapture,
        tags: [String] = [],
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.rawText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.aiTitle = aiTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.aiTopic = aiTopic?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.aiSuggestedTags = Self.normalize(tags: aiSuggestedTags)
        self.aiAnnotationModel = aiAnnotationModel
        self.aiAnnotationPromptVersion = aiAnnotationPromptVersion
        self.aiAnnotatedAt = aiAnnotatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.source = source
        self.tags = Self.normalize(tags: tags)
        self.archivedAt = archivedAt
    }

    public var displayTitle: String {
        if let aiTitle, !aiTitle.isEmpty {
            return aiTitle
        }
        return rawText
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? rawText
    }

    public var isValid: Bool {
        !rawText.isEmpty
    }

    public static func normalize(tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { raw in
            let value = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                .lowercased()
            guard !value.isEmpty, seen.insert(value).inserted else {
                return nil
            }
            return value
        }
    }
}

public enum SummaryScope: Codable, Equatable, Sendable {
    case ideaIDs([UUID])
    case dateRange(start: Date, end: Date)
    case tag(String)
    case topic(String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case ideaIDs
        case start
        case end
        case tag
        case topic
    }

    private enum Kind: String, Codable {
        case ideaIDs
        case dateRange
        case tag
        case topic
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .ideaIDs:
            self = .ideaIDs(try container.decode([UUID].self, forKey: .ideaIDs))
        case .dateRange:
            self = .dateRange(
                start: try container.decode(Date.self, forKey: .start),
                end: try container.decode(Date.self, forKey: .end)
            )
        case .tag:
            self = .tag(try container.decode(String.self, forKey: .tag))
        case .topic:
            self = .topic(try container.decode(String.self, forKey: .topic))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ideaIDs(let ideaIDs):
            try container.encode(Kind.ideaIDs, forKey: .kind)
            try container.encode(ideaIDs, forKey: .ideaIDs)
        case .dateRange(let start, let end):
            try container.encode(Kind.dateRange, forKey: .kind)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
        case .tag(let tag):
            try container.encode(Kind.tag, forKey: .kind)
            try container.encode(tag, forKey: .tag)
        case .topic(let topic):
            try container.encode(Kind.topic, forKey: .kind)
            try container.encode(topic, forKey: .topic)
        }
    }
}

public struct SummaryContent: Codable, Equatable, Sendable {
    public var themes: [String]
    public var repeatedDirections: [String]
    public var newDirections: [String]
    public var contradictions: [String]
    public var openQuestions: [String]
    public var mergeSuggestions: [String]
    public var actions: [String]

    public init(
        themes: [String] = [],
        repeatedDirections: [String] = [],
        newDirections: [String] = [],
        contradictions: [String] = [],
        openQuestions: [String] = [],
        mergeSuggestions: [String] = [],
        actions: [String] = []
    ) {
        self.themes = themes
        self.repeatedDirections = repeatedDirections
        self.newDirections = newDirections
        self.contradictions = contradictions
        self.openQuestions = openQuestions
        self.mergeSuggestions = mergeSuggestions
        self.actions = actions
    }
}

public struct Summary: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var scope: SummaryScope
    public var content: SummaryContent
    public var sourceIdeaIDs: [UUID]
    public var model: String
    public var promptVersion: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        scope: SummaryScope,
        content: SummaryContent,
        sourceIdeaIDs: [UUID],
        model: String,
        promptVersion: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.scope = scope
        self.content = content
        self.sourceIdeaIDs = sourceIdeaIDs
        self.model = model
        self.promptVersion = promptVersion
        self.createdAt = createdAt
    }
}

public enum InvestmentVerdict: String, Codable, CaseIterable, Sendable {
    case validateNow
    case observe
    case archive

    public var localizedName: String {
        switch self {
        case .validateNow: "立即验证"
        case .observe: "继续观察"
        case .archive: "暂时归档"
        }
    }
}

public struct EvaluationScores: Codable, Equatable, Sendable {
    public var painSeverity: Int
    public var willingnessToPay: Int
    public var differentiation: Int
    public var founderFit: Int
    public var validationEase: Int

    public init(
        painSeverity: Int,
        willingnessToPay: Int,
        differentiation: Int,
        founderFit: Int,
        validationEase: Int
    ) {
        self.painSeverity = Self.clamp(painSeverity)
        self.willingnessToPay = Self.clamp(willingnessToPay)
        self.differentiation = Self.clamp(differentiation)
        self.founderFit = Self.clamp(founderFit)
        self.validationEase = Self.clamp(validationEase)
    }

    public var average: Double {
        let total = painSeverity + willingnessToPay + differentiation + founderFit + validationEase
        return Double(total) / 5.0
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, 0), 5)
    }
}

public struct Evaluation: Identifiable, Codable, Equatable, Sendable {
    public var supportingArguments: [String]?
    public var opposingArguments: [String]?
    public var distributionPlan: String?
    public var sourceRawText: String?
    public var schemaVersion: Int?
    public var id: UUID
    public var ideaID: UUID
    public var verdict: InvestmentVerdict
    public var scores: EvaluationScores
    public var targetUser: String
    public var rationale: [String]
    public var risks: [String]
    public var missingEvidence: [String]
    public var confidence: Double
    public var smallestExperiment: String
    public var model: String
    public var promptVersion: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        ideaID: UUID,
        verdict: InvestmentVerdict,
        scores: EvaluationScores,
        targetUser: String,
        rationale: [String],
        risks: [String],
        missingEvidence: [String],
        confidence: Double,
        smallestExperiment: String,
        model: String,
        promptVersion: String,
        createdAt: Date = Date(),
        supportingArguments: [String]? = nil,
        opposingArguments: [String]? = nil,
        distributionPlan: String? = nil,
        sourceRawText: String? = nil,
        schemaVersion: Int? = 2
    ) {
        self.supportingArguments = supportingArguments
        self.opposingArguments = opposingArguments
        self.distributionPlan = distributionPlan
        self.sourceRawText = sourceRawText
        self.schemaVersion = schemaVersion
        self.id = id
        self.ideaID = ideaID
        self.verdict = verdict
        self.scores = scores
        self.targetUser = targetUser
        self.rationale = rationale
        self.risks = risks
        self.missingEvidence = missingEvidence
        self.confidence = min(max(confidence, 0), 1)
        self.smallestExperiment = smallestExperiment
        self.model = model
        self.promptVersion = promptVersion
        self.createdAt = createdAt
    }
}

public enum ConversationRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

public enum ConversationDeliveryState: String, Codable, Sendable {
    case complete
    case stopped
}

public struct ConversationMessage: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var role: ConversationRole
    public var content: String
    public var createdAt: Date
    public var sourceIdeaIDs: [UUID]
    public var model: String?
    public var promptVersion: String?
    public var deliveryState: ConversationDeliveryState

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case createdAt
        case sourceIdeaIDs
        case model
        case promptVersion
        case deliveryState
    }

    public init(
        id: UUID = UUID(),
        role: ConversationRole,
        content: String,
        createdAt: Date = Date(),
        sourceIdeaIDs: [UUID] = [],
        model: String? = nil,
        promptVersion: String? = nil,
        deliveryState: ConversationDeliveryState = .complete
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.sourceIdeaIDs = sourceIdeaIDs
        self.model = model
        self.promptVersion = promptVersion
        self.deliveryState = deliveryState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(ConversationRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sourceIdeaIDs = try container.decodeIfPresent([UUID].self, forKey: .sourceIdeaIDs) ?? []
        model = try container.decodeIfPresent(String.self, forKey: .model)
        promptVersion = try container.decodeIfPresent(String.self, forKey: .promptVersion)
        deliveryState = try container.decodeIfPresent(
            ConversationDeliveryState.self,
            forKey: .deliveryState
        ) ?? .complete
    }
}

public struct Conversation: Identifiable, Codable, Equatable, Sendable {
    public var evaluationID: UUID? = nil
    public var id: UUID
    public var title: String
    public var scopeIdeaIDs: [UUID]
    public var messages: [ConversationMessage]
    public var model: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        scopeIdeaIDs: [UUID],
        messages: [ConversationMessage] = [],
        model: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.scopeIdeaIDs = scopeIdeaIDs
        self.messages = messages
        self.model = model
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
