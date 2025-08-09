// APIKeyMiddleware.swift
// created by  Will on 8/9/25


import Vapor

/// Checks `X-API-Key` header against env `API_KEY`.
/// - Supports multiple keys if `API_KEY="k1,k2,k3"`.
/// - If `API_KEY` is unset/empty, middleware is a no-op (allows all) — handy for dev.
struct APIKeyMiddleware: AsyncMiddleware {
    private let header = HTTPHeaders.Name("X-API-Key")
    private let allowed: Set<String>

    init(_ env: Environment = .detect()) {
        // Cache once: split on commas, trim whitespace, drop empties
        let raw = Environment.get("API_KEY") ?? ""
        self.allowed = Set(
            raw.split(separator: ",")
               .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
               .filter { !$0.isEmpty }
        )
    }

    func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // No key configured? allow (dev-friendly). Consider failing closed in prod.
        guard !allowed.isEmpty else {
            req.logger.debug("APIKeyMiddleware: API_KEY not set; allowing request")
            return try await next.respond(to: req)
        }

        guard let provided = req.headers.first(name: header),
              allowed.contains(provided) else {
            req.logger.info("APIKeyMiddleware: missing/invalid key for \(req.method) \(req.url.path)")
            throw Abort(.unauthorized, reason: "Missing or invalid X-API-Key")
        }

        return try await next.respond(to: req)
    }
}
