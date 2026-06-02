import Foundation

enum AuthAccountRefreshPolicy: Equatable, Sendable {
    case always
    case whenCodexWouldRefresh
}

enum AuthAccountRefreshOutcome: Equatable, Sendable {
    case readyWithoutRefresh
    case refreshed
    case skippedAPIKey
}

enum AuthAccountRefreshError: Error, Equatable, Sendable {
    case missingStoredAuth
    case missingRefreshToken
    case busy
    case reloginRequired(OAuthRefreshFailureReason)
    case accountMismatch
    case invalidRefreshResponse
    case transient(String)
}

struct AuthAccountRefreshCoordinator {
    private static let accessTokenRefreshWindow: TimeInterval = 5 * 60
    private static let fallbackRefreshInterval: TimeInterval = 8 * 24 * 60 * 60

    private let store: AuthAccountStore
    private let fileManager: FileManager
    private let lock: AuthAccountFileLock
    private let refresher: OAuthTokenRefreshing
    private let now: @Sendable () -> Date

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        lock: AuthAccountFileLock? = nil,
        refresher: OAuthTokenRefreshing = URLSessionOAuthTokenRefresher(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = AuthAccountStore(homeDirectory: homeDirectory, fileManager: fileManager)
        self.fileManager = fileManager
        self.lock = lock ?? AuthAccountFileLock(homeDirectory: homeDirectory, fileManager: fileManager)
        self.refresher = refresher
        self.now = now
    }

    func prepare(
        record: AuthAccountRecord,
        registry: AuthAccountRegistry,
        policy: AuthAccountRefreshPolicy
    ) async throws -> AuthAccountRefreshOutcome {
        let storedAuthURL = store.existingAccountAuthURL(accountKey: record.accountKey)
        guard fileManager.fileExists(atPath: storedAuthURL.path) else {
            throw AuthAccountRefreshError.missingStoredAuth
        }

        let heldLock: AuthAccountHeldLock
        do {
            guard let acquiredLock = try lock.tryLock(accountKey: record.accountKey) else {
                throw AuthAccountRefreshError.busy
            }
            heldLock = acquiredLock
        } catch let error as AuthAccountRefreshError {
            throw error
        } catch {
            throw AuthAccountRefreshError.transient(error.localizedDescription)
        }
        defer {
            heldLock.release()
        }

        do {
            return try await prepareWhileLocked(
                record: record,
                registry: registry,
                policy: policy,
                storedAuthURL: storedAuthURL
            )
        } catch let error as AuthAccountRefreshError {
            throw error
        } catch {
            throw AuthAccountRefreshError.transient(error.localizedDescription)
        }
    }

    private func prepareWhileLocked(
        record: AuthAccountRecord,
        registry: AuthAccountRegistry,
        policy: AuthAccountRefreshPolicy,
        storedAuthURL: URL
    ) async throws -> AuthAccountRefreshOutcome {
        let selection = try freshestMatchingAuthFile(record: record, storedAuthURL: storedAuthURL)
        let authFile = selection.authFile

        guard authFile.isAPIKeyAuth == false else {
            return .skippedAPIKey
        }
        guard let refreshToken = authFile.refreshToken else {
            throw AuthAccountRefreshError.missingRefreshToken
        }

        if policy == .whenCodexWouldRefresh,
           authFile.needsProactiveRefresh(
               now: now(),
               accessTokenRefreshWindow: Self.accessTokenRefreshWindow,
               fallbackRefreshInterval: Self.fallbackRefreshInterval
           ) == false {
            return .readyWithoutRefresh
        }

        do {
            try await refreshAndPersist(
                authFile: authFile,
                refreshToken: refreshToken,
                record: record,
                storedAuthURL: storedAuthURL,
                updateActiveAuth: registry.activeAccountKey == record.accountKey || selection.source == .active
            )
            return .refreshed
        } catch AuthAccountRefreshError.reloginRequired(let reason) where reason != .other {
            if try await repairFromMatchingActiveAuth(
                record: record,
                staleRefreshToken: refreshToken,
                storedAuthURL: storedAuthURL
            ) {
                return .refreshed
            }
            throw AuthAccountRefreshError.reloginRequired(reason)
        }
    }

