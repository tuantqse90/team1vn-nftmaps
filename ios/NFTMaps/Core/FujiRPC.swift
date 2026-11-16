import Foundation

/// Các lệnh đọc chain (Avalanche C-Chain / Fuji) app cần.
struct FujiRPC: Sendable {
    let client: JSONRPCClient

    init(url: URL) {
        client = JSONRPCClient(url: url)
    }

    func blockNumber() async throws -> UInt64 {
        try Quantity.parse(await client.request("eth_blockNumber"))
    }

    /// `eth_call` read-only.
    func call(to contract: Address, data: Data) async throws -> Data {
        let hex: String = try await client.request("eth_call", [
            .object(["to": contract.hex, "data": data.hex]),
            .string("latest"),
        ])
        return try Data(hex: hex)
    }

    func code(at address: Address) async throws -> Data {
        let hex: String = try await client.request("eth_getCode", [.string(address.hex), .string("latest")])
        return try Data(hex: hex)
    }
}
