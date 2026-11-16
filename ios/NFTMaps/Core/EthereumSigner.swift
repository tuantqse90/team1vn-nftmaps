import Foundation
import P256K

/// Khoá ECDSA secp256k1 của chủ smart account.
struct EthereumSigner: Sendable {
    let address: Address
    private let privateKey: Data

    init(privateKey: Data) throws {
        let key = try P256K.Recovery.PrivateKey(dataRepresentation: privateKey, format: .uncompressed)
        let publicKey = key.publicKey.dataRepresentation // 0x04 || X || Y
        address = Address(data: Data(Keccak256.hash(Data(publicKey.dropFirst())).suffix(20)))
        self.privateKey = privateKey
    }

    /// Ký thẳng digest 32 byte → r || s || v (v = 27/28), đúng định dạng OpenZeppelin ECDSA nhận.
    func sign(digest: Data) throws -> Data {
        let key = try P256K.Recovery.PrivateKey(dataRepresentation: privateKey)
        let signature = key.signature(for: try HashDigest(Array(digest)))
        let compact = signature.compactRepresentation
        return compact.signature + Data([UInt8(27 + compact.recoveryId)])
    }
}
