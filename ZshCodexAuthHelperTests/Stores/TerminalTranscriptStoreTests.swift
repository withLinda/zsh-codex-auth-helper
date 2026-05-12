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
}
