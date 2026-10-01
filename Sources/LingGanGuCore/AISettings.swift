import Foundation

public enum AnnotationBackfillChoice: String, Codable, CaseIterable, Sendable {
    case futureOnly
    case recentSevenDays
    case allActive
}

public struct AISettings: Codable, Equatable, Sendable {
    public static let defaultBaseURL = "https://api.openai.com"
    public static let primaryKeychainAccount = "primary"

    public var baseURLString: String
    public var model: String
    public var timeoutSeconds: Double
    public var automaticAnnotationEnabled: Bool
    public var automaticAnnotationEnabledAt: Date?
    public var privacyConsentHost: String?

    public init(
        baseURLString: String = Self.defaultBaseURL,
        model: String = "",
        timeoutSeconds: Double = 45,
        automaticAnnotationEnabled: Bool = false,
        automaticAnnotationEnabledAt: Date? = nil,
        privacyConsentHost: String? = nil
    ) {
        self.baseURLString = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.timeoutSeconds = min(max(timeoutSeconds, 5), 180)
        self.automaticAnnotationEnabled = automaticAnnotationEnabled
        self.automaticAnnotationEnabledAt = automaticAnnotationEnabledAt
        self.privacyConsentHost = privacyConsentHost?.lowercased()
    }

    public var baseURL: URL? {
        URL(string: baseURLString)
    }

    public var normalizedHost: String? {
        baseURL?.host?.lowercased()
    }

    public var isLoopback: Bool {
        guard let host = normalizedHost else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    public var hasPrivacyConsent: Bool {
        normalizedHost != nil && privacyConsentHost == normalizedHost
    }

    public func validatedConfiguration() throws -> AIProviderConfiguration {
        guard let url = baseURL, url.host != nil else {
            throw AIProviderError.invalidConfiguration("Base URL 无效")
        }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw AIProviderError.invalidConfiguration("Base URL 仅支持 HTTP/HTTPS，不能包含账号、密码或查询参数")
        }
        if !isLoopback, url.scheme?.lowercased() != "https" {
            throw AIProviderError.invalidConfiguration("远程 Base URL 必须使用 HTTPS")
        }
        guard !model.isEmpty else {
            throw AIProviderError.invalidConfiguration("模型名称不能为空")
        }
        return AIProviderConfiguration(
            baseURL: url,
            model: model,
            keychainAccount: Self.primaryKeychainAccount,
            timeoutSeconds: timeoutSeconds
        )
    }
}

public protocol AISettingsStoring: Sendable {
    func load() async -> AISettings
    func save(_ settings: AISettings) async throws
}

public actor UserDefaultsAISettingsStore: AISettingsStoring {
    public static let storageKey = "ai.settings.v1"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() -> AISettings {
        guard let data = defaults.data(forKey: Self.storageKey),
              let settings = try? decoder.decode(AISettings.self, from: data) else {
            return AISettings()
        }
        return settings
    }

    public func save(_ settings: AISettings) throws {
        defaults.set(try encoder.encode(settings), forKey: Self.storageKey)
    }
}

public actor InMemoryAISettingsStore: AISettingsStoring {
    private var settings: AISettings

    public init(settings: AISettings = AISettings()) {
        self.settings = settings
    }

    public func load() -> AISettings {
        settings
    }

    public func save(_ settings: AISettings) {
        self.settings = settings
    }
}

public actor InMemoryAPIKeyStore: APIKeyStoring {
    public private(set) var secretReadCount = 0
    private var keys: [String: String] = [:]

    public init() {}

    public func presence(account: String) -> APIKeyPresence {
        keys[account] == nil ? .missing : .present
    }

    public func setAPIKey(_ key: String, account: String) {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            keys.removeValue(forKey: account)
        } else {
            keys[account] = normalized
        }
    }

    public func apiKey(account: String) -> String? {
        secretReadCount += 1
        return keys[account]
    }

    public func deleteAPIKey(account: String) {
        keys.removeValue(forKey: account)
    }
}

public actor AIProviderFactory {
    private let settingsStore: any AISettingsStoring
    private let keyStore: any APIKeyStoring

    public init(
        settingsStore: any AISettingsStoring,
        keyStore: any APIKeyStoring
    ) {
        self.settingsStore = settingsStore
        self.keyStore = keyStore
    }

    public func makeProvider() async throws -> OpenAICompatibleProvider {
        let settings = await settingsStore.load()
        let configuration = try settings.validatedConfiguration()
        let key = try await keyStore.apiKey(account: configuration.keychainAccount) ?? ""
        if key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !settings.isLoopback {
            throw AIProviderError.missingAPIKey
        }
        return try OpenAICompatibleProvider(configuration: configuration, apiKey: key)
    }
}
