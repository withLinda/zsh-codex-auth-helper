import Foundation

enum AuthHealthCheckStatus: Equatable, Sendable {
    case refreshed
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
        case .refreshed, .skippedAPIKey:
            return false
        case .missingStoredAuth, .missingRefreshToken, .busy, .reloginRequired, .accountMismatch, .invalidRefreshResponse, .transient:
            return true
        }
    }

    var isSkipped: Bool {
        switch self {
        case .skippedAPIKey:
            return true
        default:
            return false
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
            case .skippedAPIKey:
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
        """
        Health Check finished: \(refreshed) refreshed, \(skipped) skipped, \(failed) need attention.

        Need attention:
        \(Self.listLines(for: emails { $0.status.isFailure }))

        Refreshed:
        \(Self.listLines(for: emails { $0.status == .refreshed }))

        Skipped:
        \(Self.listLines(for: emails { $0.status.isSkipped }))
        """
    }

    private func emails(matching predicate: (AuthHealthCheckAccountResult) -> Bool) -> [String] {
        results
            .filter(predicate)
            .map(\.email)
            .sorted { lhs, rhs in
                lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
    }

    private static func listLines(for emails: [String]) -> String {
        guard emails.isEmpty == false else {
            return "- None"
        }

        return emails.map { "- \($0)" }.joined(separator: "\n")
    }
}

enum AuthHealthCheckEvent: Sendable {
    case started(total: Int)
    case checking(email: String)
    case result(AuthHealthCheckAccountResult)
    case failed(message: String)
    case finished(AuthHealthCheckSummary)

    var transcriptLine: String {
        switch self {
        case .started(let total):
            return "Health Check started for \(total) saved account\(total == 1 ? "" : "s")."
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

    func run(
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
        await emit(.started(total: accounts.count), onProgress: onProgress)

        var results: [AuthHealthCheckAccountResult] = []
        for record in accounts {
            await emit(.checking(email: record.email), onProgress: onProgress)
            let result = await check(record: record, registry: registry)
            results.append(result)
            await emit(.result(result), onProgress: onProgress)
        }

        let summary = AuthHealthCheckSummary(results: results)
        await emit(.finished(summary), onProgress: onProgress)
        return summary
    }

    private func check(
        record: AuthAccountRecord,
        registry: AuthAccountRegistry
    ) async -> AuthHealthCheckAccountResult {
        if record.isAPIKeyAccount {
            return result(record: record, status: .skippedAPIKey)
        }

        do {
            let outcome = try await coordinator.prepare(record: record, registry: registry, policy: .always)
            switch outcome {
            case .refreshed:
                return result(record: record, status: .refreshed)
            case .skippedAPIKey:
                return result(record: record, status: .skippedAPIKey)
            case .readyWithoutRefresh:
                return result(record: record, status: .transient("Login check did not refresh the saved account."))
            }
        } catch let error as AuthAccountRefreshError {
            switch error {
            case .missingStoredAuth:
                return result(record: record, status: .missingStoredAuth)
            case .missingRefreshToken:
                return result(record: record, status: .missingRefreshToken)
            case .busy:
                return result(record: record, status: .busy)
            case .reloginRequired(let reason):
                return result(record: record, status: .reloginRequired(reason))
            case .accountMismatch:
                return result(record: record, status: .accountMismatch)
            case .invalidRefreshResponse:
                return result(record: record, status: .invalidRefreshResponse)
            case .transient(let message):
                return result(record: record, status: .transient(message))
            }
        } catch {
            return result(record: record, status: .transient(error.localizedDescription))
        }
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
}

private extension AuthHealthCheckStatus {
    var transcriptDescription: String {
        switch self {
        case .refreshed:
            return "refreshed"
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
