import Foundation

/// Tuist includes all methods to interact with your tuist project
public enum Tuist {
    enum TuistError: Error {
        case signalled(command: String, code: Int32, standardError: Data)
        case terminated(command: String, code: Int32, standardError: Data)

        public var description: String {
            switch self {
            case let .signalled(command, code, data):
                if data.count > 0, let string = String(data: data, encoding: .utf8) {
                    return "The '\(command)' was interrupted with a signal \(code) and message:\n\(string)"
                } else {
                    return "The '\(command)' was interrupted with a signal \(code)"
                }
            case let .terminated(command, code, data):
                if data.count > 0, let string = String(data: data, encoding: .utf8) {
                    return "The '\(command)' command exited with error code \(code) and message:\n\(string)"
                } else {
                    return "The '\(command)' command exited with error code \(code)"
                }
            }
        }
    }

    /// Loads and returns the graph at the given path.
    /// - parameter path: the path which graph should be loaded. If nil, the current path is used.
    /// - parameter environmentKeys: the environment keys that should be copied. If empty, no environment variables will be
    /// passed.
    public static func graph(at path: String? = nil, environmentKeys: Set<String> = []) throws -> Graph {
        // If a task is executed via `tuist`, it gets passed the binary path as a last argument.
        // Otherwise, fallback to go
        let tuistBinaryPath = ProcessInfo.processInfo.environment["TUIST_CONFIG_BINARY_PATH"] ?? "tuist"
        let temporaryDirectory = try createTemporaryDirectory()

        do {
            let graphPath = temporaryDirectory.appendingPathComponent("graph.json")
            var arguments = [
                "graph",
                "--format", "json",
                "--output-path", temporaryDirectory.path,
            ]
            if let path {
                arguments += ["--path", path]
            }
            let forceConfigCacheDirectory = "TUIST_CONFIG_FORCE_CONFIG_CACHE_DIRECTORY"
            var environment: [String: String] = [:]
            for environmentKey in environmentKeys + [forceConfigCacheDirectory] {
                if let value = ProcessInfo.processInfo.environment[environmentKey], !value.isEmpty {
                    environment[environmentKey] = value
                }
            }
            try run(
                tuistBinaryPath,
                arguments,
                environment: environment
            )
            let graphData = try Data(contentsOf: graphPath)
            return try JSONDecoder().decode(Graph.self, from: graphData)
        } catch {
            try FileManager.default.removeItem(at: temporaryDirectory)
            throw error
        }
    }

    private static func createTemporaryDirectory() throws -> URL {
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        let temporaryFolderURL = temporaryDirectoryURL.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryFolderURL, withIntermediateDirectories: true, attributes: nil)
        return temporaryFolderURL
    }

    private static func run(
        _ launchPath: String,
        _ arguments: [String],
        environment _: [String: String]
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        var command = [launchPath]
        command.append(contentsOf: arguments)

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            throw Tuist.TuistError.terminated(
                command: command.joined(separator: ""),
                code: process.terminationStatus,
                standardError: errorData
            )
        }
    }
}
