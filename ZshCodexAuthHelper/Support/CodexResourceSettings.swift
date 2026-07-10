import Foundation

enum CodexResourceSettings {
    static let userDefaultsKey = "codexResourceDirectory"
    static let bundleIdentifier = "com.openai.codex"
    static let defaultDirectory = "/Applications/ChatGPT.app/Contents/Resources"
    static let legacyDefaultDirectory = "/Applications/Codex.app/Contents/Resources"

    static func normalizedDirectory(_ directory: String) -> String {
        let trimmedDirectory = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedDirectory.isEmpty == false else {
            return defaultDirectory
        }
        return NSString(string: trimmedDirectory).expandingTildeInPath
    }

    static func resolvedDirectory(
        _ directory: String,
        isExecutableFile: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String {
        let normalizedDirectory = normalizedDirectory(directory)
        let legacyExecutablePath = codexExecutablePath(in: legacyDefaultDirectory)
        let currentExecutablePath = codexExecutablePath(in: defaultDirectory)
        if normalizedDirectory == legacyDefaultDirectory,
           isExecutableFile(legacyExecutablePath) == false,
           isExecutableFile(currentExecutablePath) {
            return defaultDirectory
        }

        if normalizedDirectory == defaultDirectory,
           isExecutableFile(currentExecutablePath) == false,
           isExecutableFile(legacyExecutablePath) {
            return legacyDefaultDirectory
        }

        return normalizedDirectory
    }

    static func codexExecutablePath(in directory: String) -> String {
        URL(fileURLWithPath: normalizedDirectory(directory))
            .appendingPathComponent("codex")
            .path
    }

    static func codexAppBundlePath(forResourceDirectory directory: String) -> String {
        let resourceURL = URL(fileURLWithPath: normalizedDirectory(directory)).standardizedFileURL

        if resourceURL.lastPathComponent == "Resources" {
            let contentsURL = resourceURL.deletingLastPathComponent()
            if contentsURL.lastPathComponent == "Contents" {
                return contentsURL.deletingLastPathComponent().path
            }
        }

        if resourceURL.pathExtension == "app" {
            return resourceURL.path
        }

        return URL(fileURLWithPath: defaultDirectory)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }

    static func appDisplayName(forAppBundlePath path: String) -> String {
        let appName = URL(fileURLWithPath: path)
            .deletingPathExtension()
            .lastPathComponent
        return appName.isEmpty ? "ChatGPT" : appName
    }
}
