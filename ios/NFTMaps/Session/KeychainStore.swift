import Foundation
import Security

/// Lưu private key + username vào Keychain (chỉ máy này, chỉ khi máy đã mở khoá).
enum KeychainStore {
    struct Credential: Sendable {
        let username: String
        let privateKey: Data
    }

    enum Failure: LocalizedError {
        case status(OSStatus)

        var errorDescription: String? {
            switch self {
            case .status(let status): "Không lưu được vào Keychain (mã \(status))"
            }
        }
    }

    private static let service = "com.hackbuilder.nftmaps.wallet"

    static func save(_ credential: Credential) throws {
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credential.username,
            kSecValueData as String: credential.privateKey,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.status(status) }
    }

    static func load() -> Credential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let attributes = item as? [String: Any],
              let username = attributes[kSecAttrAccount as String] as? String,
              let privateKey = attributes[kSecValueData as String] as? Data
        else { return nil }
        return Credential(username: username, privateKey: privateKey)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
