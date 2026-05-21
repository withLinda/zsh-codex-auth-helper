import Foundation

struct LoginAutoSavePlanner {
    private let readSession: (String) -> AuthSessionInfo

    init(reader: AuthSessionReader = AuthSessionReader()) {
        self.readSession = { authFilePath in
            reader.read(authFilePath: authFilePath)
        }
    }

    init(readSession: @escaping (String) -> AuthSessionInfo) {
        self.readSession = readSession
    }

    func autoSaveCommand(
        authFilePath: String,
        commandFactory: CodexCommandFactory
    ) throws -> CommandDefinition? {
        guard let emailAlias = emailAlias(authFilePath: authFilePath) else {
            return nil
        }

        return try commandFactory.importAuth(authFilePath: authFilePath, alias: emailAlias)
    }

    func emailAlias(authFilePath: String) -> String? {
        guard let email = readSession(authFilePath)
            .email?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            email.isEmpty == false else {
            return nil
        }

        return email.lowercased()
    }
}
