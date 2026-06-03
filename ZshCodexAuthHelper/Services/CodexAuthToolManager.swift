import Foundation

enum CodexAuthReleaseChannel: String, CaseIterable, Identifiable {
    case stable
    case next

    init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .stable
    }

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .stable:
            return "Stable"
        case .next:
            return "Next Alpha"
        }
    }

    var detail: String {
        switch self {
        case .stable:
            return "Uses the latest stable npm release."
        case .next:
            return "Uses the newer alpha npm release."
        }
    }

    var npmTag: String {
        switch self {
        case .stable:
            return "latest"
        case .next:
            return "next"
        }
    }

    var packageSpec: String {
        "@loongphy/codex-auth@\(npmTag)"
    }
}

enum CodexAuthToolSettings {
    static let releaseChannelKey = "codexAuthReleaseChannel"
}

struct CodexAuthToolManager {
    typealias VersionRunner = @Sendable (_ executable: String, _ arguments: [String], _ environment: [String: String]) async -> String?

    let toolRoot: URL
    let userDefaults: UserDefaults

    private let isExecutable: (String) -> Bool
    private let versionRunner: VersionRunner

    init(
        applicationSupportDirectory: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support"),
        userDefaults: UserDefaults = .standard,
        isExecutable: @escaping (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        versionRunner: @escaping VersionRunner = { executable, arguments, environment in
            await CodexAuthToolManager.runVersionCommand(
                executable: executable,
                arguments: arguments,
                environment: environment
            )
        }
    ) {
        self.toolRoot = applicationSupportDirectory
            .appendingPathComponent("CodexAuthHelper", isDirectory: true)
            .appendingPathComponent("codex-auth-tool", isDirectory: true)
        self.userDefaults = userDefaults
        self.isExecutable = isExecutable
        self.versionRunner = versionRunner
    }

    static func live() -> CodexAuthToolManager {
        CodexAuthToolManager()
    }

    var managedBinDirectory: URL {
        toolRoot.appendingPathComponent("bin", isDirectory: true)
    }

    var managedExecutablePath: String {
        managedBinDirectory.appendingPathComponent("codex-auth").path
    }

    var selectedChannel: CodexAuthReleaseChannel {
        CodexAuthReleaseChannel(
            storedValue: userDefaults.string(forKey: CodexAuthToolSettings.releaseChannelKey)
        )
    }

    var versionEnvironment: [String: String] {
        [
            "PATH": "\(managedBinDirectory.path):/opt/homebrew/bin"
        ]
    }

    func installedVersion() async -> String? {
        guard isExecutable(managedExecutablePath) else {
            return nil
        }

        return await versionRunner(
            managedExecutablePath,
            ["--version"],
            versionEnvironment
        )?.trimmedNonEmpty
    }

    private static func runVersionCommand(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) async -> String? {
        await Task.detached(priority: .utility) {
            let process = Process()
            let outputPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = mergedEnvironment(overrides: environment)
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            do {
                try process.run()
            } catch {
                return nil
            }

            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return nil
            }

            let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: output, encoding: .utf8)
        }.value
    }

    private static func mergedEnvironment(overrides: [String: String]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in overrides {
            environment[key] = value
        }
        environment["LC_ALL"] = environment["LC_ALL"] ?? "en_US.UTF-8"
        return environment
    }
}
