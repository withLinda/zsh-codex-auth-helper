import AppKit
import Foundation

enum CodexAppState: Equatable {
    case open
    case closed

    var canRestart: Bool {
        self == .open
    }
}

struct CodexRunningApplicationSnapshot: Equatable {
    var bundleIdentifier: String?
    var bundleURLPath: String?
    var isTerminated: Bool
}

@MainActor
final class CodexAppMonitor: ObservableObject {
    @Published private(set) var state: CodexAppState = .closed

    private let codexBundleIdentifier = "com.openai.codex"
    private let runningApplications: () -> [CodexRunningApplicationSnapshot]
    private var codexResourceDirectory = CodexResourceSettings.defaultDirectory
    private var observerTokens: [NSObjectProtocol] = []

    init(
        runningApplications: @escaping () -> [CodexRunningApplicationSnapshot] = {
            NSWorkspace.shared.runningApplications.map { application in
                CodexRunningApplicationSnapshot(
                    bundleIdentifier: application.bundleIdentifier,
                    bundleURLPath: application.bundleURL?.path,
                    isTerminated: application.isTerminated
                )
            }
        }
    ) {
        self.runningApplications = runningApplications
    }

    deinit {
        let tokens = observerTokens
        NSWorkspace.shared.notificationCenter.removeObservers(tokens)
    }

    func start(codexResourceDirectory: String, observesWorkspace: Bool = true) {
        self.codexResourceDirectory = codexResourceDirectory
        refresh()

        if observesWorkspace {
            startObservingWorkspaceIfNeeded()
        }
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObservers(observerTokens)
        observerTokens = []
    }

    func update(codexResourceDirectory: String) {
        guard self.codexResourceDirectory != codexResourceDirectory else {
            return
        }

        self.codexResourceDirectory = codexResourceDirectory
        refresh()
    }

    func refresh() {
        state = runningApplications().contains(where: isCodexApplication) ? .open : .closed
    }

    private func startObservingWorkspaceIfNeeded() {
        guard observerTokens.isEmpty else {
            return
        }

        let notificationCenter = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]

        observerTokens = names.map { name in
            notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
        }
    }

    private func isCodexApplication(_ application: CodexRunningApplicationSnapshot) -> Bool {
        guard application.isTerminated == false else {
            return false
        }

        if application.bundleIdentifier == codexBundleIdentifier {
            return true
        }

        guard let bundleURLPath = application.bundleURLPath else {
            return false
        }

        return Self.standardizedPath(bundleURLPath) == configuredAppBundlePath
    }

    private var configuredAppBundlePath: String {
        Self.standardizedPath(
            CodexResourceSettings.codexAppBundlePath(forResourceDirectory: codexResourceDirectory)
        )
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            .standardizedFileURL
            .path
    }
}

private extension NotificationCenter {
    func removeObservers(_ observers: [NSObjectProtocol]) {
        for observer in observers {
            removeObserver(observer)
        }
    }
}
