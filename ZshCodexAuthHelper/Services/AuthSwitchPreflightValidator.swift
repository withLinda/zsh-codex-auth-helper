import Foundation

protocol OAuthTokenRefreshing: Sendable {
    func refresh(refreshToken: String) async throws -> OAuthRefreshResponse
}

struct OAuthRefreshResponse: Decodable, Equatable, Sendable {
    var idToken: String?
    var accessToken: String?
    var refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

enum OAuthRefreshFailureReason: Equatable, Sendable {
    case expired
    case reused
    case revoked
    case other

    var displayName: String {
        switch self {
        case .expired:
            return "expired"
        case .reused:
            return "already used"
        case .revoked:
            return "revoked"
        case .other:
            return "not accepted"
        }
    }
}

enum OAuthRefreshFailure: LocalizedError, Equatable, Sendable {
    case reloginRequired(OAuthRefreshFailureReason)
    case transient(String)

    var errorDescription: String? {
        switch self {
        case .reloginRequired(let reason):
            return "Refresh token \(reason.displayName)."
        case .transient(let message):
            return message
        }
    }
}

enum AuthSwitchPreflightError: LocalizedError, Equatable {
    case accountNotFound(query: String)
    case ambiguousAccount(query: String)
    case missingRegistry
    case missingStoredAuth(email: String)
    case missingRefreshToken(email: String)
    case reloginRequired(email: String, reason: OAuthRefreshFailureReason)
    case accountMismatch(email: String)
    case invalidRefreshResponse(email: String)
    case transient(email: String?, message: String)

    var errorDescription: String? {
        switch self {
        case .accountNotFound(let query):
            return "No saved account matches \"\(query)\". Run List Accounts and use a full email, alias, or row number."
        case .ambiguousAccount(let query):
            return "More than one saved account matches \"\(query)\". Use a full email, alias, or row number."
        case .missingRegistry:
            return "No codex-auth registry was found. Run List Accounts or Save / Update Login first."
        case .missingStoredAuth(let email):
            return "Saved auth file for \(email) was not found. Log in again, then Save / Update Login. Alias is optional for existing accounts."
        case .missingRefreshToken(let email):
            return "Saved login for \(email) has no refresh token. Log in again, then Save / Update Login. Alias is optional for existing accounts."
        case .reloginRequired(let email, let reason):
            return "Saved login for \(email) cannot refresh because its refresh token was \(reason.displayName). Log in again, then Save / Update Login before switching. Alias is optional for existing accounts."
        case .accountMismatch(let email):
            return "The refresh check for \(email) returned a different account. No account was switched."
        case .invalidRefreshResponse(let email):
            return "The refresh check for \(email) did not return a new refresh token. No account was switched."
        case .transient(let email, let message):
            if let email {
                return "Could not check login for \(email): \(message). No account was switched."
            }
            return "Could not check login: \(message). No account was switched."
        }
    }
}

struct AuthSwitchPreflightAccount: Equatable, Sendable {
    var accountKey: String
    var email: String
    var alias: String?
}

struct AuthSwitchPreflightValidator {
    private let homeDirectory: URL
    private let fileManager: FileManager
    private let refresher: OAuthTokenRefreshing
    private let now: @Sendable () -> Date

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        refresher: OAuthTokenRefreshing = URLSessionOAuthTokenRefresher(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.refresher = refresher
        self.now = now
    }

    func validateAndRefresh(query: String) async throws -> AuthSwitchPreflightAccount {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let registry = try readRegistry()
        let record = try resolveAccount(query: trimmedQuery, registry: registry)
        let account = AuthSwitchPreflightAccount(
            accountKey: record.accountKey,
            email: record.email,
            alias: record.alias.trimmedNonEmpty
        )
        let storedAuthURL = accountAuthURL(accountKey: record.accountKey)

        guard fileManager.fileExists(atPath: storedAuthURL.path) else {
            throw AuthSwitchPreflightError.missingStoredAuth(email: record.email)
        }

        var authFile = try StoredAuthFile(url: storedAuthURL)
        guard authFile.isAPIKeyAuth == false else {
            return account
        }

        guard let refreshToken = authFile.refreshToken else {
            throw AuthSwitchPreflightError.missingRefreshToken(email: record.email)
        }

        let response: OAuthRefreshResponse
        do {
            response = try await refreshResponse(refreshToken: refreshToken, email: record.email)
        } catch let error as AuthSwitchPreflightError {
            if case .reloginRequired(_, let reason) = error,
               reason.canAttemptActiveAuthRepair,
               try await repairFromActiveAuth(
                   record: record,
                   staleRefreshToken: refreshToken,
                   storedAuthURL: storedAuthURL
               ) {
                return account
            }
            throw error
        }

        try validateRefreshResponse(response, record: record, usedRefreshToken: refreshToken)
        authFile.apply(response: response, lastRefresh: Self.iso8601String(from: now()))
        try authFile.write(to: storedAuthURL)

        if registry.activeAccountKey == record.accountKey {
            let activeURL = activeAuthURL
            if fileManager.fileExists(atPath: activeURL.deletingLastPathComponent().path) {
                try authFile.write(to: activeURL)
            }
        }

        return account
    }

