import Foundation
import Testing
@testable import ZshCodexAuthHelper

struct ExecutableResolverTests {
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
}

