import Foundation
import Testing
@testable import ZshCodexAuthHelper

@MainActor
struct CommandRunnerTests {
    @Test func callsCompletionAfterCommandFinishes() async throws {
        let runner = CommandRunner()
        let store = TerminalTranscriptStore()
        let command = CommandDefinition(
            title: "Echo",
            systemImage: "terminal",
            executable: "/bin/echo",
            arguments: ["done"],
            displayCommand: "/bin/echo done"
        )
        var finishedResult: PTYCommandResult?
        var runnerWasStoppedAtCompletion = false

        runner.start(command, transcriptStore: store) { result in
            finishedResult = result
            runnerWasStoppedAtCompletion = runner.isRunning == false
        }

        while finishedResult == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(finishedResult?.exitCode == 0)
        #expect(runnerWasStoppedAtCompletion)
    }

    @Test func doesNotCallCompletionWhenStartFails() {
        let runner = CommandRunner(
            executor: PTYCommandExecutor()
        )
        let store = TerminalTranscriptStore()
        let command = CommandDefinition(
            title: "Missing",
            systemImage: "terminal",
            executable: "/missing/executable",
            arguments: [],
            displayCommand: "/missing/executable"
        )
        var completionCallCount = 0

        runner.start(command, transcriptStore: store) { _ in
            completionCallCount += 1
        }

        #expect(completionCallCount == 0)
        #expect(runner.isRunning == false)
    }
}
