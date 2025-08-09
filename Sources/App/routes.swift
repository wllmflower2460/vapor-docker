import Vapor

// Existing types
struct UploadAck: Content { let sessionID: String }

private struct UploadPayload: Content {
    var video: File              // required
    var imu: File?               // optional
    var meta: String?            // optional (JSON string or plain text)
}

// NEW: Response type for /sessions/:id summary
struct SessionSummary: Content {
    let id: String
    let files: [String: UInt64] // filename -> size (bytes)
}

public func routes(_ app: Application) throws {
    // Health probe
    app.get("healthz") { _ in "ok" }

    // Upload endpoint (multipart)
    app.on(.POST, "sessions", "upload", body: .collect(maxSize: "2gb")) { req async throws -> UploadAck in
        // Decode multipart/form-data into typed fields.
        let payload = try req.content.decode(UploadPayload.self)

        // Where to store files (bind-mounted in Docker run)
        let base = Environment.get("SESSIONS_DIR") ?? "/var/app/sessions"
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)

        let sid = UUID().uuidString
        let sdir = URL(fileURLWithPath: base).appendingPathComponent(sid, isDirectory: true)
        try FileManager.default.createDirectory(at: sdir, withIntermediateDirectories: true)

        // Save required video
        try await req.fileio.writeFile(
            payload.video.data,
            at: sdir.appendingPathComponent("video.mp4").path
        )

        // Save optional imu.json
        if let imu = payload.imu {
            try await req.fileio.writeFile(
                imu.data,
                at: sdir.appendingPathComponent("imu.json").path
            )
        }

        // Save optional meta
        if let meta = payload.meta {
            try Data(meta.utf8).write(to: sdir.appendingPathComponent("meta.json"))
        }

        return UploadAck(sessionID: sid)
    }

    // NEW: List all session IDs (directories) under SESSIONS_DIR
    app.get("sessions") { req async throws -> [String] in
        let base = Environment.get("SESSIONS_DIR") ?? "/var/app/sessions"
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(atPath: base)) ?? []
        var ids: [String] = []
        for item in items {
            var isDir: ObjCBool = false
            let path = (base as NSString).appendingPathComponent(item)
            if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                ids.append(item)
            }
        }
        return ids.sorted()
    }

    // NEW: Quick summary of a session's files
    app.get("sessions", ":id") { req async throws -> SessionSummary in
        let base = Environment.get("SESSIONS_DIR") ?? "/var/app/sessions"
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        let sdir = URL(fileURLWithPath: base).appendingPathComponent(id, isDirectory: true)

        var out: [String: UInt64] = [:]
        for name in ["video.mp4", "imu.json", "meta.json", "results.json"] {
            let p = sdir.appendingPathComponent(name)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: p.path),
               let size = attrs[.size] as? UInt64 {
                out[name] = size
            }
        }
        return SessionSummary(id: id, files: out)
    }

    // NEW: Stream results.json (404 if not present)
    app.get("sessions", ":id", "results") { req async throws -> Response in
        let base = Environment.get("SESSIONS_DIR") ?? "/var/app/sessions"
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        let p = URL(fileURLWithPath: base).appendingPathComponent(id).appendingPathComponent("results.json")
        guard FileManager.default.fileExists(atPath: p.path) else { throw Abort(.notFound) }

        let data = try Data(contentsOf: p)
        var res = Response(status: .ok)
        res.headers.contentType = .json
        res.body = .init(data: data)
        return res
    }
}
