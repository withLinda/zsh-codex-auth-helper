import Foundation

enum CommandRisk: Equatable {
    case normal
    case destructive
    case restartsApplication
}

enum CommandDraftParseError: LocalizedError, Equatable {
    case missingSwitchQuery
    case unsupportedCommand

    var errorDescription: String? {
        switch self {
        case .missingSwitchQuery:
            return "Add an alias after codex-auth switch before running."
        case .unsupportedCommand:
            return "Only codex-auth switch <alias> can run from this input."
        }
    }
}

enum CommandDraft: Equatable {
    case switchAccount(query: String)
}

enum CommandDraftParser {
    private static let switchCommand = "codex-auth switch"

    static func parse(_ input: String) throws -> CommandDraft {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedInput.hasPrefix(switchCommand) else {
            throw CommandDraftParseError.unsupportedCommand
        }

        let suffix = trimmedInput.dropFirst(switchCommand.count)
        guard suffix.first?.isWhitespace == true else {
            if suffix.isEmpty {
                throw CommandDraftParseError.missingSwitchQuery
            }
            throw CommandDraftParseError.unsupportedCommand
        }

        let query = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            throw CommandDraftParseError.missingSwitchQuery
        }

        return .switchAccount(query: query)
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
