import Foundation

/// Các kiểu ABI app cần dùng — đủ cho MapNFT, MapAccount, factory và EntryPoint.
enum ABIValue: Sendable {
    case address(Address)
    case uint(UInt64)
    case int(Int64)
    case bytes32(Data)
    case bytes(Data)
    case string(String)
}

enum ABI {
    /// Selector lấy bằng `cast sig "<signature>"`.
    enum Selector {
        // MapNFT
        static let totalSupply = Data([0x18, 0x16, 0x0d, 0xdd])   // totalSupply()
        static let ownerOf = Data([0x63, 0x52, 0x21, 0x1e])       // ownerOf(uint256)
        static let pinOf = Data([0x3d, 0xd2, 0xd1, 0x31])         // pinOf(uint256)
        static let photoOf = Data([0x90, 0x9b, 0x20, 0x37])       // photoOf(uint256)
        static let mint = Data([0x3c, 0xed, 0xcf, 0xed])          // mint(int32,int32,uint8,uint8,string,bytes)
        // MapAccount / MapAccountFactory / EntryPoint
        static let execute = Data([0xb6, 0x1d, 0x27, 0xf6])       // execute(address,uint256,bytes)
        static let createAccount = Data([0x98, 0x59, 0x38, 0x7b]) // createAccount(address)
        static let getAddress = Data([0xae, 0x22, 0xc5, 0x7d])    // getAddress(address)
        static let getNonce = Data([0x35, 0x56, 0x7e, 0x1a])      // getNonce(address,uint192)
    }

    enum DecodeError: LocalizedError {
        case malformed

        var errorDescription: String? { "Dữ liệu ABI trả về không hợp lệ" }
    }

    /// Calldata = selector + abi.encode(values)
    static func call(_ selector: Data, _ values: [ABIValue] = []) -> Data {
        selector + encode(values)
    }

    /// abi.encode(values...) — head/tail như Solidity.
    static func encode(_ values: [ABIValue]) -> Data {
        let headSize = values.count * 32
        var head = Data()
        var tail = Data()
        for value in values {
            switch value {
            case .address(let address):
                head += leftPad(address.data)
            case .uint(let number):
                head += word(number)
            case .int(let number):
                head += Data(repeating: number < 0 ? 0xff : 0x00, count: 24) + UInt64(bitPattern: number).bigEndianData
            case .bytes32(let data):
                precondition(data.count == 32, "bytes32 phải dài 32 byte")
                head += data
            case .bytes(let data):
                head += word(UInt64(headSize + tail.count))
                tail += dynamic(data)
            case .string(let string):
                head += word(UInt64(headSize + tail.count))
                tail += dynamic(Data(string.utf8))
            }
        }
        return head + tail
    }

    /// uint128 big-endian (16 byte) — cho các trường đóng gói của UserOperation.
    static func uint128(_ value: UInt64) -> Data {
        Data(repeating: 0, count: 8) + value.bigEndianData
    }

    private static func word(_ value: UInt64) -> Data {
        Data(repeating: 0, count: 24) + value.bigEndianData
    }

    private static func leftPad(_ data: Data) -> Data {
        Data(repeating: 0, count: 32 - data.count) + data
    }

    private static func dynamic(_ data: Data) -> Data {
        word(UInt64(data.count)) + data + Data(repeating: 0, count: (32 - data.count % 32) % 32)
    }
}

extension UInt64 {
    var bigEndianData: Data {
        withUnsafeBytes(of: bigEndian) { Data($0) }
    }
}

struct ABIDecoder {
    private let bytes: [UInt8]

    init(data: Data) {
        bytes = [UInt8](data)
    }

    func uint64(at slot: Int) throws -> UInt64 {
        let word = try word(at: slot)
        guard word.prefix(24).allSatisfy({ $0 == 0 }) else { throw ABI.DecodeError.malformed }
        return word.suffix(8).reduce(0) { $0 << 8 | UInt64($1) }
    }

    /// 8 byte cuối của word, không kiểm tra phần đầu (dùng cho số có dấu).
    func uint64Unchecked(at slot: Int) throws -> UInt64 {
        try word(at: slot).suffix(8).reduce(0) { $0 << 8 | UInt64($1) }
    }

    func int32(at slot: Int) throws -> Int32 {
        let raw = try word(at: slot).suffix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return Int32(bitPattern: raw)
    }

    func address(at slot: Int) throws -> Address {
        Address(data: Data(try word(at: slot).suffix(20)))
    }

    func string(at slot: Int) throws -> String {
        String(decoding: try bytes(at: slot), as: UTF8.self)
    }

    /// `bytes`/`string` động: head chứa offset, tại offset là độ dài rồi tới dữ liệu.
    func bytes(at slot: Int) throws -> Data {
        let offset = try Int(uint64(at: slot))
        guard offset.isMultiple(of: 32) else { throw ABI.DecodeError.malformed }
        let length = try Int(uint64(at: offset / 32))
        let start = offset + 32
        guard start + length <= bytes.count else { throw ABI.DecodeError.malformed }
        return Data(bytes[start..<start + length])
    }

    private func word(at slot: Int) throws -> ArraySlice<UInt8> {
        let start = slot * 32
        guard start >= 0, start + 32 <= bytes.count else { throw ABI.DecodeError.malformed }
        return bytes[start..<start + 32]
    }
}