    private func refreshAndPersist(
        authFile: StoredAuthFile,
        refreshToken: String,
        record: AuthAccountRecord,
        storedAuthURL: URL,
        updateActiveAuth: Bool
    ) async throws {
        let response = try await refresh(refreshToken: refreshToken)
        do {
            try AuthRefreshResponseValidator.validate(
                response,
                record: record,
                usedRefreshToken: refreshToken
            )
        } catch AuthRefreshValidationError.invalidRefreshResponse {
            throw AuthAccountRefreshError.invalidRefreshResponse
        } catch AuthRefreshValidationError.accountMismatch {
            throw AuthAccountRefreshError.accountMismatch
        }

        var updatedAuthFile = authFile
        updatedAuthFile.apply(response: response, lastRefresh: Self.iso8601String(from: now()))
        try updatedAuthFile.write(to: storedAuthURL)

        if updateActiveAuth {
            let activeURL = store.activeAuthURL
            if fileManager.fileExists(atPath: activeURL.deletingLastPathComponent().path) {
                try updatedAuthFile.write(to: activeURL)
            }
        }
    }

    private func refresh(refreshToken: String) async throws -> OAuthRefreshResponse {
        do {
            return try await refresher.refresh(refreshToken: refreshToken)
        } catch let failure as OAuthRefreshFailure {
            switch failure {
            case .reloginRequired(let reason):
                throw AuthAccountRefreshError.reloginRequired(reason)
            case .transient(let message):
                throw AuthAccountRefreshError.transient(message)
            }
        } catch {
            throw AuthAccountRefreshError.transient(error.localizedDescription)
        }
    }

    private func repairFromMatchingActiveAuth(
        record: AuthAccountRecord,
        staleRefreshToken: String,
        storedAuthURL: URL
    ) async throws -> Bool {
        let activeURL = store.activeAuthURL
        guard fileManager.fileExists(atPath: activeURL.path),
              let activeAuthFile = try? StoredAuthFile(url: activeURL),
              activeAuthFile.isAPIKeyAuth == false,
              activeAuthFile.identityMatches(record: record),
              let activeRefreshToken = activeAuthFile.refreshToken,
              activeRefreshToken != staleRefreshToken else {
            return false
        }

        do {
            try await refreshAndPersist(
                authFile: activeAuthFile,
                refreshToken: activeRefreshToken,
                record: record,
                storedAuthURL: storedAuthURL,
                updateActiveAuth: true
            )
            return true
        } catch AuthAccountRefreshError.reloginRequired {
            return false
        }
    }

    private func freshestMatchingAuthFile(
        record: AuthAccountRecord,
        storedAuthURL: URL
    ) throws -> AuthFileSelection {
        let storedAuthFile = try StoredAuthFile(url: storedAuthURL)
        guard storedAuthFile.isAPIKeyAuth == false else {
            return AuthFileSelection(source: .stored, authFile: storedAuthFile)
        }

        let activeURL = store.activeAuthURL
        guard fileManager.fileExists(atPath: activeURL.path),
              let activeAuthFile = try? StoredAuthFile(url: activeURL),
              activeAuthFile.isAPIKeyAuth == false,
              activeAuthFile.identityMatches(record: record),
              activeAuthFile.refreshToken != nil,
              isActiveAuthNewer(
                  activeAuthFile,
                  activeURL: activeURL,
                  than: storedAuthFile,
                  storedAuthURL: storedAuthURL
              ) else {
            return AuthFileSelection(source: .stored, authFile: storedAuthFile)
        }

        try activeAuthFile.write(to: storedAuthURL)
        return AuthFileSelection(source: .active, authFile: activeAuthFile)
    }

    private func isActiveAuthNewer(
        _ activeAuthFile: StoredAuthFile,
        activeURL: URL,
        than storedAuthFile: StoredAuthFile,
        storedAuthURL: URL
    ) -> Bool {
        guard let activeDate = freshnessDate(for: activeAuthFile, url: activeURL) else {
            return false
        }
        guard let storedDate = freshnessDate(for: storedAuthFile, url: storedAuthURL) else {
            return true
        }
        return activeDate > storedDate
    }

    private func freshnessDate(for authFile: StoredAuthFile, url: URL) -> Date? {
        authFile.lastRefreshDate ?? fileModificationDate(url)
    }

    private func fileModificationDate(_ url: URL) -> Date? {
        (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

private extension AuthAccountRefreshCoordinator {
    enum AuthFileSource {
        case stored
        case active
    }

    struct AuthFileSelection {
        var source: AuthFileSource
        var authFile: StoredAuthFile
    }
}
