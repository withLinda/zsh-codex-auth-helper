import Foundation

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
            return "Saved auth file for \(email) was not found. Click Login and finish browser login, then switch again. Use Save / Update Login only if you want to set or change an alias."
        case .missingRefreshToken(let email):
            return "Saved login for \(email) has no refresh token. Click Login and finish browser login, then switch again. Use Save / Update Login only if you want to set or change an alias."
        case .accountBusy(let email):
            return "Saved login for \(email) is already being checked. Try again after the current check finishes."
        case .reloginRequired(let email, let reason):
            return "Saved login for \(email) cannot refresh because its refresh token was \(reason.displayName). Click Login and finish browser login, then switch again. Use Save / Update Login only if you want to set or change an alias."
        case .accountMismatch(let email):
            return "Could not check login for \(email): refresh returned a different account. No account was switched."
        case .invalidRefreshResponse(let email):
            return "Could not check login for \(email): refresh did not return a new refresh token. No account was switched."
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

struct AuthSwitchPreflightResult: Equatable, Sendable {
    var account: AuthSwitchPreflightAccount
    var status: AuthAccountRefreshOutcome

    var transcriptLine: String {
        switch status {
        case .readyWithoutRefresh:
            return "Saved access token does not need refresh yet for \(account.email)."
        case .refreshed:
            return "Login refreshed for \(account.email)."
        case .skippedAPIKey:
            return "Login check passed for \(account.email). API key auth does not need OAuth refresh."
        }
    }
}

struct AuthSwitchPreflightValidator {
    private let store: AuthAccountStore
    private let coordinator: AuthAccountRefreshCoordinator

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        lock: AuthAccountFileLock? = nil,
        refresher: OAuthTokenRefreshing = URLSessionOAuthTokenRefresher(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = AuthAccountStore(homeDirectory: homeDirectory, fileManager: fileManager)
        self.coordinator = AuthAccountRefreshCoordinator(
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            lock: lock,
            refresher: refresher,
            now: now
        )
    }

    func prepareForSwitch(query: String) async throws -> AuthSwitchPreflightResult {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let registry = try readRegistry()
        let record = try resolveAccount(query: trimmedQuery, registry: registry)
        let account = AuthSwitchPreflightAccount(
            accountKey: record.accountKey,
            email: record.email,
            alias: record.alias.trimmedNonEmpty
        )

        do {
            let status = try await coordinator.prepare(
                record: record,
                registry: registry,
                policy: .whenCodexWouldRefresh
            )
            return AuthSwitchPreflightResult(account: account, status: status)
        } catch let error as AuthAccountRefreshError {
            throw map(error, email: record.email)
        } catch {
            throw AuthSwitchPreflightError.transient(email: record.email, message: error.localizedDescription)
        }
    }

    private func map(_ error: AuthAccountRefreshError, email: String) -> AuthSwitchPreflightError {
        switch error {
        case .missingStoredAuth:
            return .missingStoredAuth(email: email)
        case .missingRefreshToken:
            return .missingRefreshToken(email: email)
        case .busy:
            return .accountBusy(email: email)
        case .reloginRequired(let reason):
            return .reloginRequired(email: email, reason: reason)
        case .accountMismatch:
            return .accountMismatch(email: email)
        case .invalidRefreshResponse:
            return .invalidRefreshResponse(email: email)
        case .transient(let message):
            return .transient(email: email, message: message)
        }
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
}
