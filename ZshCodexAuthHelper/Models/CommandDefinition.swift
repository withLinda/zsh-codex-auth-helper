import Foundation

enum CommandRisk: Equatable {
    case normal
    case destructive
    case restartsApplication
}

enum CommandDraftParseError: LocalizedError, Equatable {
    case missingSwitchQuery
    case missingRemoveSelector
    case unsupportedCommand

    var errorDescription: String? {
        switch self {
        case .missingSwitchQuery:
            return "Add an account selector after codex-auth switch before running."
        case .missingRemoveSelector:
            return "Add an account selector after codex-auth remove before running."
        case .unsupportedCommand:
            return "Only codex-auth switch <selector> or codex-auth remove <selector> can run from this input."
        }
    }
}

enum CommandDraft: Equatable {
    case switchAccount(query: String)
    case removeAccount(query: String)
}

enum CommandDraftParser {
    private static let switchCommand = "codex-auth switch"
    private static let removeCommand = "codex-auth remove"

    static func parse(_ input: String) throws -> CommandDraft {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedInput.hasPrefix(switchCommand) {
            return try parseArgument(
                from: trimmedInput,
                command: switchCommand,
                missingError: .missingSwitchQuery,
                build: CommandDraft.switchAccount(query:)
            )
        }

        if trimmedInput.hasPrefix(removeCommand) {
            return try parseArgument(
                from: trimmedInput,
                command: removeCommand,
                missingError: .missingRemoveSelector,
                build: CommandDraft.removeAccount(query:)
            )
        }

        throw CommandDraftParseError.unsupportedCommand
    }

    private static func parseArgument(
        from trimmedInput: String,
        command: String,
        missingError: CommandDraftParseError,
        build: (String) -> CommandDraft
    ) throws -> CommandDraft {
        let suffix = trimmedInput.dropFirst(command.count)
        guard suffix.first?.isWhitespace == true else {
            if suffix.isEmpty {
                throw missingError
            }
            throw CommandDraftParseError.unsupportedCommand
        }

        let argument = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard argument.isEmpty == false else {
            throw missingError
        }

        return build(argument)
    }
}

struct CommandDefinition: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let executable: String
    let arguments: [String]
    let environment: [String: String]
    let risk: CommandRisk
    let displayCommand: String

    init(
        id: String? = nil,
        title: String,
        systemImage: String,
        executable: String,
        arguments: [String],
        environment: [String: String] = [:],
        risk: CommandRisk = .normal,
        displayCommand: String
    ) {
        self.id = id ?? title.lowercased().replacingOccurrences(of: " ", with: "-")
        self.title = title
        self.systemImage = systemImage
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.risk = risk
        self.displayCommand = displayCommand
    }
}
