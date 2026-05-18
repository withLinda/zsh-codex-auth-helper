import Foundation

enum CommandFactoryError: LocalizedError, Equatable {
    case missingExecutable(String)
    case missingAuthFilePath
    case missingSwitchQuery
    case missingRemoveAlias

    var errorDescription: String? {
        switch self {
        case .missingExecutable(let name):
            return "Could not find \(name)."
        case .missingAuthFilePath:
            return "Add an auth file path before saving."
        case .missingSwitchQuery:
            return "Add an alias after codex-auth switch before running."
        case .missingRemoveAlias:
            return "Add an alias after codex-auth remove before running."
        }
    }
}

struct CodexCommandFactory {
    private let resolver: ExecutableResolver
    private let homeDirectory: URL

    init(
        resolver: ExecutableResolver = .init(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.resolver = resolver
        self.homeDirectory = homeDirectory
    }

    static func live() -> CodexCommandFactory {
        CodexCommandFactory()
    }

    var defaultAuthFilePath: String {
        homeDirectory.appendingPathComponent(".codex/auth.json").path
    }

    func login(codexResourceDirectory: String = CodexResourceSettings.defaultDirectory) -> CommandDefinition {
        let resourceDirectory = CodexResourceSettings.normalizedDirectory(codexResourceDirectory)
        let bundledCodex = CodexResourceSettings.codexExecutablePath(in: resourceDirectory)
        let executable = resolver.resolve(bundledCodex) ?? resolver.resolveFromEnvironmentPath("codex") ?? bundledCodex
        let path = resolver.pathByPrepending(resourceDirectory)
        let arguments = ["login", "--device-auth"]

        return CommandDefinition(
            id: "login",
            title: "Login",
            systemImage: "person.crop.circle.badge.plus",
            executable: executable,
            arguments: arguments,
            environment: ["PATH": path],
            displayCommand: "PATH=\(ShellQuoting.quote(resourceDirectory)):$PATH codex login --device-auth"
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

    func remove(alias: String) throws -> CommandDefinition {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAlias.isEmpty == false else {
            throw CommandFactoryError.missingRemoveAlias
        }

        let executable = try codexAuthExecutable()
        let arguments = ["remove", trimmedAlias]

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
            if (index(command, marker) == 1) {
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

    private func codexAuthExecutable() throws -> String {
        if let executable = resolver.resolve("codex-auth") {
            return executable
        }
        throw CommandFactoryError.missingExecutable("codex-auth")
    }

    private func codexAuthEnvironment() -> [String: String] {
        [
            "PATH": resolver.pathByPrepending("/opt/homebrew/bin")
        ]
    }
}
