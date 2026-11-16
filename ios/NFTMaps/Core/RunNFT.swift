import Foundation

/// Một vòng chạy đã mint (contract RunNFT). Chỉ có hình vòng chạy và khu vực ~1 km, không có toạ độ thật.
struct RunToken: Identifiable, Hashable, Codable, Sendable {
    let id: UInt64
    let owner: Address
    let meters: Int
    let steps: Int
    let duration: Int
    let finishedAt: Date
    let area: RunArea
    let name: String
}

struct RunNFTReader: Sendable {
    let rpc: FujiRPC
    let contract: Address

    func totalSupply() async throws -> UInt64 {
        try ABIDecoder(data: try await rpc.call(to: contract, data: ABI.call(ABI.Selector.totalSupply))).uint64(at: 0)
    }

    /// `runOf` → (uint32 distanceMeters, uint32 steps, uint32 durationSeconds, uint64 finishedAt, int16 areaLat, int16 areaLng, string name)
    func run(id: UInt64) async throws -> RunToken {
        async let runResult = rpc.call(to: contract, data: ABI.call(ABI.Selector.runOf, [.uint(id)]))
        async let ownerResult = rpc.call(to: contract, data: ABI.call(ABI.Selector.ownerOf, [.uint(id)]))
        let run = ABIDecoder(data: try await runResult)
        let owner = ABIDecoder(data: try await ownerResult)
        return RunToken(
            id: id,
            owner: try owner.address(at: 0),
            meters: Int(try run.uint64(at: 0)),
            steps: Int(try run.uint64(at: 1)),
            duration: Int(try run.uint64(at: 2)),
            finishedAt: Date(timeIntervalSince1970: TimeInterval(try run.uint64(at: 3))),
            area: RunArea(lat: Int16(truncatingIfNeeded: try run.int64(at: 4)),
                          lng: Int16(truncatingIfNeeded: try run.int64(at: 5))),
            name: try run.string(at: 6)
        )
    }

    /// Hình vòng chạy: các cặp (x, y) trên lưới 256×256.
    func route(id: UInt64) async throws -> Data {
        try ABIDecoder(data: try await rpc.call(to: contract, data: ABI.call(ABI.Selector.routeOf, [.uint(id)]))).bytes(at: 0)
    }

    func runs(ids: ClosedRange<UInt64>) async throws -> [RunToken] {
        try await withThrowingTaskGroup(of: RunToken.self) { group in
            for id in ids { group.addTask { try await run(id: id) } }
            var runs: [RunToken] = []
            for try await run in group { runs.append(run) }
            return runs.sorted { $0.id < $1.id }
        }
    }
}

enum RunNFTCall {
    /// Contract chặn tên quá 64 byte, quãng đường < 100 m hoặc nhanh hơn 12 m/s.
    static func mintRun(_ run: RunRecord, name: String) -> Data? {
        guard let shape = run.shape, let area = run.area else { return nil }
        return ABI.call(ABI.Selector.mintRun, [
            .uint(UInt64(max(Int(run.meters), 0))),
            .uint(UInt64(max(run.steps, 0))),
            .uint(UInt64(max(Int(run.duration.rounded()), 1))),
            .int(Int64(area.lat)),
            .int(Int64(area.lng)),
            .string(name),
            .bytes(shape),
        ])
    }
}

extension ABI.Selector {
    // MapNFT
    static let isHidden = Data([0x43, 0xc9, 0xf9, 0x7a])  // isHidden(uint256)
    // RunNFT
    static let mintRun = Data([0x70, 0x4f, 0xee, 0x82])   // mintRun(uint32,uint32,uint32,int16,int16,string,bytes)
    static let runOf = Data([0xd0, 0x0a, 0x1c, 0x74])     // runOf(uint256)
    static let routeOf = Data([0xe8, 0xfc, 0x4d, 0x58])   // routeOf(uint256)
}

extension ABIDecoder {
    /// Số nguyên có dấu nhỏ (int16/int32/int64) — ABI mở rộng dấu ra 32 byte nên đọc 8 byte cuối là đủ.
    func int64(at slot: Int) throws -> Int64 {
        Int64(bitPattern: try uint64Unchecked(at: slot))
    }
}

extension Address: Codable {
    init(from decoder: any Decoder) throws {
        try self.init(try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}
