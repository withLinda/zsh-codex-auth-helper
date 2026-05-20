import Foundation

enum AuthHealthCheckStatus: Equatable, Sendable {
    case refreshed
    case skippedRecent
    case skippedAPIKey
    case missingStoredAuth
    case missingRefreshToken
    case busy
    case reloginRequired(OAuthRefreshFailureReason)
    case accountMismatch
    case invalidRefreshResponse
    case transient(String)

    var isFailure: Bool {
        switch self {
        case .refreshed, .skippedRecent, .skippedAPIKey:
            return false
        case .missingStoredAuth, .missingRefreshToken, .busy, .reloginRequired, .accountMismatch, .invalidRefreshResponse, .transient:
            return true
        }
    }
}

struct AuthHealthCheckAccountResult: Equatable, Sendable {
    var accountKey: String
    var email: String
    var alias: String?
    var status: AuthHealthCheckStatus
}

struct AuthHealthCheckSummary: Equatable, Sendable {
    var results: [AuthHealthCheckAccountResult]

    var total: Int {
        results.count
    }

    var refreshed: Int {
        results.filter { $0.status == .refreshed }.count
    }

    var skipped: Int {
        results.filter { result in
            switch result.status {
            case .skippedRecent, .skippedAPIKey:
                return true
            default:
                return false
            }
        }.count
    }

    var failed: Int {
        results.filter(\.status.isFailure).count
    }

    var transcriptSummaryLine: String {
        "Health Check finished: \(refreshed) refreshed, \(skipped) skipped, \(failed) need attention."
    }
}

enum AuthHealthCheckEvent: Sendable {
    case started(total: Int, staleAfter: TimeInterval)
    case checking(email: String)
    case result(AuthHealthCheckAccountResult)
    case failed(message: String)
    case finished(AuthHealthCheckSummary)

    var transcriptLine: String {
        switch self {
        case .started(let total, let staleAfter):
            let hours = Int(staleAfter / 3600)
            return "Health Check started for \(total) saved account\(total == 1 ? "" : "s"). Stale age: \(hours) hours."
        case .checking(let email):
            return "Checking \(email)..."
        case .result(let result):
            return "\(result.email): \(result.status.transcriptDescription)"
        case .failed(let message):
            return "Health Check could not start: \(message)"
        case .finished(let summary):
            return summary.transcriptSummaryLine
        }
    }
}

struct AuthHealthCheckService {
    static let defaultStaleAfter: TimeInterval = 24 * 60 * 60

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

    func run(
        staleAfter: TimeInterval = Self.defaultStaleAfter,
        onProgress: @escaping @MainActor (AuthHealthCheckEvent) -> Void
    ) async -> AuthHealthCheckSummary {
        let registry: AuthAccountRegistry
        do {
            registry = try store.readRegistry()
        } catch {
            let message = error.localizedDescription
            await emit(.failed(message: message), onProgress: onProgress)
            let summary = AuthHealthCheckSummary(results: [])
            await emit(.finished(summary), onProgress: onProgress)
            return summary
        }

        let accounts = registry.displayOrderedAccounts()
        await emit(.started(total: accounts.count, staleAfter: staleAfter), onProgress: onProgress)

        var results: [AuthHealthCheckAccountResult] = []
        for record in accounts {
            await emit(.checking(email: record.email), onProgress: onProgress)
            let result = await check(record: record, registry: registry, staleAfter: staleAfter)
            results.append(result)
            await emit(.result(result), onProgress: onProgress)
        }

        let summary = AuthHealthCheckSummary(results: results)
        await emit(.finished(summary), onProgress: onProgress)
        return summary
    }

