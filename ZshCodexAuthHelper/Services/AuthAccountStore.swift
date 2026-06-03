import Foundation

enum AuthAccountStoreError: LocalizedError, Equatable {
    case missingRegistry
    case unreadableRegistry
    case unreadableAuth

    var errorDescription: String? {
        switch self {
        case .missingRegistry:
            return "No codex-auth registry was found."
        case .unreadableRegistry:
            return "Registry could not be read."
        case .unreadableAuth:
            return "Auth file could not be read."
        }
    }
}

struct AuthAccountStore {
    let homeDirectory: URL
    let fileManager: FileManager

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    var accountsDirectoryURL: URL {
        homeDirectory.appendingPathComponent(".codex/accounts", isDirectory: true)
    }

    var activeAuthURL: URL {
        homeDirectory.appendingPathComponent(".codex/auth.json")
    }

    var registryURL: URL {
        accountsDirectoryURL.appendingPathComponent("registry.json")
    }

    func readRegistry() throws -> AuthAccountRegistry {
        guard fileManager.fileExists(atPath: registryURL.path) else {
            throw AuthAccountStoreError.missingRegistry
        }

        do {
            return try JSONDecoder().decode(AuthAccountRegistry.self, from: Data(contentsOf: registryURL))
        } catch {
            throw AuthAccountStoreError.unreadableRegistry
        }
    }

    func accountAuthURL(accountKey: String) -> URL {
        accountsDirectoryURL.appendingPathComponent("\(Self.accountFileKey(accountKey)).auth.json")
    }

    func existingAccountAuthURL(accountKey: String) -> URL {
        let preferredURL = accountAuthURL(accountKey: accountKey)
        if fileManager.fileExists(atPath: preferredURL.path) {
            return preferredURL
        }

        let encodedURL = accountsDirectoryURL.appendingPathComponent("\(Self.encodedAccountKey(accountKey)).auth.json")
        if encodedURL.path != preferredURL.path,
           fileManager.fileExists(atPath: encodedURL.path) {
            return encodedURL
        }

        return preferredURL
    }

    static func accountFileKey(_ accountKey: String) -> String {
        if keyNeedsFilenameEncoding(accountKey) {
            return encodedAccountKey(accountKey)
        }
        return accountKey
    }

    static func encodedAccountKey(_ accountKey: String) -> String {
        Data(accountKey.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func keyNeedsFilenameEncoding(_ key: String) -> Bool {
        guard key.isEmpty == false, key != ".", key != ".." else {
            return true
        }

        return key.unicodeScalars.contains { scalar in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", "-", "_", ".":
                return false
            default:
                return true
            }
        }
    }
}

struct AuthAccountRegistry: Decodable, Equatable, Sendable {
    static let empty = AuthAccountRegistry(activeAccountKey: nil, accounts: [])

    var activeAccountKey: String?
    var accounts: [AuthAccountRecord]

    var activeRecord: AuthAccountRecord? {
        activeAccountKey.flatMap { record(accountKey: $0) }
    }

    enum CodingKeys: String, CodingKey {
        case activeAccountKey = "active_account_key"
        case accounts
    }

    func record(accountKey: String) -> AuthAccountRecord? {
        accounts.first { $0.accountKey == accountKey }
    }

    func displayOrderedAccounts() -> [AuthAccountRecord] {
        accounts.sorted { lhs, rhs in
            if lhs.email != rhs.email {
                return lhs.email < rhs.email
            }

            let lhsActive = activeAccountKey == lhs.accountKey
            let rhsActive = activeAccountKey == rhs.accountKey
            if lhsActive != rhsActive {
                return lhsActive
            }

            let lhsRank = Self.planSortRank(lhs.displayPlan)
            let rhsRank = Self.planSortRank(rhs.displayPlan)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }

            if lhs.displayPlan != rhs.displayPlan {
                return lhs.displayPlan < rhs.displayPlan
            }

            return lhs.accountKey < rhs.accountKey
        }
    }

    private static func planSortRank(_ plan: String) -> Int {
        switch plan {
        case "team", "business", "enterprise", "edu":
            return 0
        case "free", "plus", "prolite", "pro":
            return 1
        default:
            return 2
        }
    }
}

struct AuthAccountRecord: Decodable, Equatable, Sendable {
    var accountKey: String
    var chatgptAccountID: String
    var chatgptUserID: String
    var email: String
    var alias: String
    var accountName: String?
    var plan: String?
    var authMode: String?
    var lastUsageAt: String?

    enum CodingKeys: String, CodingKey {
        case accountKey = "account_key"
        case chatgptAccountID = "chatgpt_account_id"
        case chatgptUserID = "chatgpt_user_id"
        case email
        case alias
        case accountName = "account_name"
        case plan
        case authMode = "auth_mode"
        case lastUsageAt = "last_usage_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountKey = try container.decode(String.self, forKey: .accountKey)
        chatgptAccountID = try container.decode(String.self, forKey: .chatgptAccountID)
        chatgptUserID = try container.decode(String.self, forKey: .chatgptUserID)
        email = try container.decode(String.self, forKey: .email)
        alias = try container.decodeIfPresent(String.self, forKey: .alias) ?? ""
        accountName = try container.decodeIfPresent(String.self, forKey: .accountName)
        plan = try container.decodeIfPresent(String.self, forKey: .plan)
        authMode = try container.decodeIfPresent(String.self, forKey: .authMode)
        lastUsageAt = try container.decodeIfPresent(String.self, forKey: .lastUsageAt)
    }

