import SwiftUI

struct ContentView: View {
    @AppStorage(CodexResourceSettings.userDefaultsKey) private var codexResourceDirectory = CodexResourceSettings.defaultDirectory

    @StateObject private var transcriptStore = TerminalTranscriptStore()
    @StateObject private var runner = CommandRunner()
    @StateObject private var authSessionMonitor = AuthSessionMonitor()

    private let commandFactory: CodexCommandFactory

    @State private var authFilePath: String
    @State private var alias: String
    @State private var terminalInput = ""
    @State private var terminalInputFocusRequest = 0

    init(commandFactory: CodexCommandFactory = .live()) {
        self.commandFactory = commandFactory
        _authFilePath = State(initialValue: commandFactory.defaultAuthFilePath)
        _alias = State(initialValue: "main")
    }

    var body: some View {
        HStack(spacing: 0) {
            CommandRailView(
                alias: $alias,
                authFilePath: $authFilePath,
                authSession: authSessionMonitor.info,
                isRunning: runner.isRunning,
                runLogin: { run(commandFactory.login(codexResourceDirectory: codexResourceDirectory)) },
                runImport: runImport,
                runSwitch: prepareSwitchDraft,
                runRestart: { run(commandFactory.restartCodex(codexResourceDirectory: codexResourceDirectory)) },
                runList: { runFactoryCommand(commandFactory.list) },
                requestRemove: prepareRemoveDraft
            )
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 400)

            TerminalPanelView(
                store: transcriptStore,
                runner: runner,
                input: $terminalInput,
                focusRequest: terminalInputFocusRequest,
                submitDraft: submitTerminalDraft
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ThemeTokens.Colors.appBackground)
        .onAppear {
            authSessionMonitor.start(authFilePath: authFilePath)
        }
        .onDisappear {
            authSessionMonitor.stop()
        }
        .onChange(of: authFilePath) { _, newPath in
            authSessionMonitor.updateAuthFilePath(newPath)
        }
        .onChange(of: runner.isRunning) { wasRunning, isRunning in
            if wasRunning, isRunning == false {
                authSessionMonitor.refreshCurrent()
            }
        }
    }

    private func runImport() {
        do {
            let command = try commandFactory.importAuth(authFilePath: authFilePath, alias: alias)
            run(command)
        } catch {
            transcriptStore.failToStart(error)
        }
    }

    private func prepareSwitchDraft() {
        terminalInput = "codex-auth switch "
        terminalInputFocusRequest += 1
    }

    private func prepareRemoveDraft() {
        terminalInput = "codex-auth remove "
        terminalInputFocusRequest += 1
    }

    private func submitTerminalDraft(_ draft: String) {
        do {
            switch try CommandDraftParser.parse(draft) {
            case .switchAccount(let query):
                let command = try commandFactory.switchAccount(query: query)
                terminalInput = ""
                run(command)
            case .removeAccount(let alias):
                let command = try commandFactory.remove(alias: alias)
                terminalInput = ""
                run(command)
            }
        } catch let error as CommandDraftParseError {
            transcriptStore.appendSystemLine(error.localizedDescription)
        } catch {
            transcriptStore.failToStart(error)
        }
    }

    private func runFactoryCommand(_ build: () throws -> CommandDefinition) {
        do {
            run(try build())
        } catch {
            transcriptStore.failToStart(error)
        }
    }

    private func run(_ command: CommandDefinition) {
        runner.start(command, transcriptStore: transcriptStore)
    }
}
