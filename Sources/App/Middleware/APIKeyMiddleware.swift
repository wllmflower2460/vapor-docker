// APIKeyMiddleware.swift
// created by  Will on 8/9/25

import Vapor

/// Checks `X-API-Key` header against env `API_KEY`.
/// - Supports multiple keys if `API_KEY="k1,k2,k3"`.
/// - If `API_KEY` is unset/empty, middleware is a no-op (allows all) — handy for dev.
struct APIKeyMiddleware: AsyncMiddleware {
    private let keys: Set<String>

    // Primary init: no throwing default
    init(_ env: Environment = .production) {
        let raw = Environment.get("API_KEY") ?? ""
        self.keys = Set(
            raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    // Optional: convenience throwing init for callers that want detect()
    init(detecting env: Environment) {
        self.init(env)
    }

    // If you really want an auto-detecting initializer:
    static func detected() throws -> APIKeyMiddleware {
        try APIKeyMiddleware(Environment.detect())
    }

    func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let header = req.headers.first(name: "X-API-Key") ?? ""
        guard keys.contains(header), !keys.isEmpty else {
            throw Abort(.unauthorized)
        }
        return try await next.respond(to: req)
    }
}
