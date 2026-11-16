import Foundation

/// Keccak-256 (bản gốc của Ethereum, padding 0x01 — khác SHA3-256 chuẩn NIST).
enum Keccak256 {
    static func hash(_ data: Data) -> Data {
        let rate = 136
        var message = [UInt8](data)
        message.append(0x01)
        while !message.count.isMultiple(of: rate) {
            message.append(0x00)
        }
        message[message.count - 1] |= 0x80

        var state = [UInt64](repeating: 0, count: 25)
        for blockStart in stride(from: 0, to: message.count, by: rate) {
            for lane in 0..<(rate / 8) {
                var value: UInt64 = 0
                for byte in 0..<8 {
                    value |= UInt64(message[blockStart + lane * 8 + byte]) << (8 * byte)
                }
                state[lane] ^= value
            }
            permute(&state)
        }

        var output: [UInt8] = []
        output.reserveCapacity(32)
        for lane in 0..<4 {
            for byte in 0..<8 {
                output.append(UInt8(truncatingIfNeeded: state[lane] >> (8 * byte)))
            }
        }
        return Data(output)
    }

    static func hash(_ string: String) -> Data {
        hash(Data(string.utf8))
    }

    private static let roundConstants: [UInt64] = [
        0x0000_0000_0000_0001, 0x0000_0000_0000_8082, 0x8000_0000_0000_808A, 0x8000_0000_8000_8000,
        0x0000_0000_0000_808B, 0x0000_0000_8000_0001, 0x8000_0000_8000_8081, 0x8000_0000_0000_8009,
        0x0000_0000_0000_008A, 0x0000_0000_0000_0088, 0x0000_0000_8000_8009, 0x0000_0000_8000_000A,
        0x0000_0000_8000_808B, 0x8000_0000_0000_008B, 0x8000_0000_0000_8089, 0x8000_0000_0000_8003,
        0x8000_0000_0000_8002, 0x8000_0000_0000_0080, 0x0000_0000_0000_800A, 0x8000_0000_8000_000A,
        0x8000_0000_8000_8081, 0x8000_0000_0000_8080, 0x0000_0000_8000_0001, 0x8000_0000_8000_8008,
    ]
    private static let rotations = [1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44]
    private static let piLanes = [10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1]

    private static func rotl(_ x: UInt64, _ n: Int) -> UInt64 {
        (x << UInt64(n)) | (x >> UInt64(64 - n))
    }

    private static func permute(_ state: inout [UInt64]) {
        var column = [UInt64](repeating: 0, count: 5)
        for round in 0..<24 {
            // θ
            for i in 0..<5 {
                column[i] = state[i] ^ state[i + 5] ^ state[i + 10] ^ state[i + 15] ^ state[i + 20]
            }
            for i in 0..<5 {
                let t = column[(i + 4) % 5] ^ rotl(column[(i + 1) % 5], 1)
                for j in stride(from: 0, to: 25, by: 5) {
                    state[j + i] ^= t
                }
            }
            // ρ + π
            var current = state[1]
            for i in 0..<24 {
                let lane = piLanes[i]
                let next = state[lane]
                state[lane] = rotl(current, rotations[i])
                current = next
            }
            // χ
            for j in stride(from: 0, to: 25, by: 5) {
                for i in 0..<5 {
                    column[i] = state[j + i]
                }
                for i in 0..<5 {
                    state[j + i] ^= ~column[(i + 1) % 5] & column[(i + 2) % 5]
                }
            }
            // ι
            state[0] ^= roundConstants[round]
        }
    }
}
