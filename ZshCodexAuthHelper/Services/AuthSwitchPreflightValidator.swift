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
    case accountBusy(email: String)
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
        case .accountBusy(let email):
            return "Saved login for \(email) is already being checked. Try again after the current refresh finishes."
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
    private static let defaultRecentRefreshSkipInterval: TimeInterval = 30 * 60

    private let store: AuthAccountStore
    private let fileManager: FileManager
    private let lock: AuthAccountFileLock
    private let refresher: OAuthTokenRefreshing
    private let recentRefreshSkipInterval: TimeInterval
    private let now: @Sendable () -> Date

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        lock: AuthAccountFileLock? = nil,
        refresher: OAuthTokenRefreshing = URLSessionOAuthTokenRefresher(),
        recentRefreshSkipInterval: TimeInterval = Self.defaultRecentRefreshSkipInterval,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = AuthAccountStore(homeDirectory: homeDirectory, fileManager: fileManager)
        self.fileManager = fileManager
        self.lock = lock ?? AuthAccountFileLock(homeDirectory: homeDirectory, fileManager: fileManager)
        self.refresher = refresher
        self.recentRefreshSkipInterval = recentRefreshSkipInterval
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
        let storedAuthURL = store.existingAccountAuthURL(accountKey: record.accountKey)

        guard fileManager.fileExists(atPath: storedAuthURL.path) else {
            throw AuthSwitchPreflightError.missingStoredAuth(email: record.email)
        }

        guard let heldLock = try lock.tryLock(accountKey: record.accountKey) else {
            throw AuthSwitchPreflightError.accountBusy(email: record.email)
        }
        defer {
            heldLock.release()
        }

        let selectedAuth = try freshestAuthFile(record: record, storedAuthURL: storedAuthURL)
        var authFile = selectedAuth.authFile
        guard authFile.isAPIKeyAuth == false else {
            return account
        }

        guard let refreshToken = authFile.refreshToken else {
            throw AuthSwitchPreflightError.missingRefreshToken(email: record.email)
        }

        if isRecentRefresh(selectedAuth.freshnessDate) {
            return account
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

        if registry.activeAccountKey == record.accountKey || selectedAuth.source == .active {
            let activeURL = store.activeAuthURL
            if fileManager.fileExists(atPath: activeURL.deletingLastPathComponent().path) {
                try authFile.write(to: activeURL)
            }
        }

        return account
    }

    private func freshestAuthFile(
        record: AuthAccountRecord,
        storedAuthURL: URL
    ) throws -> AuthFileSelection {
        let storedAuthFile = try StoredAuthFile(url: storedAuthURL)
        let storedSelection = AuthFileSelection(
            source: .stored,
            authFile: storedAuthFile,
            freshnessDate: freshnessDate(for: storedAuthFile, url: storedAuthURL)
        )
        guard storedAuthFile.isAPIKeyAuth == false else {
            return storedSelection
        }

        let activeURL = store.activeAuthURL
        guard fileManager.fileExists(atPath: activeURL.path),
              let activeAuthFile = try? StoredAuthFile(url: activeURL),
              activeAuthFile.isAPIKeyAuth == false,
              activeAuthFile.identityMatches(record: record),
              activeAuthFile.refreshToken != nil else {
            return storedSelection
        }

        let activeSelection = AuthFileSelection(
            source: .active,
            authFile: activeAuthFile,
            freshnessDate: freshnessDate(for: activeAuthFile, url: activeURL)
        )
        guard activeSelection.isNewer(than: storedSelection) else {
            return storedSelection
        }

        try activeAuthFile.write(to: storedAuthURL)
        return activeSelection
    }

    private func freshnessDate(for authFile: StoredAuthFile, url: URL) -> Date? {
        authFile.lastRefreshDate ?? fileModificationDate(url)
    }

    private func fileModificationDate(_ url: URL) -> Date? {
        (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    private func isRecentRefresh(_ date: Date?) -> Bool {
        guard let date else {
            return false
        }
        return now().timeIntervalSince(date) < recentRefreshSkipInterval
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
        record: AuthAccountRecord,
        usedRefreshToken: String
    ) throws {
        do {
            try AuthRefreshResponseValidator.validate(response, record: record, usedRefreshToken: usedRefreshToken)
        } catch AuthRefreshValidationError.invalidRefreshResponse {
            throw AuthSwitchPreflightError.invalidRefreshResponse(email: record.email)
        } catch AuthRefreshValidationError.accountMismatch {
            throw AuthSwitchPreflightError.accountMismatch(email: record.email)
        }
    }

    private func repairFromActiveAuth(
        record: AuthAccountRecord,
        staleRefreshToken: String,
        storedAuthURL: URL
    ) async throws -> Bool {
        let activeURL = store.activeAuthURL
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

    private func readRegistry() throws -> AuthAccountRegistry {
        do {
            return try store.readRegistry()
        } catch AuthAccountStoreError.missingRegistry {
            throw AuthSwitchPreflightError.missingRegistry
        } catch {
            throw AuthSwitchPreflightError.transient(email: nil, message: "Registry could not be read.")
        }
    }

    private func resolveAccount(query: String, registry: AuthAccountRegistry) throws -> AuthAccountRecord {
        if let displayNumber = Int(query), displayNumber > 0 {
            let ordered = registry.displayOrderedAccounts()
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

private enum AuthFileSource {
    case stored
    case active
}

private struct AuthFileSelection {
    var source: AuthFileSource
    var authFile: StoredAuthFile
    var freshnessDate: Date?

    func isNewer(than other: AuthFileSelection) -> Bool {
        guard let freshnessDate else {
            return false
        }
        guard let otherFreshnessDate = other.freshnessDate else {
            return true
        }
        return freshnessDate > otherFreshnessDate
    }
}
