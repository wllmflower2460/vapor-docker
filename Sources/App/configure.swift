import Foundation
import Fluent
import FluentSQLiteDriver
import Vapor

/// A description
/// - Parameter app:
/// - Throws:
public func configure(_ app: Application) throws {
    // Accept large uploads
    app.routes.defaultMaxBodySize = "2gb"

    // Listen on all interfaces (Docker)
    app.http.server.configuration.hostname = "0.0.0.0"
    app.http.server.configuration.port = 8080

    // Middleware
    app.middleware.use(TimingMiddleware())
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    app.middleware.use(ErrorMiddleware.default(environment: app.environment))
    app.logger.logLevel = .info // Set log level to info
    app.middleware.use(AccessLogMiddleware()) // Log each request

    // SQLite lives in the bind-mounted sessions dir
    let sessionsDir = Environment.get("SESSIONS_DIR") ?? "/var/app/sessions"
    try FileManager.default.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true, attributes: nil)

    let dbPath = sessionsDir + "/app.db"
    app.databases.use(.sqlite(.file(dbPath)), as: .sqlite)
    app.logger.info("SQLite path: \(dbPath)")

    // Migrations
    app.migrations.add(CreateTodo())

    // Run migrations on startup
    try app.autoMigrate().wait()

    // Routes
    try routes(app)
}
