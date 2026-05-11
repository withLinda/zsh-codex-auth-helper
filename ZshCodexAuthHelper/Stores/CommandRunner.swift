import Foundation

@MainActor
final class CommandRunner: ObservableObject {
    @Published private(set) var isRunning = false

    private let executor: PTYCommandExecutor
    private var runningCommand: RunningPTYCommand?

    init(executor: PTYCommandExecutor = PTYCommandExecutor()) {
        self.executor = executor
    }

    func start(_ command: CommandDefinition, transcriptStore: TerminalTranscriptStore) {
        guard isRunning == false else {
            transcriptStore.appendSystemLine("A command is already running. Stop it before starting another one.")
            return
        }

        transcriptStore.start(command)
        isRunning = true

        do {
            runningCommand = try executor.start(
                command,
                onOutput: { output in
                    DispatchQueue.main.async {
                        transcriptStore.appendOutput(output)
                    }
                },
                onTermination: { [weak self] result in
                    DispatchQueue.main.async {
                        transcriptStore.finish(result)
                        self?.runningCommand = nil
                        self?.isRunning = false
                    }
                }
            )
        } catch {
            transcriptStore.failToStart(error)
            runningCommand = nil
            isRunning = false
        }
    }

    func sendInput(_ input: String) {
        guard isRunning else {
            return
        }
        runningCommand?.sendInput(input)
    }

    func stop() {
        runningCommand?.terminate()
    }
}

