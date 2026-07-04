import Foundation
import Testing
@testable import ZshCodexAuthHelper

@MainActor
struct CodexAppMonitorTests {
    @Test func restartIsAvailableOnlyWhenCodexIsOpen() {
        #expect(CodexAppState.open.canRestart)
        #expect(CodexAppState.closed.canRestart == false)
    }

    @Test func refreshMarksCodexOpenWhenBundleIdentifierIsRunning() {
        let monitor = CodexAppMonitor(
            runningApplications: {
                [
                    .init(
                        bundleIdentifier: "com.openai.codex",
                        bundleURLPath: "/Applications/Codex.app",
                        isTerminated: false
                    )
                ]
            }
        )

        monitor.start(codexResourceDirectory: "/Applications/Codex.app/Contents/Resources", observesWorkspace: false)

        #expect(monitor.state == .open)
    }

    @Test func refreshMarksCodexOpenWhenConfiguredBundlePathIsRunning() {
        let monitor = CodexAppMonitor(
            runningApplications: {
                [
                    .init(
                        bundleIdentifier: nil,
                        bundleURLPath: "/Users/linda/My Apps/Codex.app",
                        isTerminated: false
                    )
                ]
            }
        )

        monitor.start(codexResourceDirectory: "/Users/linda/My Apps/Codex.app/Contents/Resources", observesWorkspace: false)

        #expect(monitor.state == .open)
    }

    @Test func refreshMarksCodexClosedWhenOnlyTerminatedAppMatches() {
        let monitor = CodexAppMonitor(
            runningApplications: {
                [
                    .init(
                        bundleIdentifier: "com.openai.codex",
                        bundleURLPath: "/Applications/Codex.app",
                        isTerminated: true
                    )
                ]
            }
        )

        monitor.start(codexResourceDirectory: "/Applications/Codex.app/Contents/Resources", observesWorkspace: false)

        #expect(monitor.state == .closed)
    }

    @Test func updateResourceDirectoryRechecksCustomPath() {
        var configuredPath = "/Applications/Codex.app"
        let monitor = CodexAppMonitor(
            runningApplications: {
                [
                    .init(
                        bundleIdentifier: nil,
                        bundleURLPath: configuredPath,
                        isTerminated: false
                    )
                ]
            }
        )

        monitor.start(codexResourceDirectory: "/Applications/Codex.app/Contents/Resources", observesWorkspace: false)
        configuredPath = "/Users/linda/My Apps/Codex.app"
        monitor.update(codexResourceDirectory: "/Users/linda/My Apps/Codex.app/Contents/Resources")

        #expect(monitor.state == .open)
    }

    @Test func refreshMarksCodexClosedWhenNoRunningAppMatches() {
        let monitor = CodexAppMonitor(
            runningApplications: {
                [
                    .init(
                        bundleIdentifier: "com.apple.Terminal",
                        bundleURLPath: "/System/Applications/Utilities/Terminal.app",
                        isTerminated: false
                    )
                ]
            }
        )

        monitor.start(codexResourceDirectory: "/Applications/Codex.app/Contents/Resources", observesWorkspace: false)

        #expect(monitor.state == .closed)
    }
}
