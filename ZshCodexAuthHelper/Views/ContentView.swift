import SwiftUI

struct ContentView: View {
    @AppStorage(CodexResourceSettings.userDefaultsKey) private var codexResourceDirectory = CodexResourceSettings.defaultDirectory
    @AppStorage(CodexAuthToolSettings.releaseChannelKey) private var codexAuthReleaseChannelRaw = CodexAuthReleaseChannel.stable.rawValue

    @StateObject private var transcriptStore = TerminalTranscriptStore()
    @StateObject private var runner = CommandRunner()
    @StateObject private var authSessionMonitor = AuthSessionMonitor()
    @StateObject private var codexAppMonitor = CodexAppMonitor()
    @StateObject private var accountListStore = AccountListStore()

    private let commandFactory: CodexCommandFactory
    private let switchPreflightValidator: AuthSwitchPreflightValidator
    private let healthCheckService: AuthHealthCheckService
    private let linkOpener: ChromeIncognitoLinkOpener
    private let codexAuthToolManager: CodexAuthToolManager

    @State private var authFilePath: String
    @State private var alias: String
    @State private var terminalInput = ""
    @State private var terminalInputFocusRequest = 0
    @State private var isCheckingSwitch = false
    @State private var isRunningHealthCheck = false
    @State private var pendingAccountRemoval: AccountListItem?

    private var isBusy: Bool {
        runner.isRunning || isCheckingSwitch || isRunningHealthCheck
    }

    private var selectedCodexAuthReleaseChannel: CodexAuthReleaseChannel {
        CodexAuthReleaseChannel(storedValue: codexAuthReleaseChannelRaw)
    }

    private var codexAppDisplayName: String {
        let resolvedDirectory = CodexResourceSettings.resolvedDirectory(codexResourceDirectory)
        let appBundlePath = CodexResourceSettings.codexAppBundlePath(forResourceDirectory: resolvedDirectory)
        return CodexResourceSettings.appDisplayName(forAppBundlePath: appBundlePath)
    }

