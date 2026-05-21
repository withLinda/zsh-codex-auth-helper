import Foundation
import Testing
@testable import ZshCodexAuthHelper

struct ChromeIncognitoLinkOpenerTests {
    @Test func opensHTTPURLWithChromeIncognitoArguments() throws {
        let chromeAppURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        var requestedBundleIdentifiers: [String] = []
        var launchedExecutableURL: URL?
        var launchedArguments: [String] = []
        let opener = ChromeIncognitoLinkOpener(
            applicationURLForBundleIdentifier: { bundleIdentifier in
                requestedBundleIdentifiers.append(bundleIdentifier)
                return chromeAppURL
            },
            fileExists: { path in
                path == "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
            },
            launch: { executableURL, arguments in
                launchedExecutableURL = executableURL
                launchedArguments = arguments
            }
        )
        let url = try #require(URL(string: "https://auth.openai.com/codex/device"))

        try opener.open(url)

        #expect(requestedBundleIdentifiers == ["com.google.Chrome"])
        #expect(launchedExecutableURL?.path == "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        #expect(launchedArguments == [
            "--incognito",
            "https://auth.openai.com/codex/device"
        ])
    }

    @Test func opensBlankWindowWithDefaultChromeProfileIncognitoArguments() throws {
        let chromeAppURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        var launchedExecutableURL: URL?
        var launchedArguments: [String] = []
        let opener = ChromeIncognitoLinkOpener(
            applicationURLForBundleIdentifier: { _ in chromeAppURL },
            fileExists: { path in
                path == "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
            },
            launch: { executableURL, arguments in
                launchedExecutableURL = executableURL
                launchedArguments = arguments
            }
        )

        try opener.openBlankWindow()

        #expect(launchedExecutableURL?.path == "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        #expect(launchedArguments == ["--incognito"])
        #expect(launchedArguments.contains { $0.hasPrefix("--user-data-dir") } == false)
        #expect(launchedArguments.contains("--guest") == false)
    }

    @Test func opensHTTPSAndHTTPURLsOnly() throws {
        let opener = ChromeIncognitoLinkOpener(
            applicationURLForBundleIdentifier: { _ in URL(fileURLWithPath: "/Applications/Google Chrome.app") },
            fileExists: { _ in true },
            launch: { _, _ in }
        )
        let httpsURL = try #require(URL(string: "https://auth.openai.com/codex/device"))
        let httpURL = try #require(URL(string: "http://localhost:3000/login"))

        #expect(throws: Never.self) {
            try opener.open(httpsURL)
        }
        #expect(throws: Never.self) {
            try opener.open(httpURL)
        }
        #expect(throws: ChromeIncognitoLinkOpenerError.unsupportedURLScheme("file")) {
            try opener.open(URL(fileURLWithPath: "/tmp/auth.html"))
        }
    }

    @Test func reportsChromeMissingWithoutLaunching() throws {
        var didLaunch = false
        let opener = ChromeIncognitoLinkOpener(
            applicationURLForBundleIdentifier: { _ in nil },
            fileExists: { _ in true },
            launch: { _, _ in didLaunch = true }
        )
        let url = try #require(URL(string: "https://auth.openai.com/codex/device"))

        #expect(throws: ChromeIncognitoLinkOpenerError.chromeNotFound) {
            try opener.open(url)
        }
        #expect(didLaunch == false)
    }

    @Test func reportsMissingChromeExecutableWithoutLaunching() throws {
        var didLaunch = false
        let opener = ChromeIncognitoLinkOpener(
            applicationURLForBundleIdentifier: { _ in URL(fileURLWithPath: "/Applications/Google Chrome.app") },
            fileExists: { _ in false },
            launch: { _, _ in didLaunch = true }
        )
        let url = try #require(URL(string: "https://auth.openai.com/codex/device"))

        #expect(throws: ChromeIncognitoLinkOpenerError.chromeExecutableMissing("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")) {
            try opener.open(url)
        }
        #expect(didLaunch == false)
    }

    @Test func reportsLaunchFailure() throws {
        let opener = ChromeIncognitoLinkOpener(
            applicationURLForBundleIdentifier: { _ in URL(fileURLWithPath: "/Applications/Google Chrome.app") },
            fileExists: { _ in true },
            launch: { _, _ in throw TestLaunchError.failed }
        )
        let url = try #require(URL(string: "https://auth.openai.com/codex/device"))

        #expect(throws: ChromeIncognitoLinkOpenerError.launchFailed("failed")) {
            try opener.open(url)
        }
    }
}

private enum TestLaunchError: LocalizedError {
    case failed

    var errorDescription: String? {
        "failed"
    }
}
