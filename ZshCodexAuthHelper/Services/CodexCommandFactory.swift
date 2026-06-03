import Foundation

enum CommandFactoryError: LocalizedError, Equatable {
    case missingExecutable(String)
    case missingNPM
    case missingAuthFilePath
    case missingSwitchQuery
    case missingRemoveSelector

    var errorDescription: String? {
        switch self {
        case .missingExecutable(let name):
            return "Could not find \(name)."
        case .missingNPM:
            return "Could not find npm. Install Node.js and npm, then reopen the app."
        case .missingAuthFilePath:
            return "Add an auth file path before saving."
        case .missingSwitchQuery:
            return "Add an account selector after codex-auth switch before running."
        case .missingRemoveSelector:
            return "Add an account selector after codex-auth remove before running."
        }
    }
}

struct CodexCommandFactory {
    private let resolver: ExecutableResolver
    private let homeDirectory: URL
    private let codexAuthToolManager: CodexAuthToolManager

    init(
        resolver: ExecutableResolver = .init(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        codexAuthToolManager: CodexAuthToolManager = .live()
    ) {
        self.resolver = resolver
        self.homeDirectory = homeDirectory
        self.codexAuthToolManager = codexAuthToolManager
    }

    static func live() -> CodexCommandFactory {
        CodexCommandFactory()
    }

    var defaultAuthFilePath: String {
        homeDirectory.appendingPathComponent(".codex/auth.json").path
    }

    func updateCodexAuth(channel: CodexAuthReleaseChannel) throws -> CommandDefinition {
        guard let executable = resolver.resolve("npm") else {
            throw CommandFactoryError.missingNPM
        }

        let arguments = [
            "install",
            "--global",
            "--prefix",
            codexAuthToolManager.toolRoot.path,
            channel.packageSpec
        ]

        return CommandDefinition(
            id: "update-codex-auth",
            title: "Update codex-auth",
            systemImage: "arrow.down.circle",
            executable: executable,
            arguments: arguments,
            environment: codexAuthEnvironment(),
            displayCommand: ShellQuoting.displayCommand(executable: "npm", arguments: arguments)
        )
    }

    func login(codexResourceDirectory: String = CodexResourceSettings.defaultDirectory) throws -> CommandDefinition {
        let resourceDirectory = CodexResourceSettings.normalizedDirectory(codexResourceDirectory)
        let executable = try codexAuthExecutable()
        let arguments = ["login", "--device-auth"]

        return CommandDefinition(
            id: "login",
            title: "Login",
            systemImage: "person.crop.circle.badge.plus",
            executable: executable,
            arguments: arguments,
            environment: codexAuthEnvironment(prepending: resourceDirectory),
            displayCommand: "PATH=\(ShellQuoting.quote(resourceDirectory)):/opt/homebrew/bin:$PATH \(ShellQuoting.displayCommand(executable: "codex-auth", arguments: arguments))"
        )
    }

    func importAuth(authFilePath: String, alias: String) throws -> CommandDefinition {
        let trimmedPath = authFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedPath.isEmpty == false else {
            throw CommandFactoryError.missingAuthFilePath
        }

        let executable = try codexAuthExecutable()
        var arguments = ["import", NSString(string: trimmedPath).expandingTildeInPath]
        if trimmedAlias.isEmpty == false {
            arguments.append(contentsOf: ["--alias", trimmedAlias])
        }

        return CommandDefinition(
            id: "import",
            title: "Save / Update Login",
            systemImage: "tray.and.arrow.down",
            executable: executable,
            arguments: arguments,
            environment: codexAuthEnvironment(),
            displayCommand: ShellQuoting.displayCommand(executable: "codex-auth", arguments: arguments)
        )
    }

    func switchAccount(query: String) throws -> CommandDefinition {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            throw CommandFactoryError.missingSwitchQuery
        }

        let executable = try codexAuthExecutable()
        let arguments = ["switch", trimmedQuery]

        return CommandDefinition(
            id: "switch",
            title: "Switch Account",
            systemImage: "arrow.triangle.2.circlepath",
            executable: executable,
            arguments: arguments,
            environment: codexAuthEnvironment(),
            displayCommand: ShellQuoting.displayCommand(executable: "codex-auth", arguments: arguments)
        )
    }

    func list() throws -> CommandDefinition {
        let executable = try codexAuthExecutable()
        return CommandDefinition(
            id: "list",
            title: "List Accounts",
            systemImage: "list.bullet.rectangle",
            executable: executable,
            arguments: ["list"],
            environment: codexAuthEnvironment(),
            displayCommand: "codex-auth list"
        )
    }

    func remove(query: String) throws -> CommandDefinition {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            throw CommandFactoryError.missingRemoveSelector
        }

        let executable = try codexAuthExecutable()
        let arguments = ["remove", trimmedQuery]

