import Foundation

enum CodexResourceSettings {
    static let userDefaultsKey = "codexResourceDirectory"
    static let defaultDirectory = "/Applications/Codex.app/Contents/Resources"

    static func normalizedDirectory(_ directory: String) -> String {
        let trimmedDirectory = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedDirectory.isEmpty == false else {
            return defaultDirectory
        }
        return NSString(string: trimmedDirectory).expandingTildeInPath
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
}
