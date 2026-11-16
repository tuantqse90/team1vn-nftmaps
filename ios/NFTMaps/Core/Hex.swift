import Foundation

enum HexError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let value): "Chuỗi hex không hợp lệ: \(value.prefix(20))"
        }
    }
}

extension Data {
    init(hex: String) throws {
        let digits = hex.hasPrefix("0x") ? hex.dropFirst(2) : Substring(hex)
        guard digits.count.isMultiple(of: 2) else { throw HexError.invalid(hex) }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(digits.count / 2)
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            guard let byte = UInt8(digits[index..<next], radix: 16) else { throw HexError.invalid(hex) }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    /// "0x" + hex chữ thường
    var hex: String {
        let digits = Array("0123456789abcdef".utf8)
        var out: [UInt8] = Array("0x".utf8)
        out.reserveCapacity(2 + count * 2)
        for byte in self {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: out, as: UTF8.self)
    }
}

/// Số nguyên dạng "quantity" của JSON-RPC Ethereum ("0x1a").
enum Quantity {
    static func hex(_ value: UInt64) -> String {
        "0x" + String(value, radix: 16)
    }

    static func parse(_ hex: String) throws -> UInt64 {
        guard hex.hasPrefix("0x"), let value = UInt64(hex.dropFirst(2), radix: 16) else {
            throw HexError.invalid(hex)
        }
        return value
    }
}

struct Address: Hashable, Sendable, CustomStringConvertible {
    let data: Data

    init(_ hex: String) throws {
        let data = try Data(hex: hex)
        guard data.count == 20 else { throw HexError.invalid(hex) }
        self.data = data
    }

    init(data: Data) {
        precondition(data.count == 20, "Address phải dài 20 byte")
        self.data = Data(data)
    }

    var hex: String { data.hex }
    var short: String { "\(hex.prefix(6))…\(hex.suffix(4))" }
    var description: String { hex }
}
