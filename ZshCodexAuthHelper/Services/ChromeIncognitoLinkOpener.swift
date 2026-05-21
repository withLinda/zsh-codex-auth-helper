import AppKit
import Foundation

enum ChromeIncognitoLinkOpenerError: LocalizedError, Equatable {
    case unsupportedURLScheme(String?)
    case chromeNotFound
    case chromeExecutableMissing(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedURLScheme:
            return "Only http and https login links can be opened in Chrome Incognito."
        case .chromeNotFound:
            return "Google Chrome was not found. Install Chrome, then open the login link again."
        case .chromeExecutableMissing(let path):
            return "Google Chrome could not be opened because its executable was not found at \(path)."
        case .launchFailed(let message):
            return "Could not open Chrome Incognito: \(message)"
        }
    }
}

struct ChromeIncognitoLinkOpener {
    private static let chromeBundleIdentifier = "com.google.Chrome"
    private static let chromeExecutablePath = "Contents/MacOS/Google Chrome"

    private let applicationURLForBundleIdentifier: (String) -> URL?
    private let fileExists: (String) -> Bool
    private let launch: (URL, [String]) throws -> Void

    init(
        applicationURLForBundleIdentifier: @escaping (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        },
        fileExists: @escaping (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        },
        launch: @escaping (URL, [String]) throws -> Void = Self.launchProcess
    ) {
        self.applicationURLForBundleIdentifier = applicationURLForBundleIdentifier
        self.fileExists = fileExists
        self.launch = launch
    }

    func open(_ url: URL) throws {
        guard url.scheme == "http" || url.scheme == "https" else {
            throw ChromeIncognitoLinkOpenerError.unsupportedURLScheme(url.scheme)
        }

        guard let chromeAppURL = applicationURLForBundleIdentifier(Self.chromeBundleIdentifier) else {
            throw ChromeIncognitoLinkOpenerError.chromeNotFound
        }

        let executableURL = chromeAppURL.appendingPathComponent(Self.chromeExecutablePath)
        guard fileExists(executableURL.path) else {
            throw ChromeIncognitoLinkOpenerError.chromeExecutableMissing(executableURL.path)
        }

        do {
            try launch(executableURL, ["--incognito", url.absoluteString])
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw ChromeIncognitoLinkOpenerError.launchFailed(message)
        }
    }

    private static func launchProcess(executableURL: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        try process.run()
    }
}
