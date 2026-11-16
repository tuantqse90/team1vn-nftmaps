import Foundation
import Observation

/// Phiên đăng nhập: username + password → private key → smart account. Lần sau tự khôi phục từ Keychain.
@MainActor
@Observable
final class WalletSession {
    enum State {
        case restoring
        case signedOut
        case ready(SmartAccount)
    }

    private(set) var state: State = .restoring
    private(set) var username = ""
    private(set) var isSigningIn = false
    var errorMessage: String?

    func restore() async {
        guard let credential = KeychainStore.load() else {
            state = .signedOut
            return
        }
        do {
            try await activate(username: credential.username, privateKey: credential.privateKey)
        } catch {
            errorMessage = error.localizedDescription
            state = .signedOut
        }
    }

    func signIn(username: String, password: String) async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            let name = KeyDerivation.normalizedUsername(username)
            // PBKDF2 600k vòng ~0.5s — chạy ngoài main thread để UI không đứng.
            let privateKey = try await Task.detached(priority: .userInitiated) {
                try KeyDerivation.privateKey(username: name, password: password)
            }.value
            try await activate(username: name, privateKey: privateKey)
            try KeychainStore.save(.init(username: name, privateKey: privateKey))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        KeychainStore.delete()
        username = ""
        state = .signedOut
    }

    private func activate(username: String, privateKey: Data) async throws {
        let account = try await SmartAccount.load(
            owner: try EthereumSigner(privateKey: privateKey),
            rpc: FujiRPC(url: Config.rpcURL),
            factory: try Config.address(Config.accountFactoryAddress, name: "accountFactoryAddress"),
            entryPoint: try Config.address(Config.entryPointAddress, name: "entryPointAddress"),
            chainID: Config.chainID
        )
        self.username = username
        state = .ready(account)
    }
}
