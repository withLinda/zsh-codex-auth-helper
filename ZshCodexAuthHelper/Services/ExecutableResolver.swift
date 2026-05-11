import Foundation

struct ExecutableResolver {
    let environmentPath: String
    private let fileExists: (String) -> Bool

    init(
        environmentPath: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        fileExists: @escaping (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.environmentPath = environmentPath
        self.fileExists = fileExists
    }

    func resolve(_ executableName: String) -> String? {
        if executableName.contains("/"), fileExists(executableName) {
            return executableName
        }

        for directory in searchPaths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(executableName).path
            if fileExists(candidate) {
                return candidate
            }
        }

        return nil
    }

    func resolveFromEnvironmentPath(_ executableName: String) -> String? {
        if executableName.contains("/"), fileExists(executableName) {
            return executableName
        }

        for directory in splitPath(environmentPath) {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(executableName).path
            if fileExists(candidate) {
                return candidate
            }
        }

        return nil
    }

    func pathByPrepending(_ directory: String) -> String {
        let environmentParts = splitPath(environmentPath)
        if environmentParts.contains(directory) {
            return environmentPath
        }
        if environmentPath.isEmpty {
            return directory
        }
        return "\(directory):\(environmentPath)"
    }

    private var searchPaths: [String] {
        unique(splitPath(environmentPath) + fallbackPaths)
    }

    private var fallbackPaths: [String] {
        [
            "/Applications/Codex.app/Contents/Resources",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
    }

    private func splitPath(_ path: String) -> [String] {
        path.split(separator: ":").map(String.init).filter { $0.isEmpty == false }
    }

    private func unique(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }
}
