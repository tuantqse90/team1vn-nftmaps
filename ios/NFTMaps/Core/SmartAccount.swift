import Foundation

/// Smart account (MapAccount) của user. Địa chỉ tính trước từ factory theo owner;
/// contract chỉ thực sự được deploy ở UserOperation đầu tiên (qua initCode).
struct SmartAccount: Sendable {
    let owner: EthereumSigner
    let address: Address
    let rpc: FujiRPC
    let factory: Address
    let entryPoint: Address
    let chainID: UInt64

    static func load(
        owner: EthereumSigner,
        rpc: FujiRPC,
        factory: Address,
        entryPoint: Address,
        chainID: UInt64
    ) async throws -> SmartAccount {
        let result = try await rpc.call(to: factory, data: ABI.call(ABI.Selector.getAddress, [.address(owner.address)]))
        return SmartAccount(
            owner: owner,
            address: try ABIDecoder(data: result).address(at: 0),
            rpc: rpc,
            factory: factory,
            entryPoint: entryPoint,
            chainID: chainID
        )
    }

    /// Dựng UserOperation gọi `target` qua `MapAccount.execute` — chưa có gas, paymaster, chữ ký thật.
    func buildUserOperation(target: Address, value: UInt64 = 0, data: Data) async throws -> UserOperation {
        async let codeResult = rpc.code(at: address)
        async let nonceResult = rpc.call(
            to: entryPoint,
            data: ABI.call(ABI.Selector.getNonce, [.address(address), .uint(0)])
        )

        var operation = UserOperation(
            sender: address,
            nonce: try ABIDecoder(data: try await nonceResult).uint64(at: 0),
            callData: ABI.call(ABI.Selector.execute, [.address(target), .uint(value), .bytes(data)])
        )
        if try await codeResult.isEmpty {
            operation.factory = factory
            operation.factoryData = ABI.call(ABI.Selector.createAccount, [.address(owner.address)])
        }
        return operation
    }

    func sign(_ operation: UserOperation) throws -> UserOperation {
        var operation = operation
        operation.signature = try owner.sign(digest: operation.hash(chainID: chainID, entryPoint: entryPoint))
        return operation
    }
}
