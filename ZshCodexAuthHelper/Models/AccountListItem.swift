import Foundation

struct AccountListItem: Identifiable, Equatable, Sendable {
    var id: String { accountKey }

    var accountKey: String
    var email: String
    var alias: String?
    var accountName: String?
    var plan: String?
    var authMode: String?
    var isActive: Bool
    var rowNumber: Int
    var safeSelector: String
    var lastUsageAt: String?

    var isAPIKeyAccount: Bool {
        authMode?.localizedCaseInsensitiveCompare("apikey") == .orderedSame
    }

    var planLabel: String {
        if isAPIKeyAccount {
            return "API Key"
        }

        guard let plan = plan?.trimmedNonEmpty else {
            return "Unknown"
        }

        return plan
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    var subtitleParts: [String] {
        var parts: [String] = []
        if let alias {
            parts.append("Alias: \(alias)")
        }
        if let accountName {
            parts.append(accountName)
        }
        if let lastUsageAt {
            parts.append("Last use: \(lastUsageAt)")
        }
        return parts
    }
}
