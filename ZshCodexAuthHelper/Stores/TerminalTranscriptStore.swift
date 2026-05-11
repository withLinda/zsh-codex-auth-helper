import Foundation

@MainActor
final class TerminalTranscriptStore: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var runningCommandTitle: String?
    @Published private(set) var lastExitCode: Int32?
    @Published private(set) var detectedURLs: [URL] = []

    var isRunning: Bool {
        runningCommandTitle != nil
    }

    var latestURL: URL? {
        detectedURLs.last
    }

    func start(_ command: CommandDefinition) {
        runningCommandTitle = command.title
        lastExitCode = nil
        appendSystemLine("$ \(command.displayCommand)")
    }

    func appendOutput(_ output: String) {
        transcript += output
        updateDetectedURLs()
    }

    func appendSystemLine(_ line: String) {
        if transcript.isEmpty == false, transcript.hasSuffix("\n") == false {
            transcript += "\n"
        }
        transcript += "\(line)\n"
        updateDetectedURLs()
    }

    func finish(_ result: PTYCommandResult) {
        runningCommandTitle = nil
        lastExitCode = result.exitCode
        appendSystemLine("Finished with exit code \(result.exitCode).")
    }

    func failToStart(_ error: Error) {
        runningCommandTitle = nil
        appendSystemLine("Could not start command: \(error.localizedDescription)")
    }

    func clear() {
        transcript = ""
        lastExitCode = nil
        detectedURLs = []
    }

    private func updateDetectedURLs() {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return
        }

        let range = NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
        let urls = detector.matches(in: transcript, options: [], range: range).compactMap(\.url)
        detectedURLs = Array(urls.suffix(4))
    }
}

