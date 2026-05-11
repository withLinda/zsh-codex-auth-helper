import Foundation
import Testing
@testable import ZshCodexAuthHelper

struct PTYCommandExecutorTests {
    @Test func executorStreamsOutputAndExitCode() async throws {
        let executor = PTYCommandExecutor()
        let command = CommandDefinition(
            title: "Echo",
            systemImage: "terminal",
            executable: "/bin/echo",
            arguments: ["hello"],
            displayCommand: "/bin/echo hello"
        )

        let result = try await executor.runForTesting(command)

        #expect(result.output.contains("hello"))
        #expect(result.exitCode == 0)
    }

    @Test func executorSendsInputToInteractiveProcess() async throws {
        let executor = PTYCommandExecutor()
        let command = CommandDefinition(
            title: "Cat",
            systemImage: "terminal",
            executable: "/bin/cat",
            arguments: [],
            displayCommand: "/bin/cat"
        )

        let result = try await executor.runForTesting(command, input: "typed text\n", stopAfterInput: true)

        #expect(result.output.contains("typed text"))
    }

    @Test func executorReportsNonZeroExit() async throws {
        let executor = PTYCommandExecutor()
        let command = CommandDefinition(
            title: "False",
            systemImage: "terminal",
            executable: "/usr/bin/false",
            arguments: [],
            displayCommand: "/usr/bin/false"
        )

        let result = try await executor.runForTesting(command)

        #expect(result.exitCode != 0)
    }
}

