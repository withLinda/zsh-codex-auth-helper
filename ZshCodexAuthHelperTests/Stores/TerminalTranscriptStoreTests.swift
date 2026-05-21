import Foundation
import Testing
@testable import ZshCodexAuthHelper

@MainActor
struct TerminalTranscriptStoreTests {
    @Test func ansiWrappedDeviceCodeIsDetectedAndDisplayedCleanly() {
        let store = TerminalTranscriptStore()

        store.appendOutput(
            """
            2. Enter this one-time code \u{1B}[90m(expires in 15 minutes)\u{1B}[0m
               \u{1B}[94mY0Z1-JL1SR\u{1B}[0m
            """
        )

        #expect(store.latestDeviceCode == "Y0Z1-JL1SR")
        #expect(store.displayTranscript.contains("\u{1B}") == false)
        #expect(store.displayTranscript.contains("[94m") == false)
        #expect(store.displayTranscript.contains("[0m") == false)
        #expect(store.displayTranscript.contains("Y0Z1-JL1SR"))
    }

    @Test func visibleColorFragmentsAroundDeviceCodeAreRemoved() {
        let store = TerminalTranscriptStore()

        store.appendOutput(
            """
            2. Enter this one-time code [90m(expires in 15 minutes)[0m
               [94mY0Z1-JL1SR[0m
            """
        )

        #expect(store.latestDeviceCode == "Y0Z1-JL1SR")
        #expect(store.displayTranscript.contains("[94m") == false)
        #expect(store.displayTranscript.contains("[0m") == false)
        #expect(store.displayTranscript.contains("Y0Z1-JL1SR"))
    }

    @Test func deviceAuthTranscriptDetectsURLAndCodeTogether() {
        let store = TerminalTranscriptStore()

        store.appendOutput(
            """
            1. Open this link in your browser and sign in to your account
               [94mhttps://auth.openai.com/codex/device[0m

            2. Enter this one-time code [90m(expires in 15 minutes)[0m
               [94mY0Z1-JL1SR[0m
            """
        )

        #expect(store.latestURL?.absoluteString == "https://auth.openai.com/codex/device")
        #expect(store.latestDeviceCode == "Y0Z1-JL1SR")
    }

    @Test func startingNewCommandClearsDetectedLoginArtifactsButKeepsTranscriptHistory() {
        let store = TerminalTranscriptStore()
        store.appendOutput(
            """
            [94mhttps://auth.openai.com/codex/device[0m
            [94mY0Z1-JL1SR[0m
            """
        )

        store.start(
            CommandDefinition(
                title: "List Accounts",
                systemImage: "list.bullet",
                executable: "/usr/bin/env",
                arguments: ["true"],
                displayCommand: "codex-auth list"
            )
        )

        #expect(store.transcript.contains("Y0Z1-JL1SR"))
        #expect(store.latestURL == nil)
        #expect(store.latestDeviceCode == nil)
    }

    @Test func clearResetsTranscriptURLsAndDeviceCode() {
        let store = TerminalTranscriptStore()
        store.appendOutput(
            """
            [94mhttps://auth.openai.com/codex/device[0m
            [94mY0Z1-JL1SR[0m
            """
        )

        store.clear()

        #expect(store.transcript.isEmpty)
        #expect(store.displayTranscript.isEmpty)
        #expect(store.detectedURLs.isEmpty)
        #expect(store.latestDeviceCode == nil)
    }

    @Test func healthCheckAccountHighlightsUseTokenStatusColors() {
        let transcript = """
        Checking used@example.com...
        used@example.com: needs login; refresh token was already used
        revoked@example.com: needs login; refresh token was revoked
        fresh@example.com: refreshed
        api@example.com: skipped; API key auth does not use a refresh token
        Health Check finished: 1 refreshed, 1 skipped, 2 need attention.
        """

        let highlights = TerminalTranscriptParser.accountHighlights(in: transcript)

        #expect(highlightedAccounts(in: transcript, highlights: highlights) == [
            HighlightedAccount(email: "used@example.com", tone: .warning),
            HighlightedAccount(email: "revoked@example.com", tone: .destructive),
            HighlightedAccount(email: "fresh@example.com", tone: .success),
            HighlightedAccount(email: "api@example.com", tone: .success)
        ])
    }

    @Test func accountHighlightsIgnoreNonResultHealthCheckLines() {
        let transcript = """
        Health Check started for 2 saved accounts.
        Checking used@example.com...
        Health Check finished: 0 refreshed, 0 skipped, 0 need attention.
        """

        #expect(TerminalTranscriptParser.accountHighlights(in: transcript).isEmpty)
    }

    @Test func healthCheckFinishedEventShowsSortedCategorySummaries() {
        let summary = AuthHealthCheckSummary(
            results: [
                .init(accountKey: "z", email: "zeta@example.com", alias: nil, status: .reloginRequired(.revoked)),
                .init(accountKey: "b", email: "beta@example.com", alias: nil, status: .refreshed),
                .init(accountKey: "a", email: "alpha@example.com", alias: nil, status: .skippedAPIKey),
                .init(accountKey: "g", email: "gamma@example.com", alias: nil, status: .missingRefreshToken),
                .init(accountKey: "a2", email: "aisy@example.com", alias: nil, status: .refreshed)
            ]
        )

        #expect(summary.transcriptSummaryLine == """
        Health Check finished: 2 refreshed, 1 skipped, 2 need attention.

        Need attention:
        - gamma@example.com
        - zeta@example.com

        Refreshed:
        - aisy@example.com
        - beta@example.com

        Skipped:
        - alpha@example.com
        """)
    }

    @Test func healthCheckFinishedEventShowsNoneForEmptyCategories() {
        let summary = AuthHealthCheckSummary(results: [])

        #expect(summary.transcriptSummaryLine == """
        Health Check finished: 0 refreshed, 0 skipped, 0 need attention.

        Need attention:
        - None

        Refreshed:
        - None

        Skipped:
        - None
        """)
    }
}

private struct HighlightedAccount: Equatable {
    var email: String
    var tone: TerminalTranscriptAccountTone
}

private func highlightedAccounts(
    in transcript: String,
    highlights: [TerminalTranscriptAccountHighlight]
) -> [HighlightedAccount] {
    highlights.map { highlight in
        HighlightedAccount(
            email: String(transcript[highlight.range]),
            tone: highlight.tone
        )
    }
}
