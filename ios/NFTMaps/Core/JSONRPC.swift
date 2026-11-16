import Foundation

/// Tham số JSON-RPC — app chỉ cần chuỗi và object chuỗi→chuỗi.
enum JSONValue: Encodable, Sendable {
    case string(String)
    case object([String: String])

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

struct RPCError: LocalizedError, Decodable, Sendable {
    let code: Int
    let message: String

    var errorDescription: String? { "RPC \(code): \(message)" }
}

enum RPCClientError: LocalizedError {
    case badResponse(status: Int, body: String)
    case emptyResult(method: String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let status, let body): "HTTP \(status): \(body)"
        case .emptyResult(let method): "\(method) không trả về kết quả"
        }
    }
}

struct JSONRPCClient: Sendable {
    let url: URL

    func request<Result: Decodable & Sendable>(_ method: String, _ params: [JSONValue] = []) async throws -> Result {
        guard let result: Result = try await requestOptional(method, params) else {
            throw RPCClientError.emptyResult(method: method)
        }
        return result
    }

    /// Như `request` nhưng `result: null` hợp lệ (vd. receipt chưa có).
    func requestOptional<Result: Decodable & Sendable>(_ method: String, _ params: [JSONValue] = []) async throws -> Result? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(method: method, params: params))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let decoded = try? JSONDecoder().decode(Response<Result>.self, from: data) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw RPCClientError.badResponse(status: status, body: String(decoding: data.prefix(300), as: UTF8.self))
        }
        if let error = decoded.error { throw error }
        return decoded.result
    }

    private struct Body: Encodable {
        let jsonrpc = "2.0"
        let id = 1
        let method: String
        let params: [JSONValue]
    }

    private struct Response<Result: Decodable>: Decodable {
        let result: Result?
        let error: RPCError?
    }
}
