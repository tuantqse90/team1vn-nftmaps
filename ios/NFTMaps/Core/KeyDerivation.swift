import CommonCrypto
import Foundation

/// Sinh private key từ username + password (PBKDF2-HMAC-SHA256).
/// Cùng username + password → cùng ví trên mọi máy, không cần server.
/// Đánh đổi: ai đoán được cặp này là lấy được ví — chỉ dùng cho testnet / demo.
enum KeyDerivation {
    static let iterations: UInt32 = 600_000

    enum Failure: LocalizedError {
        case pbkdf2(Int32)

        var errorDescription: String? {
            switch self {
            case .pbkdf2(let status): "Không sinh được khoá (PBKDF2 lỗi \(status))"
            }
        }
    }

    static func normalizedUsername(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func privateKey(username: String, password: String) throws -> Data {
        let salt = Array("nftmaps-v1:\(normalizedUsername(username))".utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            password, password.utf8.count,
            salt, salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            iterations,
            &derived, derived.count
        )
        guard Int(status) == kCCSuccess else { throw Failure.pbkdf2(status) }
        return Data(derived)
    }
}
