import SwiftUI

struct ContentView: View {
    @AppStorage(CodexResourceSettings.userDefaultsKey) private var codexResourceDirectory = CodexResourceSettings.defaultDirectory

    @StateObject private var transcriptStore = TerminalTranscriptStore()
    @StateObject private var runner = CommandRunner()
    @StateObject private var authSessionMonitor = AuthSessionMonitor()
    @StateObject private var codexAppMonitor = CodexAppMonitor()

    private let commandFactory: CodexCommandFactory
    private let switchPreflightValidator: AuthSwitchPreflightValidator
    private let healthCheckService: AuthHealthCheckService
    private let loginAutoSavePlanner: LoginAutoSavePlanner
    private let linkOpener: ChromeIncognitoLinkOpener

    @State private var authFilePath: String
    @State private var alias: String
    @State private var terminalInput = ""
    @State private var terminalInputFocusRequest = 0
    @State private var isCheckingSwitch = false
    @State private var isRunningHealthCheck = false

    private var isBusy: Bool {
        runner.isRunning || isCheckingSwitch || isRunningHealthCheck
    }

    init(
        commandFactory: CodexCommandFactory = .live(),
        switchPreflightValidator: AuthSwitchPreflightValidator = AuthSwitchPreflightValidator(),
        healthCheckService: AuthHealthCheckService = AuthHealthCheckService(),
        loginAutoSavePlanner: LoginAutoSavePlanner = LoginAutoSavePlanner(),
        linkOpener: ChromeIncognitoLinkOpener = ChromeIncognitoLinkOpener()
    ) {
        self.commandFactory = commandFactory
        self.switchPreflightValidator = switchPreflightValidator
        self.healthCheckService = healthCheckService
        self.loginAutoSavePlanner = loginAutoSavePlanner
        self.linkOpener = linkOpener
        _authFilePath = State(initialValue: commandFactory.defaultAuthFilePath)
        _alias = State(initialValue: "")
    }

    var body: some View {
        HStack(spacing: 0) {
            CommandRailView(
                alias: $alias,
                authFilePath: $authFilePath,
                authSession: authSessionMonitor.info,
                codexAppState: codexAppMonitor.state,
                isRunning: isBusy,
                runLogin: runLogin,
                runImport: runImport,
                runSwitch: prepareSwitchDraft,
                runRestart: runRestartCodex,
                runOpenCodex: runOpenCodex,
                runForceCloseCodex: runForceCloseCodex,
                runList: { runFactoryCommand(commandFactory.list) },
                runHealthCheck: runHealthCheck,
                requestRemove: prepareRemoveDraft
            )
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 400)

            TerminalPanelView(
                store: transcriptStore,
                runner: runner,
                input: $terminalInput,
                focusRequest: terminalInputFocusRequest,
                submitDraft: submitTerminalDraft,
                openURL: openLoginURL
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ThemeTokens.Colors.appBackground)
        .onAppear {
            authSessionMonitor.start(authFilePath: authFilePath)
            codexAppMonitor.start(codexResourceDirectory: codexResourceDirectory)
        }
        .onDisappear {
            authSessionMonitor.stop()
            codexAppMonitor.stop()
        }
        .onChange(of: authFilePath) { _, newPath in
            authSessionMonitor.updateAuthFilePath(newPath)
        }
        .onChange(of: codexResourceDirectory) { _, newDirectory in
            codexAppMonitor.update(codexResourceDirectory: newDirectory)
        }
        .onChange(of: runner.isRunning) { wasRunning, isRunning in
            if wasRunning, isRunning == false {
                authSessionMonitor.refreshCurrent()
                codexAppMonitor.refresh()
            }
        }
    }

    private func runLogin() {
        run(commandFactory.login(codexResourceDirectory: codexResourceDirectory)) { result in
            handleLoginCompletion(result)
        }
    }

    private func runImport() {
        do {
            let command = try commandFactory.importAuth(authFilePath: authFilePath, alias: alias)
            run(command) { result in
                if result.exitCode == 0 {
                    alias = ""
                }
            }
        } catch {
            transcriptStore.failToStart(error)
        }
    }

    private func runRestartCodex() {
        run(commandFactory.restartCodex(codexResourceDirectory: codexResourceDirectory)) { _ in
            codexAppMonitor.refresh()
        }
    }

    private func runOpenCodex() {
        run(commandFactory.openCodex(codexResourceDirectory: codexResourceDirectory)) { _ in
            codexAppMonitor.refresh()
        }
    }

    private func runForceCloseCodex() {
        run(commandFactory.forceCloseCodex(codexResourceDirectory: codexResourceDirectory)) { _ in
            codexAppMonitor.refresh()
        }
    }

    private func openLoginURL(_ url: URL) {
        do {
            try linkOpener.open(url)
        } catch {
            transcriptStore.appendSystemLine(error.localizedDescription)
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
                terminalInput = ""
                Task {
                    await runPreflightSwitch(query: query)
                }
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

    private func run(_ command: CommandDefinition, onFinish: ((PTYCommandResult) -> Void)? = nil) {
        runner.start(command, transcriptStore: transcriptStore, onFinish: onFinish)
    }

    private func handleLoginCompletion(_ result: PTYCommandResult) {
        guard result.exitCode == 0 else {
            return
        }

        authSessionMonitor.refreshCurrent()

        do {
            guard let emailAlias = loginAutoSavePlanner.emailAlias(authFilePath: authFilePath) else {
                transcriptStore.appendSystemLine("Login finished, but no email was found in the auth file. Use Save / Update Login manually.")
                return
            }

            transcriptStore.appendSystemLine("Login finished. Saving login as \(emailAlias)...")
            let command = try commandFactory.importAuth(authFilePath: authFilePath, alias: emailAlias)
            run(command) { result in
                if result.exitCode == 0 {
                    alias = ""
                }
            }
        } catch {
            transcriptStore.failToStart(error)
        }
    }

    private func runPreflightSwitch(query: String) async {
        guard isBusy == false else {
            transcriptStore.appendSystemLine("A command is already running. Stop it before starting another one.")
            return
        }

        isCheckingSwitch = true
        transcriptStore.appendSystemLine("Checking saved login before switching...")

        do {
            let account = try await switchPreflightValidator.validateAndRefresh(query: query)
            transcriptStore.appendSystemLine("Login check passed for \(account.email).")
            let command = try commandFactory.switchAccount(query: query)
            isCheckingSwitch = false
            run(command)
        } catch {
            isCheckingSwitch = false
            transcriptStore.appendSystemLine(error.localizedDescription)
        }
    }

    private func runHealthCheck() {
        guard isBusy == false else {
            transcriptStore.appendSystemLine("A command is already running. Stop it before starting another one.")
            return
        }

        isRunningHealthCheck = true
        Task {
            _ = await healthCheckService.run { event in
                transcriptStore.appendSystemLine(event.transcriptLine)
            }
            isRunningHealthCheck = false
            authSessionMonitor.refreshCurrent()
        }
    }
}
