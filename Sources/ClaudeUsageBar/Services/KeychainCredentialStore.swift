import Foundation
import Security

protocol CredentialStore {
    func readCredential() throws -> OAuthCredential
}

enum CredentialStoreError: Error, Equatable {
    case notFound
    case unreadable(OSStatus)
    case parsing(CredentialParsingError)
}

struct KeychainCredentialStore: CredentialStore {
    static let serviceName = "Claude Code-credentials"

    func readCredential() throws -> OAuthCredential {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            throw CredentialStoreError.notFound
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CredentialStoreError.unreadable(status)
        }

        do {
            return try parseCredentialData(data)
        } catch let error as CredentialParsingError {
            throw CredentialStoreError.parsing(error)
        }
    }
}
