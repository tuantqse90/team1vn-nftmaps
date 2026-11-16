import Foundation

/// Bundler + paymaster của Pimlico. Paymaster trả gas thay user → ví không cần AVAX.
struct PimlicoBundler: Sendable {
    let client: JSONRPCClient
    let entryPoint: Address
    /// Sponsorship policy trên dashboard Pimlico (vd. "sp_..."); nil = không gửi.
    var sponsorshipPolicyID: String?

    enum Failure: LocalizedError {
        case timeout

        var errorDescription: String? { "Hết thời gian chờ giao dịch được xác nhận" }
    }

    struct Receipt: Decodable, Sendable {
        struct TransactionReceipt: Decodable, Sendable {
            let transactionHash: String
        }

        let success: Bool
        let reason: String?
        let receipt: TransactionReceipt
    }

    func gasPrice() async throws -> (maxFeePerGas: UInt64, maxPriorityFeePerGas: UInt64) {
        let prices: GasPrices = try await client.request("pimlico_getUserOperationGasPrice")
        return (try Quantity.parse(prices.fast.maxFeePerGas), try Quantity.parse(prices.fast.maxPriorityFeePerGas))
    }

    /// Xin paymaster tài trợ; kết quả kèm luôn các gas limit đã ước lượng.
    func sponsor(_ operation: UserOperation) async throws -> UserOperation {
        var params: [JSONValue] = [.object(operation.rpcObject), .string(entryPoint.hex)]
        if let sponsorshipPolicyID {
            params.append(.object(["sponsorshipPolicyId": sponsorshipPolicyID]))
        }
        let result: Sponsorship = try await client.request("pm_sponsorUserOperation", params)
        var operation = operation
        operation.callGasLimit = try Quantity.parse(result.callGasLimit)
        operation.verificationGasLimit = try Quantity.parse(result.verificationGasLimit)
        operation.preVerificationGas = try Quantity.parse(result.preVerificationGas)
        operation.paymaster = try Address(result.paymaster)
        operation.paymasterVerificationGasLimit = try Quantity.parse(result.paymasterVerificationGasLimit)
        operation.paymasterPostOpGasLimit = try Quantity.parse(result.paymasterPostOpGasLimit)
        operation.paymasterData = try Data(hex: result.paymasterData)
        return operation
    }

    /// Trả về userOpHash.
    func send(_ operation: UserOperation) async throws -> String {
        try await client.request("eth_sendUserOperation", [.object(operation.rpcObject), .string(entryPoint.hex)])
    }

    func waitForReceipt(userOpHash: String, timeout: Duration = .seconds(90)) async throws -> Receipt {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let receipt: Receipt = try await client.requestOptional("eth_getUserOperationReceipt", [.string(userOpHash)]) {
                return receipt
            }
            try await Task.sleep(for: .seconds(2))
        }
        throw Failure.timeout
    }

    private struct GasPrice: Decodable, Sendable {
        let maxFeePerGas: String
        let maxPriorityFeePerGas: String
    }

    private struct GasPrices: Decodable, Sendable {
        let fast: GasPrice
    }

    private struct Sponsorship: Decodable, Sendable {
        let callGasLimit: String
        let verificationGasLimit: String
        let preVerificationGas: String
        let paymaster: String
        let paymasterVerificationGasLimit: String
        let paymasterPostOpGasLimit: String
        let paymasterData: String
    }
}