    private func check(
        record: AuthAccountRecord,
        registry: AuthAccountRegistry,
        staleAfter: TimeInterval
    ) async -> AuthHealthCheckAccountResult {
        if record.isAPIKeyAccount {
            return result(record: record, status: .skippedAPIKey)
        }

        let storedAuthURL = store.existingAccountAuthURL(accountKey: record.accountKey)
        guard fileManager.fileExists(atPath: storedAuthURL.path) else {
            return result(record: record, status: .missingStoredAuth)
        }

        let heldLock: AuthAccountHeldLock
        do {
            guard let acquiredLock = try lock.tryLock(accountKey: record.accountKey) else {
                return result(record: record, status: .busy)
            }
            heldLock = acquiredLock
        } catch {
            return result(record: record, status: .transient(error.localizedDescription))
        }
        defer {
            heldLock.release()
        }

        var authFile: StoredAuthFile
        do {
            authFile = try StoredAuthFile(url: storedAuthURL)
        } catch {
            return result(record: record, status: .transient(error.localizedDescription))
        }

        if authFile.isAPIKeyAuth {
            return result(record: record, status: .skippedAPIKey)
        }

        if let lastRefreshDate = authFile.lastRefreshDate,
           now().timeIntervalSince(lastRefreshDate) < staleAfter {
            return result(record: record, status: .skippedRecent)
        }

        guard let refreshToken = authFile.refreshToken else {
            return result(record: record, status: .missingRefreshToken)
        }

        let response: OAuthRefreshResponse
        do {
            response = try await refresher.refresh(refreshToken: refreshToken)
        } catch let failure as OAuthRefreshFailure {
            switch failure {
            case .reloginRequired(let reason):
                return result(record: record, status: .reloginRequired(reason))
            case .transient(let message):
                return result(record: record, status: .transient(message))
            }
        } catch {
            return result(record: record, status: .transient(error.localizedDescription))
        }

        do {
            try AuthRefreshResponseValidator.validate(response, record: record, usedRefreshToken: refreshToken)
        } catch AuthRefreshValidationError.invalidRefreshResponse {
            return result(record: record, status: .invalidRefreshResponse)
        } catch AuthRefreshValidationError.accountMismatch {
            return result(record: record, status: .accountMismatch)
        } catch {
            return result(record: record, status: .transient(error.localizedDescription))
        }

        do {
            authFile.apply(response: response, lastRefresh: Self.iso8601String(from: now()))
            try authFile.write(to: storedAuthURL)

            if registry.activeAccountKey == record.accountKey {
                let activeURL = store.activeAuthURL
                if fileManager.fileExists(atPath: activeURL.deletingLastPathComponent().path) {
                    try authFile.write(to: activeURL)
                }
            }
        } catch {
            return result(record: record, status: .transient(error.localizedDescription))
        }

        return result(record: record, status: .refreshed)
    }

    private func result(record: AuthAccountRecord, status: AuthHealthCheckStatus) -> AuthHealthCheckAccountResult {
        AuthHealthCheckAccountResult(
            accountKey: record.accountKey,
            email: record.email,
            alias: record.alias.trimmedNonEmpty,
            status: status
        )
    }

    private func emit(
        _ event: AuthHealthCheckEvent,
        onProgress: @escaping @MainActor (AuthHealthCheckEvent) -> Void
    ) async {
        await MainActor.run {
            onProgress(event)
        }
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

private extension AuthHealthCheckStatus {
    var transcriptDescription: String {
        switch self {
        case .refreshed:
            return "refreshed"
        case .skippedRecent:
            return "skipped; checked within the last 24 hours"
        case .skippedAPIKey:
            return "skipped; API key auth does not use a refresh token"
        case .missingStoredAuth:
            return "needs login; saved auth file is missing"
        case .missingRefreshToken:
            return "needs login; refresh token is missing"
        case .busy:
            return "skipped; another refresh is already checking it"
        case .reloginRequired(let reason):
            return "needs login; refresh token was \(reason.displayName)"
        case .accountMismatch:
            return "failed; refresh returned a different account"
        case .invalidRefreshResponse:
            return "failed; refresh did not return a new refresh token"
        case .transient(let message):
            return "failed; \(message)"
        }
    }
}
