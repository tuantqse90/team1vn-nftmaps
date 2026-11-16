import Foundation

enum Config {
    static let chainID: UInt64 = 43113
    static let explorerURL = URL(string: "https://testnet.snowtrace.io")!

    /// Địa chỉ contract trên Fuji — `scripts/deploy-fuji.sh` tự điền sau khi deploy.
    enum Deployed {
        static let mapNFT = "0x350cb01b077DDD71D81Ecf94E13f1E94C8b048A0"
        static let accountFactory = "0xf5dBBA586FACD6e70b6199E3a5e4f27d57aD3743"
        static let runNFT = "0xfd2786B894a387149Ab132fDdF7Fff483a5FE1de"
    }

    /// EntryPoint v0.8 (ERC-4337) — có sẵn trên Fuji.
    static let entryPointAddress = "0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108"

    // Key đọc từ Info.plist, giá trị lấy từ ios/Config/Local.xcconfig (gitignored) lúc build.

    /// API key Pimlico (https://dashboard.pimlico.io) — bundler + paymaster trả gas thay user.
    static var pimlicoAPIKey: String { override("PIMLICO_API_KEY") ?? info("PimlicoAPIKey") }
    /// Tuỳ chọn: ID sponsorship policy ("sp_...") nếu Pimlico báo "Sponsorship policy ID is required".
    static var pimlicoSponsorshipPolicyID: String { override("PIMLICO_POLICY_ID") ?? info("PimlicoPolicyID") }

    /// NullMaps tự host (dẫn đường đi bộ + tên phường). Thiếu URL hoặc key thì dùng Apple MapKit.
    static var nullMapsURL: URL? {
        let value = override("NULLMAPS_URL") ?? info("NullMapsURL")
        return value.isEmpty ? nil : URL(string: value)
    }
    static var nullMapsAPIKey: String { override("NULLMAPS_API_KEY") ?? info("NullMapsAPIKey") }

    private static func info(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    static var rpcURL: URL {
        override("NFTMAPS_RPC_URL").flatMap(URL.init(string:))
            ?? URL(string: "https://api.avax-test.network/ext/bc/C/rpc")!
    }

    static var contractAddress: String {
        override("NFTMAPS_CONTRACT") ?? Deployed.mapNFT
    }

    static var runNFTAddress: String {
        override("NFTMAPS_RUN_NFT") ?? Deployed.runNFT
    }

    static var accountFactoryAddress: String {
        override("NFTMAPS_FACTORY") ?? Deployed.accountFactory
    }

    static func address(_ value: String, name: String) throws -> Address {
        guard !value.isEmpty else { throw ConfigError.missing(name) }
        return try Address(value)
    }

    static func bundlerURL() throws -> URL {
        if let url = override("NFTMAPS_BUNDLER_URL").flatMap(URL.init(string:)) {
            return url
        }
        guard !pimlicoAPIKey.isEmpty,
              let url = URL(string: "https://api.pimlico.io/v2/\(chainID)/rpc?apikey=\(pimlicoAPIKey)")
        else { throw ConfigError.missing("pimlicoAPIKey") }
        return url
    }

    /// Chỉ bản Debug: trỏ app vào chain local (anvil fork Fuji) qua biến môi trường của scheme hoặc UI test.
    /// Bản Release luôn dùng giá trị ở trên.
    static func override(_ key: String) -> String? {
        #if DEBUG
        guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else { return nil }
        return value
        #else
        return nil
        #endif
    }
}

enum ConfigError: LocalizedError {
    case missing(String)

    var errorDescription: String? {
        switch self {
        case .missing(let name): "Chưa cấu hình \(name) — chạy scripts/deploy-fuji.sh hoặc điền trong Config.swift"
        }
    }
}