    var isAPIKeyAccount: Bool {
        authMode?.lowercased() == "apikey"
    }

    var displayPlan: String {
        if isAPIKeyAccount {
            return "API_KEY"
        }
        return plan?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_") ?? "-"
    }
}

enum AuthRefreshValidationError: Error, Equatable {
    case invalidRefreshResponse
    case accountMismatch
}

enum AuthRefreshResponseValidator {
    static func validate(
        _ response: OAuthRefreshResponse,
        record: AuthAccountRecord,
        usedRefreshToken: String
    ) throws {
        guard let rotatedRefreshToken = response.refreshToken.trimmedNonEmpty,
              rotatedRefreshToken != usedRefreshToken else {
            throw AuthRefreshValidationError.invalidRefreshResponse
        }

        if let idToken = response.idToken,
           let tokenIdentity = TokenIdentity(idToken: idToken),
           tokenIdentity.accountID != record.chatgptAccountID || tokenIdentity.userID != record.chatgptUserID {
            throw AuthRefreshValidationError.accountMismatch
        }
    }
}

struct StoredAuthFile {
    private var root: [String: Any]

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthAccountStoreError.unreadableAuth
        }
        root = object
    }

    var isAPIKeyAuth: Bool {
        (root["OPENAI_API_KEY"] as? String).trimmedNonEmpty != nil
    }

    var refreshToken: String? {
        (tokens["refresh_token"] as? String).trimmedNonEmpty
    }

    var accessTokenExpirationDate: Date? {
        guard let accessToken = (tokens["access_token"] as? String).trimmedNonEmpty,
              let expiration = JWT.payload(from: accessToken)?["exp"] as? NSNumber else {
            return nil
        }
        return Date(timeIntervalSince1970: expiration.doubleValue)
    }

    var lastRefreshDate: Date? {
        guard let value = (root["last_refresh"] as? String).trimmedNonEmpty else {
            return nil
        }
        return Self.iso8601Formatter.date(from: value) ?? Self.fractionalISO8601Formatter.date(from: value)
    }

    func identityMatches(record: AuthAccountRecord) -> Bool {
        guard let idToken = (tokens["id_token"] as? String).trimmedNonEmpty,
              let identity = TokenIdentity(idToken: idToken) else {
            return false
        }
        return identity.userID == record.chatgptUserID && identity.accountID == record.chatgptAccountID
    }

    func needsProactiveRefresh(
        now: Date,
        accessTokenRefreshWindow: TimeInterval,
        fallbackRefreshInterval: TimeInterval
    ) -> Bool {
        if let accessTokenExpirationDate {
            return accessTokenExpirationDate <= now.addingTimeInterval(accessTokenRefreshWindow)
        }

        guard let lastRefreshDate else {
            return false
        }
        return lastRefreshDate < now.addingTimeInterval(-fallbackRefreshInterval)
    }

    private var tokens: [String: Any] {
        root["tokens"] as? [String: Any] ?? [:]
    }

    mutating func apply(response: OAuthRefreshResponse, lastRefresh: String) {
        var updatedTokens = tokens
        if let idToken = response.idToken.trimmedNonEmpty {
            updatedTokens["id_token"] = idToken
            if let identity = TokenIdentity(idToken: idToken) {
                updatedTokens["account_id"] = identity.accountID
            }
        }
        if let accessToken = response.accessToken.trimmedNonEmpty {
            updatedTokens["access_token"] = accessToken
        }
        if let refreshToken = response.refreshToken.trimmedNonEmpty {
            updatedTokens["refresh_token"] = refreshToken
        }
        root["tokens"] = updatedTokens
        root["last_refresh"] = lastRefresh
    }

    func write(to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let fractionalISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

struct TokenIdentity {
    var userID: String
    var accountID: String

    init?(idToken: String) {
        guard let payload = JWT.payload(from: idToken),
              let authClaims = payload["https://api.openai.com/auth"] as? [String: Any],
              let userID = ((authClaims["chatgpt_user_id"] as? String) ?? (authClaims["user_id"] as? String)).trimmedNonEmpty,
              let accountID = (authClaims["chatgpt_account_id"] as? String).trimmedNonEmpty else {
            return nil
        }
        self.userID = userID
        self.accountID = accountID
    }
}

enum JWT {
    static func payload(from token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2,
              let data = base64URLData(String(parts[1])),
              let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any] else {
            return nil
        }
        return payload
    }

    private static func base64URLData(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Optional where Wrapped == String {
    var trimmedNonEmpty: String? {
        self?.trimmedNonEmpty
    }
}