    private func refreshResponse(refreshToken: String, email: String) async throws -> OAuthRefreshResponse {
        do {
            return try await refresher.refresh(refreshToken: refreshToken)
        } catch let failure as OAuthRefreshFailure {
            switch failure {
            case .reloginRequired(let reason):
                throw AuthSwitchPreflightError.reloginRequired(email: email, reason: reason)
            case .transient(let message):
                throw AuthSwitchPreflightError.transient(email: email, message: message)
            }
        } catch {
            throw AuthSwitchPreflightError.transient(email: email, message: error.localizedDescription)
        }
    }

    private func validateRefreshResponse(
        _ response: OAuthRefreshResponse,
        record: SwitchAccountRecord,
        usedRefreshToken: String
    ) throws {
        guard let rotatedRefreshToken = response.refreshToken.trimmedNonEmpty,
              rotatedRefreshToken != usedRefreshToken else {
            throw AuthSwitchPreflightError.invalidRefreshResponse(email: record.email)
        }

        if let idToken = response.idToken,
           let tokenIdentity = TokenIdentity(idToken: idToken),
           tokenIdentity.accountID != record.chatgptAccountID || tokenIdentity.userID != record.chatgptUserID {
            throw AuthSwitchPreflightError.accountMismatch(email: record.email)
        }
    }

    private func repairFromActiveAuth(
        record: SwitchAccountRecord,
        staleRefreshToken: String,
        storedAuthURL: URL
    ) async throws -> Bool {
        let activeURL = activeAuthURL
        guard fileManager.fileExists(atPath: activeURL.path),
              var activeAuthFile = try? StoredAuthFile(url: activeURL),
              activeAuthFile.isAPIKeyAuth == false,
              activeAuthFile.identityMatches(record: record),
              let activeRefreshToken = activeAuthFile.refreshToken,
              activeRefreshToken != staleRefreshToken else {
            return false
        }

        let response = try await refreshResponse(refreshToken: activeRefreshToken, email: record.email)
        try validateRefreshResponse(response, record: record, usedRefreshToken: activeRefreshToken)
        activeAuthFile.apply(response: response, lastRefresh: Self.iso8601String(from: now()))
        try activeAuthFile.write(to: activeURL)
        try activeAuthFile.write(to: storedAuthURL)
        return true
    }

    private var registryURL: URL {
        homeDirectory.appendingPathComponent(".codex/accounts/registry.json")
    }

    private var activeAuthURL: URL {
        homeDirectory.appendingPathComponent(".codex/auth.json")
    }

    private func accountAuthURL(accountKey: String) -> URL {
        homeDirectory
            .appendingPathComponent(".codex/accounts")
            .appendingPathComponent("\(Self.encodedAccountKey(accountKey)).auth.json")
    }

    private func readRegistry() throws -> SwitchRegistry {
        guard fileManager.fileExists(atPath: registryURL.path) else {
            throw AuthSwitchPreflightError.missingRegistry
        }

        do {
            return try JSONDecoder().decode(SwitchRegistry.self, from: Data(contentsOf: registryURL))
        } catch {
            throw AuthSwitchPreflightError.transient(email: nil, message: "Registry could not be read.")
        }
    }

    private func resolveAccount(query: String, registry: SwitchRegistry) throws -> SwitchAccountRecord {
        if let displayNumber = Int(query), displayNumber > 0 {
            let ordered = displayOrderedAccounts(registry: registry)
            if displayNumber <= ordered.count {
                return ordered[displayNumber - 1]
            }
        }

        let matches = registry.accounts.filter { record in
            record.email.localizedCaseInsensitiveContains(query) ||
            record.alias.localizedCaseInsensitiveContains(query) ||
            (record.accountName?.localizedCaseInsensitiveContains(query) ?? false)
        }

        if matches.isEmpty {
            throw AuthSwitchPreflightError.accountNotFound(query: query)
        }
        if matches.count > 1 {
            throw AuthSwitchPreflightError.ambiguousAccount(query: query)
        }
        return matches[0]
    }

