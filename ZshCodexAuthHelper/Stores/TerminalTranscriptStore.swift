import Foundation

@MainActor
final class TerminalTranscriptStore: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var displayTranscript = ""
    @Published private(set) var runningCommandTitle: String?
    @Published private(set) var lastExitCode: Int32?
    @Published private(set) var detectedURLs: [URL] = []
    @Published private(set) var latestDeviceCode: String?

    private var currentCommandTranscript = ""

    var isRunning: Bool {
        runningCommandTitle != nil
    }

    var latestURL: URL? {
        detectedURLs.last
    }

    func start(_ command: CommandDefinition) {
        runningCommandTitle = command.title
        lastExitCode = nil
        resetDetectedArtifacts()
        currentCommandTranscript = ""
        appendSystemLine("$ \(command.displayCommand)")
    }

    func appendOutput(_ output: String) {
        transcript += output
        currentCommandTranscript += output
        updateTranscriptArtifacts()
    }

    func appendSystemLine(_ line: String) {
        if transcript.isEmpty == false, transcript.hasSuffix("\n") == false {
            transcript += "\n"
        }
        transcript += "\(line)\n"
        currentCommandTranscript += "\(line)\n"
        updateTranscriptArtifacts()
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
        displayTranscript = ""
        lastExitCode = nil
        currentCommandTranscript = ""
        resetDetectedArtifacts()
    }

    private func updateTranscriptArtifacts() {
        displayTranscript = TerminalTranscriptParser.clean(transcript)
        let currentDisplayTranscript = TerminalTranscriptParser.clean(currentCommandTranscript)
        updateDetectedURLs(in: currentDisplayTranscript)
        latestDeviceCode = TerminalTranscriptParser.latestDeviceCode(in: currentDisplayTranscript)
    }

    private func updateDetectedURLs(in text: String) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let urls = detector.matches(in: text, options: [], range: range).compactMap(\.url)
        detectedURLs = Array(urls.suffix(4))
    }

    private func resetDetectedArtifacts() {
        detectedURLs = []
        latestDeviceCode = nil
    }
}

enum TerminalTranscriptAccountTone: Equatable {
    case success
    case warning
    case destructive
}

struct TerminalTranscriptAccountHighlight: Equatable {
    var range: Range<String.Index>
    var tone: TerminalTranscriptAccountTone
}

enum TerminalTranscriptParser {
    static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: "\u{001B}\\[[0-?]*[ -/]*[@-~]",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\[(?:\d{1,3})(?:;\d{1,3})*m"#,
                with: "",
                options: .regularExpression
            )
    }

    static func latestDeviceCode(in text: String) -> String? {
        let pattern = #"\b[A-Z0-9]{4,8}-[A-Z0-9]{4,8}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex
            .matches(in: text, range: range)
            .last
            .flatMap { Range($0.range, in: text) }
            .map { String(text[$0]) }
    }

    static func accountHighlights(in text: String) -> [TerminalTranscriptAccountHighlight] {
        var highlights: [TerminalTranscriptAccountHighlight] = []
        var lineStart = text.startIndex

        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex

            if let highlight = accountHighlight(in: text, lineStart: lineStart, lineEnd: lineEnd) {
                highlights.append(highlight)
            }

            guard lineEnd < text.endIndex else {
                break
            }

            lineStart = text.index(after: lineEnd)
        }

        return highlights
    }

    private static func accountHighlight(
        in text: String,
        lineStart: String.Index,
        lineEnd: String.Index
    ) -> TerminalTranscriptAccountHighlight? {
        guard let colon = text[lineStart..<lineEnd].firstIndex(of: ":") else {
            return nil
        }

        let emailRange = lineStart..<colon
        let email = String(text[emailRange])
        guard email.isEmpty == false,
              email.contains("@"),
              email.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return nil
        }

        let afterColon = text.index(after: colon)
        guard afterColon < lineEnd, text[afterColon] == " " else {
            return nil
        }

        let statusStart = text.index(after: afterColon)
        let status = String(text[statusStart..<lineEnd])
        guard let tone = accountTone(for: status) else {
            return nil
        }

        return TerminalTranscriptAccountHighlight(range: emailRange, tone: tone)
    }

    private static func accountTone(for status: String) -> TerminalTranscriptAccountTone? {
        guard isHealthCheckResultStatus(status) else {
            return nil
        }

        if status.contains("refresh token was revoked") {
            return .destructive
        }

        if status.contains("refresh token was already used") {
            return .warning
        }

        return .success
    }

    private static func isHealthCheckResultStatus(_ status: String) -> Bool {
        status == "refreshed"
            || status.hasPrefix("skipped; ")
            || status.hasPrefix("needs login; ")
            || status.hasPrefix("failed; ")
    }
}
