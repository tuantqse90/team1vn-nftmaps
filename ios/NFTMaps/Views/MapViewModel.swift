import CoreLocation
import Foundation
import Observation

/// Dữ liệu đọc từ chain cho cả app: bé (MapNFT), vòng chạy (RunNFT), bé bị ẩn, độ hiếm.
/// Lưu bản sao trên máy để mất mạng vẫn xem được bản đồ.
@MainActor
@Observable
final class MapViewModel {
    private(set) var tokens: [MapToken] = []
    private(set) var hidden: Set<UInt64> = []
    private(set) var runs: [RunToken] = []
    private(set) var rarities: [UInt64: Rarity] = [:]
    private(set) var blockNumber: UInt64?
    private(set) var status = "Đang kết nối Fuji…"
    private(set) var isLoading = false
    /// Lần tải gần nhất lỗi mạng — đang xem dữ liệu đã lưu.
    private(set) var isOffline = false

    private let rpc = FujiRPC(url: Config.rpcURL)
    /// Ảnh/hình on-chain không bao giờ đổi → cache theo token id; gộp các lần tải trùng nhau.
    private var photoTasks: [UInt64: Task<Data, any Error>] = [:]
    private var routeTasks: [UInt64: Task<Data, any Error>] = [:]

    private struct Snapshot: Codable {
        var tokens: [MapToken]
        var hidden: Set<UInt64>
        var runs: [RunToken]
    }

    init() {
        if let data = try? Data(contentsOf: Self.cacheURL),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            tokens = snapshot.tokens
            hidden = snapshot.hidden
            runs = snapshot.runs
            recomputeRarities()
        }
    }

    /// Bé hiện trên bản đồ (bỏ những bé chủ nuôi đã xin ẩn).
    var visibleTokens: [MapToken] { tokens.filter { !hidden.contains($0.id) } }

    func tokens(ownedBy owner: Address) -> [MapToken] {
        tokens.filter { $0.owner == owner }
    }

    func runs(ownedBy owner: Address) -> [RunToken] {
        runs.filter { $0.owner == owner }
    }

    func rarity(of token: MapToken) -> Rarity { rarities[token.id] ?? .common }

    /// Độ hiếm nếu mint một bé mới ở đây bây giờ.
    func rarityForNewPet(species: PetSpecies, at coordinate: CLLocationCoordinate2D) -> Rarity {
        GameRules.rarity(species: species, at: coordinate, among: tokens)
    }

    /// Bảng xếp hạng khu ~1 km: tổng mét đã mint của từng ví.
    func leaderboard(area: RunArea) -> [(owner: Address, meters: Int, runs: Int)] {
        var totals: [Address: (meters: Int, runs: Int)] = [:]
        for run in runs where run.area == area {
            totals[run.owner, default: (0, 0)].meters += run.meters
            totals[run.owner, default: (0, 0)].runs += 1
        }
        return totals.map { (owner: $0.key, meters: $0.value.meters, runs: $0.value.runs) }
            .sorted { $0.meters > $1.meters }
    }

    func photo(id: UInt64) async throws -> Data {
        if let task = photoTasks[id] { return try await task.value }
        let reader = try reader()
        let task = Task { try await reader.photo(id: id) }
        photoTasks[id] = task
        do {
            return try await task.value
        } catch {
            photoTasks[id] = nil  // lỗi mạng → lần sau thử lại
            throw error
        }
    }

    func route(runID: UInt64) async throws -> Data {
        if let task = routeTasks[runID] { return try await task.value }
        guard let reader = try runReader() else { throw ConfigError.missing("runNFT") }
        let task = Task { try await reader.route(id: runID) }
        routeTasks[runID] = task
        do {
            return try await task.value
        } catch {
            routeTasks[runID] = nil
            throw error
        }
    }

    /// Chỉ tải token mới (id > số đã có); cờ ẩn thì đọc lại hết vì người kiểm duyệt có thể ẩn bất kỳ lúc nào.
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            blockNumber = try await rpc.blockNumber()
            let reader = try reader()
            let total = try await reader.totalSupply()
            // Cache có nhiều token hơn chain (vd. dữ liệu từ chain local cùng địa chỉ contract) → đọc lại từ đầu.
            if total < UInt64(tokens.count) { tokens.removeAll() }
            let known = UInt64(tokens.count)
            if total > known {
                tokens += try await reader.tokens(ids: (known + 1)...total)
                recomputeRarities()
            }
            hidden = await hiddenFlags(contract: reader.contract)
            if let runReader = try runReader() {
                let runTotal = try await runReader.totalSupply()
                if runTotal < UInt64(runs.count) { runs.removeAll() }
                let knownRuns = UInt64(runs.count)
                if runTotal > knownRuns {
                    runs += try await runReader.runs(ids: (knownRuns + 1)...runTotal)
                }
            }
            isOffline = false
            status = tokens.isEmpty ? "Chưa có bé nào, bắt bé đầu tiên đi!" : "\(visibleTokens.count) bé trên bản đồ"
            saveSnapshot()
        } catch let error as URLError {
            isOffline = true
            status = error.localizedDescription
        } catch {
            status = error.localizedDescription
        }
    }

    private func hiddenFlags(contract: Address) async -> Set<UInt64> {
        let ids = tokens.map(\.id)
        let rpc = rpc
        return await withTaskGroup(of: UInt64?.self) { group in
            for id in ids {
                group.addTask {
                    let result = try? await rpc.call(to: contract, data: ABI.call(ABI.Selector.isHidden, [.uint(id)]))
                    guard let result, (try? ABIDecoder(data: result).uint64(at: 0)) == 1 else { return nil }
                    return id
                }
            }
            var hidden: Set<UInt64> = []
            for await id in group { if let id { hidden.insert(id) } }
            return hidden
        }
    }

    /// Độ hiếm của từng bé tính theo các bé mint trước nó.
    private func recomputeRarities() {
        var result: [UInt64: Rarity] = [:]
        for (index, token) in tokens.enumerated() {
            result[token.id] = GameRules.rarity(species: token.species, at: token.coordinate,
                                                among: Array(tokens[..<index]))
        }
        rarities = result
    }

    private func reader() throws -> MapNFTReader {
        MapNFTReader(rpc: rpc, contract: try Config.address(Config.contractAddress, name: "contractAddress"))
    }

    /// nil nếu chưa deploy RunNFT — app vẫn chạy, chỉ thiếu phần vòng chạy on-chain.
    private func runReader() throws -> RunNFTReader? {
        guard !Config.runNFTAddress.isEmpty else { return nil }
        return RunNFTReader(rpc: rpc, contract: try Config.address(Config.runNFTAddress, name: "runNFT"))
    }

    private func saveSnapshot() {
        guard let data = try? JSONEncoder().encode(Snapshot(tokens: tokens, hidden: hidden, runs: runs)) else { return }
        try? FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: Self.cacheURL, options: .atomic)
    }

    private static var cacheURL: URL {
        // Theo cả RPC lẫn contract: chain local (anvil fork) dùng cùng địa chỉ contract với Fuji.
        let host = Config.rpcURL.host() ?? "rpc"
        return URL.cachesDirectory.appending(path: "PawRun/chain-\(host)-\(Config.contractAddress.lowercased()).json")
    }
}