    private func displayOrderedAccounts(registry: SwitchRegistry) -> [SwitchAccountRecord] {
        registry.accounts.sorted { lhs, rhs in
            if lhs.email != rhs.email {
                return lhs.email < rhs.email
            }

            let lhsActive = registry.activeAccountKey == lhs.accountKey
            let rhsActive = registry.activeAccountKey == rhs.accountKey
            if lhsActive != rhsActive {
                return lhsActive
            }

            let lhsRank = planSortRank(lhs.displayPlan)
            let rhsRank = planSortRank(rhs.displayPlan)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }

            if lhs.displayPlan != rhs.displayPlan {
                return lhs.displayPlan < rhs.displayPlan
            }

            return lhs.accountKey < rhs.accountKey
        }
    }

    private func planSortRank(_ plan: String) -> Int {
        switch plan {
        case "team", "business", "enterprise", "edu":
            return 0
        case "free", "plus", "prolite", "pro":
            return 1
        default:
            return 2
        }
    }

    private static func encodedAccountKey(_ accountKey: String) -> String {
        Data(accountKey.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

struct URLSessionOAuthTokenRefresher: OAuthTokenRefreshing {
    private static let endpoint = URL(string: "https://auth.openai.com/oauth/token")!
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    func refresh(refreshToken: String) async throws -> OAuthRefreshResponse {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": Self.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OAuthRefreshFailure.transient(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthRefreshFailure.transient("Refresh server returned a non-HTTP response")
        }

        if (200...299).contains(httpResponse.statusCode) {
            return try JSONDecoder().decode(OAuthRefreshResponse.self, from: data)
        }

        if httpResponse.statusCode == 401 {
            throw OAuthRefreshFailure.reloginRequired(Self.failureReason(from: data))
        }

        throw OAuthRefreshFailure.transient("Refresh server returned HTTP \(httpResponse.statusCode)")
    }

    private static func failureReason(from data: Data) -> OAuthRefreshFailureReason {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .other
        }

        let code: String?
        if let error = object["error"] as? [String: Any] {
            code = error["code"] as? String
        } else {
            code = object["error"] as? String ?? object["code"] as? String
        }

        switch code?.lowercased() {
        case "refresh_token_expired":
            return .expired
        case "refresh_token_reused":
            return .reused
        case "refresh_token_invalidated":
            return .revoked
        default:
            return .other
        }
    }
}

private struct SwitchRegistry: Decodable {
    var activeAccountKey: String?
    var accounts: [SwitchAccountRecord]

    enum CodingKeys: String, CodingKey {
        case activeAccountKey = "active_account_key"
        case accounts
    }
}

private struct SwitchAccountRecord: Decodable {
    var accountKey: String
    var chatgptAccountID: String
    var chatgptUserID: String
    var email: String
    var alias: String
    var accountName: String?
    var plan: String?
    var authMode: String?

    enum CodingKeys: String, CodingKey {
        case accountKey = "account_key"
        case chatgptAccountID = "chatgpt_account_id"
        case chatgptUserID = "chatgpt_user_id"
        case email
        case alias
        case accountName = "account_name"
        case plan
        case authMode = "auth_mode"
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
    }

    var displayPlan: String {
        if authMode?.lowercased() == "apikey" {
            return "API_KEY"
        }
        return plan?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_") ?? "-"
    }
}

private struct StoredAuthFile {
    private var root: [String: Any]

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthSwitchPreflightError.transient(email: nil, message: "Auth file is not a JSON object.")
        }
        root = object
    }

    var isAPIKeyAuth: Bool {
        (root["OPENAI_API_KEY"] as? String).trimmedNonEmpty != nil
    }

    var refreshToken: String? {
        tokens["refresh_token"] as? String
    }

    func identityMatches(record: SwitchAccountRecord) -> Bool {
        guard let idToken = (tokens["id_token"] as? String).trimmedNonEmpty,
              let identity = TokenIdentity(idToken: idToken) else {
            return false
        }
        return identity.userID == record.chatgptUserID && identity.accountID == record.chatgptAccountID
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
}

private struct TokenIdentity {
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

private enum JWT {
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

private extension OAuthRefreshFailureReason {
    var canAttemptActiveAuthRepair: Bool {
        switch self {
        case .expired, .reused, .revoked:
            return true
        case .other:
            return false
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Optional where Wrapped == String {
    var trimmedNonEmpty: String? {
        self?.trimmedNonEmpty
    }
}
