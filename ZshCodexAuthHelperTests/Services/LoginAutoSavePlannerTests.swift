import Foundation
import Testing
@testable import ZshCodexAuthHelper

struct LoginAutoSavePlannerTests {
    @Test func commandUsesDetectedEmailAsAliasAndPreservesAuthFilePath() throws {
        let factory = CodexCommandFactory(
            resolver: .init(environmentPath: "/opt/homebrew/bin", fileExists: { $0 == "/opt/homebrew/bin/codex-auth" }),
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )
        let planner = LoginAutoSavePlanner(
            readSession: { path in
                AuthSessionInfo(status: .activeAuth, email: "SAFINAJULI13@OUTLOOK.COM")
            }
        )

        let command = try planner.autoSaveCommand(
            authFilePath: "/Users/linda/.codex/auth.json",
            commandFactory: factory
        )

        #expect(command?.arguments == [
            "import",
            "/Users/linda/.codex/auth.json",
            "--alias",
            "safinajuli13@outlook.com"
        ])
    }

    @Test func commandIsNilWhenNoEmailCanBeRead() throws {
        let factory = CodexCommandFactory(
            resolver: .init(environmentPath: "/opt/homebrew/bin", fileExists: { $0 == "/opt/homebrew/bin/codex-auth" }),
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )
        let planner = LoginAutoSavePlanner(
            readSession: { _ in
                .noSignedInAccount
            }
        )

        let command = try planner.autoSaveCommand(
            authFilePath: "/Users/linda/.codex/auth.json",
            commandFactory: factory
        )

        #expect(command == nil)
    }

    @Test func commandIsNilWhenEmailIsBlank() throws {
        let factory = CodexCommandFactory(
            resolver: .init(environmentPath: "/opt/homebrew/bin", fileExists: { $0 == "/opt/homebrew/bin/codex-auth" }),
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )
        let planner = LoginAutoSavePlanner(
            readSession: { _ in
                AuthSessionInfo(status: .activeAuth, email: "   ")
            }
        )

        let command = try planner.autoSaveCommand(
            authFilePath: "/Users/linda/.codex/auth.json",
            commandFactory: factory
        )

        #expect(command == nil)
    }
}
