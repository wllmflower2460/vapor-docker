import App
import Vapor

// Detect the environment (development, production, etc.)
var env = try Environment.detect()
// Bootstrap logging from that environment
try LoggingSystem.bootstrap(from: &env)
// Load environment variables
try Environment.load(.detect())
// Create the Application
let app = try await Application.make(env)
defer { await app.shutdown() }

// Configure your application (configure.swift)
try await configure(app)

// Run the server
try await app.run()

