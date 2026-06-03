import Foundation
import Testing
@testable import ZshCodexAuthHelper

struct ExecutableResolverTests {
    @Test func resolvePrefersAppOwnedCodexAuthBeforeGlobalPath() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/opt/homebrew/bin:/usr/bin",
            preferredDirectories: ["/Users/linda/Library/Application Support/CodexAuthHelper/codex-auth-tool/bin"],
            fileExists: {
                $0 == "/Users/linda/Library/Application Support/CodexAuthHelper/codex-auth-tool/bin/codex-auth" ||
                    $0 == "/opt/homebrew/bin/codex-auth"
            }
        )

        let path = try #require(resolver.resolve("codex-auth"))

        #expect(path == "/Users/linda/Library/Application Support/CodexAuthHelper/codex-auth-tool/bin/codex-auth")
    }

    @Test func resolveFindsExecutableFromEnvironmentPath() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/bin:/opt/homebrew/bin:/usr/bin",
            fileExists: { $0 == "/opt/homebrew/bin/codex-auth" }
        )

        let path = try #require(resolver.resolve("codex-auth"))

        #expect(path == "/opt/homebrew/bin/codex-auth")
    }

    @Test func resolveUsesFallbackHomebrewPathWhenGuiEnvironmentIsSparse() throws {
        let resolver = ExecutableResolver(
            environmentPath: "/usr/bin:/bin",
            fileExists: { $0 == "/opt/homebrew/bin/codex-auth" }
        )

        let path = try #require(resolver.resolve("codex-auth"))

        #expect(path == "/opt/homebrew/bin/codex-auth")
    }

    @Test func pathByPrependingAvoidsDuplicateResourcePath() {
        let resolver = ExecutableResolver(
            environmentPath: "/Applications/Codex.app/Contents/Resources:/usr/bin",
            fileExists: { _ in false }
        )

        #expect(
            resolver.pathByPrepending("/Applications/Codex.app/Contents/Resources")
            == "/Applications/Codex.app/Contents/Resources:/usr/bin"
        )
    }

    @Test func pathByPrependingMultipleDirectoriesKeepsStableOrderAndAvoidsDuplicates() {
        let resolver = ExecutableResolver(
            environmentPath: "/opt/homebrew/bin:/usr/bin",
            fileExists: { _ in false }
        )

        #expect(
            resolver.pathByPrepending([
                "/Users/linda/Library/Application Support/CodexAuthHelper/codex-auth-tool/bin",
                "/opt/homebrew/bin"
            ])
            == "/Users/linda/Library/Application Support/CodexAuthHelper/codex-auth-tool/bin:/opt/homebrew/bin:/usr/bin"
        )
    }
}
