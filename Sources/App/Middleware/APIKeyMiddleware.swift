import Vapor

/// Checks `X-API-Key` header against env `API_KEY`.
/// If `API_KEY` is unset/empty, this middleware is a no-op (allows all).
struct APIKeyMiddleware: AsyncMiddleware {
    func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let required = Environment.get("API_KEY")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !required.isEmpty else {
            // No key configured ? do not enforce
            return try await next.respond(to: req)
        }
        guard let got = req.headers.first(name: "X-API-Key"), got == required else {
            throw Abort(.unauthorized, reason: "Missing or invalid X-API-Key")
        }
        return try await next.respond(to: req)
    }
}
