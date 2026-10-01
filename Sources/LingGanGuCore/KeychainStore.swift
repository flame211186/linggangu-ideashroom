import Foundation
import Security

public enum KeychainError: Error, Equatable, LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            "Keychain 操作失败：\(status)"
        case .invalidData:
            "Keychain 中的密钥数据无效"
        }
    }
}

public enum APIKeyPresence: Sendable { case present, missing, unavailable }

public protocol APIKeyStoring: Sendable {
    func presence(account: String) async -> APIKeyPresence
    func setAPIKey(_ key: String, account: String) async throws
    func apiKey(account: String) async throws -> String?
    func deleteAPIKey(account: String) async throws
}

public actor KeychainAPIKeyStore: APIKeyStoring {
    public static let defaultService = "com.huomiao.linggangu.api-key"
    private let service: String

    public init(service: String = KeychainAPIKeyStore.defaultService) {
        self.service = service
    }

    public func presence(account: String) -> APIKeyPresence {
        var query = baseQuery(account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // Legacy macOS keychain: prohibit UI; never request kSecReturnData here.
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess { return .present }
        if status == errSecItemNotFound { return .missing }
        return .unavailable
    }

    public func setAPIKey(_ key: String, account: String) throws {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            try deleteAPIKey(account: account)
            return
        }
        let data = Data(normalized.utf8)
        let query = baseQuery(account: account)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(insertStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func apiKey(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return value
    }

    public func deleteAPIKey(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