        return CommandDefinition(
            id: "remove",
            title: "Remove Account",
            systemImage: "trash",
            executable: executable,
            arguments: arguments,
            environment: codexAuthEnvironment(),
            risk: .destructive,
            displayCommand: ShellQuoting.displayCommand(executable: "codex-auth", arguments: arguments)
        )
    }

    func restartCodex(codexResourceDirectory: String = CodexResourceSettings.defaultDirectory) -> CommandDefinition {
        let bundleIdentifier = "com.openai.codex"
        let appBundlePath = CodexResourceSettings.codexAppBundlePath(forResourceDirectory: codexResourceDirectory)
        let script = """
        bundle_id=\(ShellQuoting.quote(bundleIdentifier))
        app_bundle=\(ShellQuoting.quote(appBundlePath))
        process_marker="${app_bundle}/Contents/"

        codexPids() {
          /bin/ps -axo pid=,command= | /usr/bin/awk -v marker="$process_marker" '
          {
            pid = $1
            command = $0
            sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "", command)
            if (index(command, marker) == 1 || command ~ /\\/Codex\\.app\\/Contents\\//) {
              print pid
            }
          }'
        }

        waitForCodexExit() {
          local remaining="$1"
          local delay="$2"
          while (( remaining > 0 )); do
            if [[ -z "$(codexPids)" ]]; then
              return 0
            fi
            sleep "$delay"
            remaining=$(( remaining - 1 ))
          done
          [[ -z "$(codexPids)" ]]
        }

        signalCodex() {
          local signal="$1"
          local pids
          pids="$(codexPids)"
          if [[ -n "$pids" ]]; then
            /bin/kill "-$signal" ${(f)pids} 2>/dev/null || true
          fi
        }

        /usr/bin/osascript -e 'tell application id "com.openai.codex" to quit' 2>/dev/null || true
        waitForCodexExit 30 0.1 || true

        if [[ -n "$(codexPids)" ]]; then
          signalCodex TERM
          waitForCodexExit 10 0.1 || true
        fi

        if [[ -n "$(codexPids)" ]]; then
          signalCodex KILL
          waitForCodexExit 20 0.1 || true
        fi

        if [[ -d "$app_bundle" ]]; then
          /usr/bin/open "$app_bundle"
        else
          /usr/bin/open -b "$bundle_id"
        fi
        """

        return CommandDefinition(
            id: "restart",
            title: "Restart Codex",
            systemImage: "power",
            executable: "/bin/zsh",
            arguments: ["-lc", script],
            risk: .restartsApplication,
            displayCommand: "osascript -e 'tell application id \"\(bundleIdentifier)\" to quit'; wait for Codex to exit; open \(ShellQuoting.quote(appBundlePath))"
        )
    }

    func openCodex(codexResourceDirectory: String = CodexResourceSettings.defaultDirectory) -> CommandDefinition {
        let bundleIdentifier = "com.openai.codex"
        let appBundlePath = CodexResourceSettings.codexAppBundlePath(forResourceDirectory: codexResourceDirectory)
        let script = """
        bundle_id=\(ShellQuoting.quote(bundleIdentifier))
        app_bundle=\(ShellQuoting.quote(appBundlePath))

        if [[ -d "$app_bundle" ]]; then
          /usr/bin/open "$app_bundle"
        else
          /usr/bin/open -b "$bundle_id"
        fi
        """

        return CommandDefinition(
            id: "open-codex",
            title: "Open Codex",
            systemImage: "arrow.up.forward.app",
            executable: "/bin/zsh",
            arguments: ["-lc", script],
            displayCommand: "open \(ShellQuoting.quote(appBundlePath))"
        )
    }

    func forceCloseCodex(codexResourceDirectory: String = CodexResourceSettings.defaultDirectory) -> CommandDefinition {
        let appBundlePath = CodexResourceSettings.codexAppBundlePath(forResourceDirectory: codexResourceDirectory)
        let script = """
        app_bundle=\(ShellQuoting.quote(appBundlePath))
        process_marker="${app_bundle}/Contents/"

        codexPids() {
          /bin/ps -axo pid=,command= | /usr/bin/awk -v marker="$process_marker" '
          {
            pid = $1
            command = $0
            sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "", command)
            if (index(command, marker) == 1 || command ~ /\\/Codex\\.app\\/Contents\\//) {
              print pid
            }
          }'
        }

        waitForCodexExit() {
          local remaining="$1"
          local delay="$2"
          while (( remaining > 0 )); do
            if [[ -z "$(codexPids)" ]]; then
              return 0
            fi
            sleep "$delay"
            remaining=$(( remaining - 1 ))
          done
          [[ -z "$(codexPids)" ]]
        }

        signalCodex() {
          local signal="$1"
          local pids
          pids="$(codexPids)"
          if [[ -n "$pids" ]]; then
            /bin/kill "-$signal" ${(f)pids} 2>/dev/null || true
          fi
        }

        signalCodex TERM
        waitForCodexExit 10 0.1 || true

        if [[ -n "$(codexPids)" ]]; then
          signalCodex KILL
          waitForCodexExit 20 0.1 || true
        fi
        """

        return CommandDefinition(
            id: "force-close-codex",
            title: "Force Close Codex",
            systemImage: "xmark.circle",
            executable: "/bin/zsh",
            arguments: ["-lc", script],
            risk: .destructive,
            displayCommand: "force close Codex at \(ShellQuoting.quote(appBundlePath))"
        )
    }

    private func codexAuthExecutable() throws -> String {
        if let executable = resolver.resolve("codex-auth") {
            return executable
        }
        throw CommandFactoryError.missingExecutable("codex-auth")
    }

    private func codexAuthEnvironment(prepending directory: String? = nil) -> [String: String] {
        [
            "PATH": codexAuthPath(prepending: directory)
        ]
    }

    private func codexAuthPath(prepending directory: String? = nil) -> String {
        var directories: [String] = []
        if let directory = directory?.trimmedNonEmpty {
            directories.append(directory)
        }
        directories.append(codexAuthToolManager.managedBinDirectory.path)
        directories.append("/opt/homebrew/bin")
        return resolver.pathByPrepending(directories)
    }
}
