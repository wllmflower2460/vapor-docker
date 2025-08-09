import App
import Vapor

// Detect the environment (development, production, etc.)
var env = try Environment.detect()
// Bootstrap logging from that environment
try LoggingSystem.bootstrap(from: &env)
// Create the Application
let app = Application(env)
defer { app.shutdown() }

// Configure your application (configure.swift)
try configure(app)

// Run the server
try app.run()

