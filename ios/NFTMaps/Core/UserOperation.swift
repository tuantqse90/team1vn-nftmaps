import Foundation

/// UserOperation ERC-4337 cho EntryPoint v0.8, dạng "unpacked" như JSON-RPC của bundler.
struct UserOperation: Sendable {
    var sender: Address
    var nonce: UInt64
    var factory: Address?
    var factoryData = Data()
    var callData: Data
    var callGasLimit: UInt64 = 0
    var verificationGasLimit: UInt64 = 0
    var preVerificationGas: UInt64 = 0
    var maxFeePerGas: UInt64 = 0
    var maxPriorityFeePerGas: UInt64 = 0
    var paymaster: Address?
    var paymasterVerificationGasLimit: UInt64 = 0
    var paymasterPostOpGasLimit: UInt64 = 0
    var paymasterData = Data()
    var signature = UserOperation.dummySignature

    /// Chữ ký giả 65 byte để bundler/paymaster ước lượng gas trước khi ký thật
    /// (không làm ECDSA revert, chỉ khiến validate trả về "sai chữ ký").
    static let dummySignature: Data = Data(repeating: 0xff, count: 15) + Data([0xf0]) + Data(repeating: 0, count: 16)
        + Data([0x7a]) + Data(repeating: 0xaa, count: 31) + Data([0x1c])

    var initCode: Data {
        guard let factory else { return Data() }
        return factory.data + factoryData
    }

    var accountGasLimits: Data {
        ABI.uint128(verificationGasLimit) + ABI.uint128(callGasLimit)
    }

    var gasFees: Data {
        ABI.uint128(maxPriorityFeePerGas) + ABI.uint128(maxFeePerGas)
    }

    var paymasterAndData: Data {
        guard let paymaster else { return Data() }
        return paymaster.data + ABI.uint128(paymasterVerificationGasLimit) + ABI.uint128(paymasterPostOpGasLimit) + paymasterData
    }

    /// userOpHash (EIP-712, EntryPoint v0.8) — bằng đúng `EntryPoint.getUserOpHash(op)`.
    func hash(chainID: UInt64, entryPoint: Address) -> Data {
        let structHash = Keccak256.hash(ABI.encode([
            .bytes32(Self.typeHash),
            .address(sender),
            .uint(nonce),
            .bytes32(Keccak256.hash(initCode)),
            .bytes32(Keccak256.hash(callData)),
            .bytes32(accountGasLimits),
            .uint(preVerificationGas),
            .bytes32(gasFees),
            .bytes32(Keccak256.hash(paymasterAndData)),
        ]))
        let domainSeparator = Keccak256.hash(ABI.encode([
            .bytes32(Self.domainTypeHash),
            .bytes32(Keccak256.hash("ERC4337")),
            .bytes32(Keccak256.hash("1")),
            .uint(chainID),
            .address(entryPoint),
        ]))
        return Keccak256.hash(Data([0x19, 0x01]) + domainSeparator + structHash)
    }

    /// Định dạng JSON-RPC gửi bundler (eth_sendUserOperation, pm_sponsorUserOperation…).
    var rpcObject: [String: String] {
        var object = [
            "sender": sender.hex,
            "nonce": Quantity.hex(nonce),
            "callData": callData.hex,
            "callGasLimit": Quantity.hex(callGasLimit),
            "verificationGasLimit": Quantity.hex(verificationGasLimit),
            "preVerificationGas": Quantity.hex(preVerificationGas),
            "maxFeePerGas": Quantity.hex(maxFeePerGas),
            "maxPriorityFeePerGas": Quantity.hex(maxPriorityFeePerGas),
            "signature": signature.hex,
        ]
        if let factory {
            object["factory"] = factory.hex
            object["factoryData"] = factoryData.hex
        }
        if let paymaster {
            object["paymaster"] = paymaster.hex
            object["paymasterVerificationGasLimit"] = Quantity.hex(paymasterVerificationGasLimit)
            object["paymasterPostOpGasLimit"] = Quantity.hex(paymasterPostOpGasLimit)
            object["paymasterData"] = paymasterData.hex
        }
        return object
    }

    private static let typeHash = Keccak256.hash(
        "PackedUserOperation(address sender,uint256 nonce,bytes initCode,bytes callData,bytes32 accountGasLimits,uint256 preVerificationGas,bytes32 gasFees,bytes paymasterAndData)"
    )
    private static let domainTypeHash = Keccak256.hash(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    )
}
