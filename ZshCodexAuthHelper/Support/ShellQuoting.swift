import Foundation

enum ShellQuoting {
    static func quote(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }

        let safeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-=/:.,@")
        if value.rangeOfCharacter(from: safeCharacters.inverted) == nil {
            return value
        }

        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func displayCommand(executable: String, arguments: [String]) -> String {
        ([executable] + arguments).map(quote).joined(separator: " ")
    }
}
