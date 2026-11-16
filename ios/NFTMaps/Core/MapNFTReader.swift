import CoreLocation

struct MapToken: Identifiable, Hashable, Codable, Sendable {
    let id: UInt64
    let owner: Address
    let latitude: Double
    let longitude: Double
    let species: PetSpecies
    /// % độ tin cậy của model lúc mint, 0...100
    let confidence: Int
    let name: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Đọc dữ liệu NFT từ contract MapNFT (read-only, không cần ví).
struct MapNFTReader: Sendable {
    let rpc: FujiRPC
    let contract: Address

    func totalSupply() async throws -> UInt64 {
        let result = try await rpc.call(to: contract, data: ABI.call(ABI.Selector.totalSupply))
        return try ABIDecoder(data: result).uint64(at: 0)
    }

    /// Thông tin ghim trên bản đồ — không kèm ảnh để tải nhanh.
    func token(id: UInt64) async throws -> MapToken {
        async let pinResult = rpc.call(to: contract, data: ABI.call(ABI.Selector.pinOf, [.uint(id)]))
        async let ownerResult = rpc.call(to: contract, data: ABI.call(ABI.Selector.ownerOf, [.uint(id)]))

        // pinOf → (int32 lat, int32 lng, uint8 species, uint8 confidence, string name)
        let pin = ABIDecoder(data: try await pinResult)
        let owner = ABIDecoder(data: try await ownerResult)
        guard let species = PetSpecies(rawValue: UInt8(truncatingIfNeeded: try pin.uint64(at: 2))) else {
            throw ABI.DecodeError.malformed
        }
        return MapToken(
            id: id,
            owner: try owner.address(at: 0),
            latitude: Double(try pin.int32(at: 0)) / 1e6,
            longitude: Double(try pin.int32(at: 1)) / 1e6,
            species: species,
            confidence: Int(try pin.uint64(at: 3)),
            name: try pin.string(at: 4)
        )
    }

    /// Ảnh JPEG lưu on-chain của token.
    func photo(id: UInt64) async throws -> Data {
        let result = try await rpc.call(to: contract, data: ABI.call(ABI.Selector.photoOf, [.uint(id)]))
        return try ABIDecoder(data: result).bytes(at: 0)
    }

    /// Token id chạy từ 1...totalSupply (contract không có burn).
    func allTokens() async throws -> [MapToken] {
        let count = try await totalSupply()
        guard count > 0 else { return [] }
        return try await tokens(ids: 1...count)
    }

    /// Đọc song song một dải token id, trả về theo thứ tự id.
    func tokens(ids: ClosedRange<UInt64>) async throws -> [MapToken] {
        try await withThrowingTaskGroup(of: MapToken.self) { group in
            for id in ids {
                group.addTask { try await token(id: id) }
            }
            var tokens: [MapToken] = []
            for try await token in group {
                tokens.append(token)
            }
            return tokens.sorted { $0.id < $1.id }
        }
    }
}

/// Calldata ghi vào MapNFT.
enum MapNFTCall {
    /// `mint(int32 lat, int32 lng, uint8 species, uint8 confidence, string name, bytes photo)` — toạ độ × 1e6.
    static func mint(latitude: Double, longitude: Double, detection: PetDetection, name: String, photo: Data) -> Data {
        ABI.call(ABI.Selector.mint, [
            .int(Int64((latitude * 1e6).rounded())),
            .int(Int64((longitude * 1e6).rounded())),
            .uint(UInt64(detection.species.rawValue)),
            .uint(UInt64(detection.confidencePercent)),
            .string(name),
            .bytes(photo),
        ])
    }
}