    init(
        commandFactory: CodexCommandFactory = .live(),
        switchPreflightValidator: AuthSwitchPreflightValidator = AuthSwitchPreflightValidator(),
        healthCheckService: AuthHealthCheckService = AuthHealthCheckService(),
        linkOpener: ChromeIncognitoLinkOpener = ChromeIncognitoLinkOpener(),
        codexAuthToolManager: CodexAuthToolManager = .live()
    ) {
        self.commandFactory = commandFactory
        self.switchPreflightValidator = switchPreflightValidator
        self.healthCheckService = healthCheckService
        self.linkOpener = linkOpener
        self.codexAuthToolManager = codexAuthToolManager
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
                codexAppDisplayName: codexAppDisplayName,
                isRunning: isBusy,
                runLogin: runLogin,
                runImport: runImport,
                runRestart: runRestartCodex,
                runOpenCodex: runOpenCodex,
                runForceCloseCodex: runForceCloseCodex,
                runOpenBlankIncognito: openBlankIncognito,
                runUpdateCodexAuth: runUpdateCodexAuth,
                runHealthCheck: runHealthCheck
            )
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 400)

            VSplitView {
                AccountDashboardView(
                    store: accountListStore,
                    codexAppDisplayName: codexAppDisplayName,
                    isRunning: isBusy,
                    refresh: accountListStore.refresh,
                    switchAccount: switchToAccount,
                    requestRemove: requestRemoveAccount
                )
                .frame(minHeight: 310)

                TerminalPanelView(
                    store: transcriptStore,
                    runner: runner,
                    input: $terminalInput,
                    focusRequest: terminalInputFocusRequest,
                    submitDraft: submitTerminalDraft,
                    openURL: openLoginURL
                )
                .frame(minHeight: 230, idealHeight: 280)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ThemeTokens.Colors.appBackground)
        .alert(
            "Remove saved account?",
            isPresented: isShowingRemoveAlert,
            presenting: pendingAccountRemoval
        ) { account in
            Button("Remove", role: .destructive) {
                confirmRemoveAccount(account)
            }
            Button("Cancel", role: .cancel) {
                pendingAccountRemoval = nil
            }
        } message: { account in
            Text("Remove \(account.email) from saved accounts. This does not delete the OpenAI account.")
        }
        .onAppear {
            let resolvedDirectory = CodexResourceSettings.resolvedDirectory(codexResourceDirectory)
            if resolvedDirectory != codexResourceDirectory {
                codexResourceDirectory = resolvedDirectory
            }
            authSessionMonitor.start(authFilePath: authFilePath)
            codexAppMonitor.start(codexResourceDirectory: resolvedDirectory)
            accountListStore.start()
        }
        .onDisappear {
            authSessionMonitor.stop()
            codexAppMonitor.stop()
            accountListStore.stop()
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
                accountListStore.refresh()
            }
        }
    }

    private var isShowingRemoveAlert: Binding<Bool> {
        Binding {
            pendingAccountRemoval != nil
        } set: { isShowing in
            if isShowing == false {
                pendingAccountRemoval = nil
            }
        }
    }

    private func runLogin() {
        do {
            let command = try commandFactory.login(codexResourceDirectory: codexResourceDirectory)
            run(command) { result in
                handleLoginCompletion(result)
            }
        } catch {
            transcriptStore.failToStart(error)
        }
    }

    private func runImport() {
        do {
            let command = try commandFactory.importAuth(authFilePath: authFilePath, alias: alias)
            run(command) { result in
                if result.exitCode == 0 {
                    alias = ""
                    accountListStore.refresh()
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

    private func runUpdateCodexAuth() {
        do {
            let command = try commandFactory.updateCodexAuth(channel: selectedCodexAuthReleaseChannel)
            run(command) { result in
                guard result.exitCode == 0 else {
                    return
                }

                Task {
                    let version = await codexAuthToolManager.installedVersion()
                    await MainActor.run {
                        if let version {
                            transcriptStore.appendSystemLine("App codex-auth version: \(version).")
                        } else {
                            transcriptStore.appendSystemLine("Update finished, but the app could not read the app-owned codex-auth version.")
                        }
                    }
                }
            }
        } catch {
            transcriptStore.failToStart(error)
        }
    }

    private func openLoginURL(_ url: URL) {
        do {
            try linkOpener.open(url)
        } catch {
            transcriptStore.appendSystemLine(error.localizedDescription)
        }
    }

    private func openBlankIncognito() {
        do {
            try linkOpener.openBlankWindow()
        } catch {
            transcriptStore.appendSystemLine(error.localizedDescription)
        }
    }

    private func submitTerminalDraft(_ draft: String) {
        do {
            switch try CommandDraftParser.parse(draft) {
            case .switchAccount(let query):
                terminalInput = ""
                Task {
                    await runPreflightSwitch(query: query)
                }
            case .removeAccount(let query):
                let command = try commandFactory.remove(query: query)
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

    private func switchToAccount(_ account: AccountListItem) {
        guard account.isActive == false else {
            return
        }

        Task {
            await runPreflightSwitch(query: account.safeSelector, opensCodexAfterSwitch: true)
        }
    }

    private func requestRemoveAccount(_ account: AccountListItem) {
        pendingAccountRemoval = account
    }

    private func confirmRemoveAccount(_ account: AccountListItem) {
        pendingAccountRemoval = nil

        guard isBusy == false else {
            transcriptStore.appendSystemLine("A command is already running. Stop it before starting another one.")
            return
        }

        do {
            let command = try commandFactory.remove(query: account.safeSelector)
            run(command) { result in
                guard result.exitCode == 0 else {
                    return
                }
                accountListStore.refresh()
            }
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

        transcriptStore.appendSystemLine("Login finished. codex-auth saved the account. Use Save / Update Login only if you want to set or change an alias.")
    }

    private func runPreflightSwitch(query: String, opensCodexAfterSwitch: Bool = false) async {
        guard isBusy == false else {
            transcriptStore.appendSystemLine("A command is already running. Stop it before starting another one.")
            return
        }

        isCheckingSwitch = true
        transcriptStore.appendSystemLine("Checking saved login before switching...")

        do {
            _ = try await switchPreflightValidator.prepareForSwitch(query: query) { event in
                await MainActor.run {
                    transcriptStore.appendSystemLine(event.transcriptLine)
                }
            }
            let command = if opensCodexAfterSwitch {
                try commandFactory.switchAccountAndOpenCodex(
                    query: query,
                    codexResourceDirectory: codexResourceDirectory
                )
            } else {
                try commandFactory.switchAccount(query: query)
            }
            transcriptStore.appendSystemLine("Switch check passed. Running \(command.displayCommand).")
            isCheckingSwitch = false
            run(command) { result in
                guard result.exitCode == 0 else {
                    return
                }
                accountListStore.refresh()
                if opensCodexAfterSwitch {
                    codexAppMonitor.refresh()
                }
            }
        } catch {
            isCheckingSwitch = false
            transcriptStore.appendSystemLine(error.localizedDescription)
            transcriptStore.appendSystemLine("Switch blocked. No account was switched.")
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
            accountListStore.refresh()
        }
    }
}
