import Foundation
import Testing
@testable import ZshCodexAuthHelper

struct CodexCommandFactoryTests {
    @Test func updateCodexAuthBuildsStableNpmInstallCommand() throws {
        let manager = CodexAuthToolManager(
            applicationSupportDirectory: URL(fileURLWithPath: "/Users/linda/Library/Application Support")
        )
        let resolver = ExecutableResolver(
            environmentPath: "/opt/homebrew/bin:/usr/bin",
            fileExists: { $0 == "/opt/homebrew/bin/npm" }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda"),
            codexAuthToolManager: manager
        )

        let command = try factory.updateCodexAuth(channel: .stable)

        #expect(command.id == "update-codex-auth")
        #expect(command.title == "Update codex-auth")
        #expect(command.executable == "/opt/homebrew/bin/npm")
        #expect(command.arguments == [
            "install",
            "--global",
            "--prefix",
            "/Users/linda/Library/Application Support/CodexAuthHelper/codex-auth-tool",
            "@loongphy/codex-auth@latest"
        ])
        #expect(command.environment["PATH"] == "/Users/linda/Library/Application Support/CodexAuthHelper/codex-auth-tool/bin:/opt/homebrew/bin:/usr/bin")
        #expect(command.displayCommand == "npm install --global --prefix '/Users/linda/Library/Application Support/CodexAuthHelper/codex-auth-tool' @loongphy/codex-auth@latest")
    }

    @Test func updateCodexAuthBuildsNextNpmInstallCommand() throws {
        let manager = CodexAuthToolManager(
            applicationSupportDirectory: URL(fileURLWithPath: "/Users/linda/Library/Application Support")
        )
        let resolver = ExecutableResolver(
            environmentPath: "/opt/homebrew/bin:/usr/bin",
            fileExists: { $0 == "/opt/homebrew/bin/npm" }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda"),
            codexAuthToolManager: manager
        )

        let command = try factory.updateCodexAuth(channel: .next)

        #expect(command.arguments.last == "@loongphy/codex-auth@next")
        #expect(command.displayCommand.hasSuffix("@loongphy/codex-auth@next"))
    }

    @Test func updateCodexAuthRequiresNpmExecutable() {
        let factory = CodexCommandFactory(
            resolver: .init(environmentPath: "/usr/bin:/bin", fileExists: { _ in false }),
            homeDirectory: URL(fileURLWithPath: "/Users/linda"),
            codexAuthToolManager: CodexAuthToolManager(
                applicationSupportDirectory: URL(fileURLWithPath: "/Users/linda/Library/Application Support")
            )
        )

        #expect(throws: CommandFactoryError.missingNPM) {
            _ = try factory.updateCodexAuth(channel: .stable)
        }
    }

    @Test func loginUsesCodexAuthAndPrependsResourcePathForBundledCodex() throws {
        let manager = CodexAuthToolManager(
            applicationSupportDirectory: URL(fileURLWithPath: "/Users/linda/Library/Application Support")
        )
        let resolver = ExecutableResolver(
            environmentPath: "/usr/bin:/bin",
            fileExists: {
                $0 == "/Applications/Codex.app/Contents/Resources/codex" ||
                    $0 == "/opt/homebrew/bin/codex-auth"
            }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda"),
            codexAuthToolManager: manager
        )

        let command = try factory.login()

        #expect(command.executable == "/opt/homebrew/bin/codex-auth")
        #expect(command.arguments == ["login", "--device-auth"])
        #expect(command.environment["PATH"] == "/Applications/Codex.app/Contents/Resources:/Users/linda/Library/Application Support/CodexAuthHelper/codex-auth-tool/bin:/opt/homebrew/bin:/usr/bin:/bin")
        #expect(command.displayCommand.contains("codex-auth login --device-auth"))
    }

    @Test func loginUsesCustomCodexResourceDirectoryForCodexAuthPath() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/usr/bin:/bin",
            fileExists: {
                $0 == "/Users/linda/Applications/Codex.app/Contents/Resources/codex" ||
                    $0 == "/opt/homebrew/bin/codex-auth"
            }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = try factory.login(
            codexResourceDirectory: "/Users/linda/Applications/Codex.app/Contents/Resources"
        )

        #expect(command.executable == "/opt/homebrew/bin/codex-auth")
        #expect(command.environment["PATH"] == "/Users/linda/Applications/Codex.app/Contents/Resources:/Users/linda/Library/Application Support/CodexAuthHelper/codex-auth-tool/bin:/opt/homebrew/bin:/usr/bin:/bin")
    }

    @Test func loginKeepsCustomResourceDirectoryOnPathWhenDirectoryIsInvalid() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/opt/homebrew/bin:/usr/bin",
            fileExists: { $0 == "/opt/homebrew/bin/codex-auth" }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = try factory.login(
            codexResourceDirectory: "/Users/linda/Missing Codex.app/Contents/Resources"
        )

        #expect(command.executable == "/opt/homebrew/bin/codex-auth")
        #expect(command.environment["PATH"] == "/Users/linda/Missing Codex.app/Contents/Resources:/Users/linda/Library/Application Support/CodexAuthHelper/codex-auth-tool/bin:/opt/homebrew/bin:/usr/bin")
    }

    @Test func loginDisplayCommandQuotesCustomPathSegmentWithSpaces() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/usr/bin:/bin",
            fileExists: {
                $0 == "/Users/linda/My Apps/Codex.app/Contents/Resources/codex" ||
                    $0 == "/opt/homebrew/bin/codex-auth"
            }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = try factory.login(
            codexResourceDirectory: "/Users/linda/My Apps/Codex.app/Contents/Resources"
        )

        #expect(command.displayCommand == "PATH='/Users/linda/My Apps/Codex.app/Contents/Resources':/opt/homebrew/bin:$PATH codex-auth login --device-auth")
    }

    @Test func loginUsesDefaultResourceDirectoryWhenSettingIsBlank() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/usr/bin:/bin",
            fileExists: {
                $0 == "/Applications/Codex.app/Contents/Resources/codex" ||
                    $0 == "/opt/homebrew/bin/codex-auth"
            }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = try factory.login(codexResourceDirectory: "   ")

        #expect(command.executable == "/opt/homebrew/bin/codex-auth")
        #expect(command.environment["PATH"] == "/Applications/Codex.app/Contents/Resources:/Users/linda/Library/Application Support/CodexAuthHelper/codex-auth-tool/bin:/opt/homebrew/bin:/usr/bin:/bin")
    }

    @Test func loginRequiresCodexAuthExecutable() throws {
        let factory = CodexCommandFactory(
            resolver: .init(environmentPath: "/usr/bin:/bin", fileExists: { _ in false }),
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        #expect(throws: CommandFactoryError.missingExecutable("codex-auth")) {
            _ = try factory.login()
        }
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

    @Test func importAuthOmitsAliasArgumentWhenAliasIsEmpty() throws {
        let factory = CodexCommandFactory(
            resolver: .init(environmentPath: "/opt/homebrew/bin", fileExists: { $0 == "/opt/homebrew/bin/codex-auth" }),
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = try factory.importAuth(authFilePath: "/Users/linda/.codex/auth.json", alias: "   ")

        #expect(command.executable == "/opt/homebrew/bin/codex-auth")
        #expect(command.arguments == [
            "import",
            "/Users/linda/.codex/auth.json"
        ])
        #expect(command.displayCommand == "codex-auth import /Users/linda/.codex/auth.json")
    }

    @Test func switchAccountPassesQueryAsSeparateArgument() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/opt/homebrew/bin",
            fileExists: { $0 == "/opt/homebrew/bin/codex-auth" }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = try factory.switchAccount(query: "damar")

        #expect(command.executable == "/opt/homebrew/bin/codex-auth")
        #expect(command.arguments == ["switch", "damar"])
        #expect(command.displayCommand == "codex-auth switch damar")
    }

    @Test func switchAccountDisplayCommandQuotesSpacedQueryButKeepsOneArgument() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/opt/homebrew/bin",
            fileExists: { $0 == "/opt/homebrew/bin/codex-auth" }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = try factory.switchAccount(query: "personal account")

        #expect(command.arguments == ["switch", "personal account"])
        #expect(command.displayCommand == "codex-auth switch 'personal account'")
    }

    @Test func switchAccountDisplayCommandEscapesQuotedQueryButKeepsOneArgument() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/opt/homebrew/bin",
            fileExists: { $0 == "/opt/homebrew/bin/codex-auth" }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = try factory.switchAccount(query: "dama'r")

        #expect(command.arguments == ["switch", "dama'r"])
        #expect(command.displayCommand == #"codex-auth switch 'dama'\''r'"#)
    }

    @Test func switchAccountRejectsEmptyQuery() {
        let factory = CodexCommandFactory(
            resolver: .init(environmentPath: "", fileExists: { _ in true }),
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        #expect(throws: CommandFactoryError.self) {
            try factory.switchAccount(query: "   ")
        }
    }

    @Test func commandDraftParserBuildsSwitchCommandFromPreparedDraft() throws {
        let draft = try CommandDraftParser.parse("codex-auth switch damar")

        #expect(draft == .switchAccount(query: "damar"))
    }

    @Test func commandDraftParserBuildsRemoveCommandFromPreparedDraft() throws {
        let draft = try CommandDraftParser.parse("codex-auth remove damar")

        #expect(draft == .removeAccount(query: "damar"))
    }

    @Test func commandDraftParserRejectsBareSwitchDraft() {
        #expect(throws: CommandDraftParseError.missingSwitchQuery) {
            try CommandDraftParser.parse("codex-auth switch ")
        }
    }

    @Test func commandDraftParserRejectsBareRemoveDraft() {
        #expect(throws: CommandDraftParseError.missingRemoveSelector) {
            try CommandDraftParser.parse("codex-auth remove ")
        }
    }

    @Test func commandDraftParserRejectsUnsupportedCommands() {
        #expect(throws: CommandDraftParseError.unsupportedCommand) {
            try CommandDraftParser.parse("codex-auth list")
        }
    }

    @Test func commandDraftParserUnsupportedCommandMessageMentionsSwitchAndRemove() {
        do {
            _ = try CommandDraftParser.parse("codex-auth list")
            Issue.record("Expected unsupported command to throw.")
        } catch let error as CommandDraftParseError {
            #expect(error.localizedDescription == "Only codex-auth switch <selector> or codex-auth remove <selector> can run from this input.")
        } catch {
            Issue.record("Wrong error thrown: \(error)")
        }
    }

    @Test func removeAccountPassesSelectorAsSeparateArgument() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/opt/homebrew/bin",
            fileExists: { $0 == "/opt/homebrew/bin/codex-auth" }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = try factory.remove(query: "damar")

        #expect(command.executable == "/opt/homebrew/bin/codex-auth")
        #expect(command.arguments == ["remove", "damar"])
        #expect(command.displayCommand == "codex-auth remove damar")
    }

    @Test func removeAccountDisplayCommandQuotesSpacedSelectorButKeepsOneArgument() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/opt/homebrew/bin",
            fileExists: { $0 == "/opt/homebrew/bin/codex-auth" }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = try factory.remove(query: "personal account")

        #expect(command.arguments == ["remove", "personal account"])
        #expect(command.displayCommand == "codex-auth remove 'personal account'")
    }

    @Test func removeAccountDisplayCommandEscapesQuotedSelectorButKeepsOneArgument() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/opt/homebrew/bin",
            fileExists: { $0 == "/opt/homebrew/bin/codex-auth" }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = try factory.remove(query: "dama'r")

        #expect(command.arguments == ["remove", "dama'r"])
        #expect(command.displayCommand == #"codex-auth remove 'dama'\''r'"#)
    }

    @Test func removeAccountRejectsEmptySelector() {
        let factory = CodexCommandFactory(
            resolver: .init(environmentPath: "", fileExists: { _ in true }),
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        #expect(throws: CommandFactoryError.missingRemoveSelector) {
            try factory.remove(query: "   ")
        }
    }

    @Test func removeAccountNeverBuildsRemoveAllForRowSelector() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/opt/homebrew/bin",
            fileExists: { $0 == "/opt/homebrew/bin/codex-auth" }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = try factory.remove(query: "2")

        #expect(command.arguments == ["remove", "2"])
        #expect(command.arguments.contains("--all") == false)
    }

    @Test func removeAccountIsMarkedDestructive() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/opt/homebrew/bin",
            fileExists: { $0 == "/opt/homebrew/bin/codex-auth" }
        )
        let factory = CodexCommandFactory(
            resolver: resolver,
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = try factory.remove(query: "damar")

        #expect(command.arguments == ["remove", "damar"])
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
        #expect(script.contains("waitForCodexExit 30 0.1"))
        #expect(script.contains("waitForCodexExit 10 0.1"))
        #expect(script.contains("waitForCodexExit 20 0.1"))
        #expect(script.contains("waitForCodexExit 100 0.1") == false)
        #expect(script.contains("waitForCodexExit 50 0.1") == false)
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

    @Test func openCodexOpensConfiguredAppBundleAndFallsBackToBundleIdentifier() throws {
        let factory = CodexCommandFactory(
            resolver: .init(environmentPath: "", fileExists: { _ in false }),
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = factory.openCodex(
            codexResourceDirectory: "/Users/linda/My Apps/Codex.app/Contents/Resources"
        )
        let script = try #require(command.arguments.last)

        #expect(command.id == "open-codex")
        #expect(command.title == "Open Codex")
        #expect(command.arguments.first == "-lc")
        #expect(script.contains("app_bundle='/Users/linda/My Apps/Codex.app'"))
        #expect(script.contains(#"/usr/bin/open "$app_bundle""#))
        #expect(script.contains(#"/usr/bin/open -b "$bundle_id""#))
        #expect(command.displayCommand == "open '/Users/linda/My Apps/Codex.app'")
    }

    @Test func forceCloseCodexTerminatesConfiguredCodexProcessesWithoutReopening() throws {
        let factory = CodexCommandFactory(
            resolver: .init(environmentPath: "", fileExists: { _ in false }),
            homeDirectory: URL(fileURLWithPath: "/Users/linda")
        )

        let command = factory.forceCloseCodex(
            codexResourceDirectory: "/Users/linda/My Apps/Codex.app/Contents/Resources"
        )
        let script = try #require(command.arguments.last)

        #expect(command.id == "force-close-codex")
        #expect(command.title == "Force Close Codex")
        #expect(command.risk == .destructive)
        #expect(script.contains("app_bundle='/Users/linda/My Apps/Codex.app'"))
        #expect(script.contains(#"process_marker="${app_bundle}/Contents/""#))
        #expect(script.contains("signalCodex TERM"))
        #expect(script.contains("signalCodex KILL"))
        #expect(script.contains("/usr/bin/open") == false)
        #expect(command.displayCommand == "force close Codex at '/Users/linda/My Apps/Codex.app'")
    }
}
