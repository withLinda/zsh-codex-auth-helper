import Foundation

enum AuthSessionStatus: Equatable {
    case activeAuth
    case selectedFile
    case missingFile
    case unreadableAuth
    case noSignedInAccount
}

enum AuthSessionPlan: Equatable {
    case free
    case plus
    case proLite
    case pro
    case business
    case enterprise
    case edu
    case unknown

    init?(rawValue: String?) {
        guard let rawValue else {
            return nil
        }

        switch rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_") {
        case "free":
            self = .free
        case "plus":
            self = .plus
        case "pro_lite", "prolite":
            self = .proLite
        case "pro":
            self = .pro
        case "team", "business":
            self = .business
        case "enterprise":
            self = .enterprise
        case "edu":
            self = .edu
        case "unknown":
            self = .unknown
        case "":
            return nil
        default:
            self = .unknown
        }
    }

    var displayName: String {
        switch self {
        case .free:
            return "Free"
        case .plus:
            return "Plus"
        case .proLite:
            return "Pro Lite"
        case .pro:
            return "Pro"
        case .business:
            return "Business"
        case .enterprise:
            return "Enterprise"
        case .edu:
            return "Edu"
        case .unknown:
            return "Unknown"
        }
    }
}

struct AuthSessionInfo: Equatable {
    var status: AuthSessionStatus
    var email: String?
    var plan: AuthSessionPlan?
    var alias: String?
    var accountName: String?
    var accountKey: String?

    static let missingFile = AuthSessionInfo(status: .missingFile)
    static let unreadableAuth = AuthSessionInfo(status: .unreadableAuth)
    static let noSignedInAccount = AuthSessionInfo(status: .noSignedInAccount)

    init(
        status: AuthSessionStatus,
        email: String? = nil,
        plan: AuthSessionPlan? = nil,
        alias: String? = nil,
        accountName: String? = nil,
        accountKey: String? = nil
    ) {
        self.status = status
        self.email = email
        self.plan = plan
        self.alias = alias?.nilIfBlank
        self.accountName = accountName?.nilIfBlank
        self.accountKey = accountKey?.nilIfBlank
    }

    var title: String {
        if let email {
            return email
        }

        switch status {
        case .activeAuth, .selectedFile, .noSignedInAccount:
            return "No signed-in account"
        case .missingFile:
            return "No auth file"
        case .unreadableAuth:
            return "Unreadable auth"
        }
    }

    var detail: String {
        switch status {
        case .activeAuth:
            return detail(partsStartingWith: "Active auth")
        case .selectedFile:
            return detail(partsStartingWith: "Selected file")
        case .missingFile:
            return "Check auth path"
        case .unreadableAuth:
            return "Check JSON"
        case .noSignedInAccount:
            return "No email found"
        }
    }

    var needsAttention: Bool {
        switch status {
        case .activeAuth, .selectedFile:
            return false
        case .missingFile, .unreadableAuth, .noSignedInAccount:
            return true
        }
    }

    private func detail(partsStartingWith firstPart: String) -> String {
        var parts = [firstPart]
        if let plan {
            parts.append(plan.displayName)
        }
        if let alias {
            parts.append("Alias: \(alias)")
        } else if let accountName {
            parts.append(accountName)
        }
        return parts.joined(separator: " · ")
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
