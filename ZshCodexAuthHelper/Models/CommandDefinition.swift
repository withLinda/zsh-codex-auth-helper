import Foundation

enum CommandRisk: Equatable {
    case normal
    case destructive
    case restartsApplication
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

