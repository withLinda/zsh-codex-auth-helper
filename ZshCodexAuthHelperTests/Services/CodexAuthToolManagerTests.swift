import Foundation
import Testing
@testable import ZshCodexAuthHelper

struct CodexAuthToolManagerTests {
    @Test func managedPathsUseApplicationSupportFolder() {
        let manager = CodexAuthToolManager(
            applicationSupportDirectory: URL(fileURLWithPath: "/Users/linda/Library/Application Support")
        )

        #expect(manager.toolRoot.path == "/Users/linda/Library/Application Support/CodexAuthHelper/codex-auth-tool")
        #expect(manager.managedBinDirectory.path == "/Users/linda/Library/Application Support/CodexAuthHelper/codex-auth-tool/bin")
        #expect(manager.managedExecutablePath == "/Users/linda/Library/Application Support/CodexAuthHelper/codex-auth-tool/bin/codex-auth")
    }

    @Test func releaseChannelsMapToNpmTags() {
        #expect(CodexAuthReleaseChannel.stable.npmTag == "latest")
        #expect(CodexAuthReleaseChannel.stable.packageSpec == "@loongphy/codex-auth@latest")
        #expect(CodexAuthReleaseChannel.next.npmTag == "next")
        #expect(CodexAuthReleaseChannel.next.packageSpec == "@loongphy/codex-auth@next")
    }

    @Test func invalidStoredChannelDefaultsToStable() {
        #expect(CodexAuthReleaseChannel(storedValue: "next") == .next)
        #expect(CodexAuthReleaseChannel(storedValue: "broken") == .stable)
        #expect(CodexAuthReleaseChannel(storedValue: nil) == .stable)
    }

    @Test func installedVersionReadsManagedExecutableOutput() async {
        let manager = CodexAuthToolManager(
            applicationSupportDirectory: URL(fileURLWithPath: "/Users/linda/Library/Application Support"),
            isExecutable: { $0 == "/Users/linda/Library/Application Support/CodexAuthHelper/codex-auth-tool/bin/codex-auth" },
            versionRunner: { executable, arguments, environment in
                #expect(executable == "/Users/linda/Library/Application Support/CodexAuthHelper/codex-auth-tool/bin/codex-auth")
                #expect(arguments == ["--version"])
                #expect(environment["PATH"] == "/Users/linda/Library/Application Support/CodexAuthHelper/codex-auth-tool/bin:/opt/homebrew/bin")
                return "codex-auth 0.3.0-alpha.9\n"
            }
        )

        let version = await manager.installedVersion()

        #expect(version == "codex-auth 0.3.0-alpha.9")
    }
}
