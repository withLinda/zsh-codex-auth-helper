import Foundation
import Testing
@testable import ZshCodexAuthHelper

struct CodexCommandFactoryTests {
    @Test func loginUsesBundledCodexAndPrependsResourcePath() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/usr/bin:/bin",
            fileExists: { $0 == "/Applications/Codex.app/Contents/Resources/codex" }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = factory.login()

        #expect(command.executable == "/Applications/Codex.app/Contents/Resources/codex")
        #expect(command.arguments == ["login", "--device-auth"])
        #expect(command.environment["PATH"] == "/Applications/Codex.app/Contents/Resources:/usr/bin:/bin")
        #expect(command.displayCommand.contains("codex login --device-auth"))
    }

    @Test func loginUsesCustomCodexResourceDirectoryWhenExecutableExists() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/usr/bin:/bin",
            fileExists: { $0 == "/Users/linda/Applications/Codex.app/Contents/Resources/codex" }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = factory.login(
            codexResourceDirectory: "/Users/linda/Applications/Codex.app/Contents/Resources"
        )

        #expect(command.executable == "/Users/linda/Applications/Codex.app/Contents/Resources/codex")
        #expect(command.environment["PATH"] == "/Users/linda/Applications/Codex.app/Contents/Resources:/usr/bin:/bin")
    }

    @Test func loginFallsBackToCodexFromEnvironmentPathWhenCustomDirectoryIsInvalid() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/opt/homebrew/bin:/usr/bin",
            fileExists: { $0 == "/opt/homebrew/bin/codex" }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = factory.login(
            codexResourceDirectory: "/Users/linda/Missing Codex.app/Contents/Resources"
        )

        #expect(command.executable == "/opt/homebrew/bin/codex")
        #expect(command.environment["PATH"] == "/Users/linda/Missing Codex.app/Contents/Resources:/opt/homebrew/bin:/usr/bin")
    }

    @Test func loginDisplayCommandQuotesCustomPathSegmentWithSpaces() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/usr/bin:/bin",
            fileExists: { $0 == "/Users/linda/My Apps/Codex.app/Contents/Resources/codex" }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = factory.login(
            codexResourceDirectory: "/Users/linda/My Apps/Codex.app/Contents/Resources"
        )

        #expect(command.displayCommand == "PATH='/Users/linda/My Apps/Codex.app/Contents/Resources':$PATH codex login --device-auth")
    }

    @Test func loginUsesDefaultResourceDirectoryWhenSettingIsBlank() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/usr/bin:/bin",
            fileExists: { $0 == "/Applications/Codex.app/Contents/Resources/codex" }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = factory.login(codexResourceDirectory: "   ")

        #expect(command.executable == "/Applications/Codex.app/Contents/Resources/codex")
        #expect(command.environment["PATH"] == "/Applications/Codex.app/Contents/Resources:/usr/bin:/bin")
    }

    @Test func importAuthPassesAliasAsSeparateArgument() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/opt/homebrew/bin:/usr/bin",
            fileExists: { $0 == "/opt/homebrew/bin/codex-auth" }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = try factory.importAuth(
            authFilePath: "/Users/linda/.codex/auth.json",
            alias: "personal account"
        )

        #expect(command.executable == "/opt/homebrew/bin/codex-auth")
        #expect(command.arguments == [
            "import",
            "/Users/linda/.codex/auth.json",
            "--alias",
            "personal account"
        ])
        #expect(command.displayCommand.contains("'personal account'"))
    }

    @Test func importAuthRejectsEmptyAlias() {
        let factory = CodexCommandFactory(
            resolver: .init(environmentPath: "", fileExists: { _ in true }),
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        #expect(throws: CommandFactoryError.self) {
            try factory.importAuth(authFilePath: "/Users/linda/.codex/auth.json", alias: "   ")
        }
    }

    @Test func removeCommandIsMarkedDestructive() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/opt/homebrew/bin",
            fileExists: { $0 == "/opt/homebrew/bin/codex-auth" }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = try factory.remove()

        #expect(command.arguments == ["remove"])
        #expect(command.risk == .destructive)
    }

    @Test func restartUsesBundleIdentifierAndWaitsForCodexProcesses() throws {
        let factory = CodexCommandFactory(
            resolver: .init(environmentPath: "", fileExists: { _ in false }),
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = factory.restartCodex()
        let script = try #require(command.arguments.last)

        #expect(command.arguments.first == "-lc")
        #expect(script.contains(#"tell application id "com.openai.codex" to quit"#))
        #expect(script.contains("osascript quit Codex") == false)
        #expect(script.contains("pkill -9 -x Codex") == false)
        #expect(command.displayCommand.contains("osascript quit Codex") == false)
        #expect(command.displayCommand.contains("pkill -9 -x Codex") == false)
        #expect(script.contains("waitForCodexExit 100 0.1"))
        #expect(script.contains("waitForCodexExit 20 0.1"))
        #expect(script.contains("/usr/bin/open \"$app_bundle\""))
        #expect(script.contains("/usr/bin/open -b \"$bundle_id\""))
    }

    @Test func restartUsesCustomCodexAppBundleDerivedFromResourceDirectory() throws {
        let factory = CodexCommandFactory(
            resolver: .init(environmentPath: "", fileExists: { _ in false }),
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = factory.restartCodex(
            codexResourceDirectory: "/Users/linda/Apps/Codex.app/Contents/Resources"
        )
        let script = try #require(command.arguments.last)

        #expect(CodexResourceSettings.codexAppBundlePath(
            forResourceDirectory: "/Users/linda/Apps/Codex.app/Contents/Resources"
        ) == "/Users/linda/Apps/Codex.app")
        #expect(script.contains("app_bundle=/Users/linda/Apps/Codex.app"))
        #expect(script.contains(#"process_marker="${app_bundle}/Contents/""#))
    }
}
