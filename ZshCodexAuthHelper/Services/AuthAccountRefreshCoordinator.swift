import CryptoKit
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
    case storedAuthIdentityMismatch
    case accountMismatch
    case invalidRefreshResponse
    case transient(String)
}

struct AuthAccountRefreshDebugEvent: Equatable, Sendable {
    var message: String

    var transcriptLine: String {
        "Switch check: \(message)"
    }
}

typealias AuthAccountRefreshDebugSink = @Sendable (AuthAccountRefreshDebugEvent) async -> Void
typealias AuthFileWriter = @Sendable (StoredAuthFile, URL) throws -> Void

struct AuthAccountRefreshCoordinator {
    private static let accessTokenRefreshWindow: TimeInterval = 5 * 60
    private static let fallbackRefreshInterval: TimeInterval = 8 * 24 * 60 * 60

    private let store: AuthAccountStore
    private let fileManager: FileManager
    private let lock: AuthAccountFileLock
    private let refresher: OAuthTokenRefreshing
    private let writeAuthFile: AuthFileWriter
    private let now: @Sendable () -> Date

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        lock: AuthAccountFileLock? = nil,
        refresher: OAuthTokenRefreshing = URLSessionOAuthTokenRefresher(),
        writeAuthFile: @escaping AuthFileWriter = { authFile, url in
            try authFile.write(to: url)
        },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = AuthAccountStore(homeDirectory: homeDirectory, fileManager: fileManager)
        self.fileManager = fileManager
        self.lock = lock ?? AuthAccountFileLock(homeDirectory: homeDirectory, fileManager: fileManager)
        self.refresher = refresher
        self.writeAuthFile = writeAuthFile
        self.now = now
    }

    func prepare(
        record: AuthAccountRecord,
        registry: AuthAccountRegistry,
        policy: AuthAccountRefreshPolicy,
        onDebug: AuthAccountRefreshDebugSink? = nil
    ) async throws -> AuthAccountRefreshOutcome {
        let storedAuthURL = store.existingAccountAuthURL(accountKey: record.accountKey)
        await emit("selected \(record.email).", onDebug: onDebug)
        await emit("saved file \(displayPath(storedAuthURL)).", onDebug: onDebug)
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
                storedAuthURL: storedAuthURL,
                onDebug: onDebug
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
        storedAuthURL: URL,
        onDebug: AuthAccountRefreshDebugSink?
    ) async throws -> AuthAccountRefreshOutcome {
        let selection = try await freshestMatchingAuthFile(
            record: record,
            storedAuthURL: storedAuthURL,
            onDebug: onDebug
        )
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
            await emit("saved access token is fresh enough; no OpenAI refresh needed before switch.", onDebug: onDebug)
            return .readyWithoutRefresh
        }

        do {
            try await refreshAndPersist(
                authFile: authFile,
                refreshToken: refreshToken,
                record: record,
                storedAuthURL: storedAuthURL,
                updateActiveAuth: registry.activeAccountKey == record.accountKey || selection.source == .active,
                onDebug: onDebug
            )
            return .refreshed
        } catch AuthAccountRefreshError.reloginRequired(let reason) where reason != .other {
            await emit("OpenAI says this refresh token was \(reason.displayName).", onDebug: onDebug)
            if let repairOutcome = try await repairFromMatchingActiveAuth(
                record: record,
                staleRefreshToken: refreshToken,
                storedAuthURL: storedAuthURL,
                policy: policy,
                onDebug: onDebug
            ) {
                return repairOutcome
            }
            throw AuthAccountRefreshError.reloginRequired(reason)
        }
    }

    private func refreshAndPersist(
        authFile: StoredAuthFile,
        refreshToken: String,
        record: AuthAccountRecord,
        storedAuthURL: URL,
        updateActiveAuth: Bool,
        onDebug: AuthAccountRefreshDebugSink?
    ) async throws {
        await emit("asking OpenAI to validate refresh token \(Self.tokenFingerprint(refreshToken)).", onDebug: onDebug)
        let response = try await refresh(refreshToken: refreshToken)
        if let rotatedRefreshToken = response.refreshToken.trimmedNonEmpty {
            await emit("OpenAI accepted it and returned a new refresh token \(Self.tokenFingerprint(rotatedRefreshToken)).", onDebug: onDebug)
        } else {
            await emit("OpenAI accepted it, but did not return a new refresh token.", onDebug: onDebug)
        }
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
        do {
            try writeAuthFile(updatedAuthFile, storedAuthURL)
            await emit("saved new token into saved account file.", onDebug: onDebug)
        } catch {
            await emit("failed to save the new refresh token into \(displayPath(storedAuthURL)): \(error.localizedDescription)", onDebug: onDebug)
            await emit("OpenAI already returned a rotated token, so the old local refresh token may now be already used. Click Login if the next check says already used.", onDebug: onDebug)
            throw AuthAccountRefreshError.transient(error.localizedDescription)
        }

        if updateActiveAuth {
            let activeURL = store.activeAuthURL
            if fileManager.fileExists(atPath: activeURL.deletingLastPathComponent().path) {
                do {
                    try writeAuthFile(updatedAuthFile, activeURL)
                    await emit("saved new token into active auth file.", onDebug: onDebug)
                } catch {
                    await emit("failed to save the new refresh token into \(displayPath(activeURL)): \(error.localizedDescription)", onDebug: onDebug)
                    throw AuthAccountRefreshError.transient(error.localizedDescription)
                }
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
        storedAuthURL: URL,
        policy: AuthAccountRefreshPolicy,
        onDebug: AuthAccountRefreshDebugSink?
    ) async throws -> AuthAccountRefreshOutcome? {
        let activeURL = store.activeAuthURL
        guard fileManager.fileExists(atPath: activeURL.path),
              let activeAuthFile = try? StoredAuthFile(url: activeURL),
              activeAuthFile.isAPIKeyAuth == false,
              activeAuthFile.identityMatches(record: record),
              let activeRefreshToken = activeAuthFile.refreshToken,
              activeRefreshToken != staleRefreshToken else {
            await emit("no newer matching active auth was found. Another Codex or codex-auth process may have refreshed this token first, or the saved account file may be stale.", onDebug: onDebug)
            return nil
        }

        if let storedAuthFile = try? StoredAuthFile(url: storedAuthURL),
           isActiveAuthNewer(activeAuthFile, activeURL: activeURL, than: storedAuthFile, storedAuthURL: storedAuthURL) {
            await emit("found newer matching active auth; trying it as repair.", onDebug: onDebug)
        } else {
            await emit("found matching active auth with a different refresh token; trying it as repair.", onDebug: onDebug)
        }

        if policy == .whenCodexWouldRefresh,
           activeAuthFile.needsProactiveRefresh(
               now: now(),
               accessTokenRefreshWindow: Self.accessTokenRefreshWindow,
               fallbackRefreshInterval: Self.fallbackRefreshInterval
           ) == false {
            do {
                try writeAuthFile(activeAuthFile, storedAuthURL)
                await emit("copied matching active auth into saved account file; no OpenAI refresh needed before switch.", onDebug: onDebug)
            } catch {
                await emit("failed to copy matching active auth into \(displayPath(storedAuthURL)): \(error.localizedDescription)", onDebug: onDebug)
                throw AuthAccountRefreshError.transient(error.localizedDescription)
            }
            return .readyWithoutRefresh
        }

        do {
            try await refreshAndPersist(
                authFile: activeAuthFile,
                refreshToken: activeRefreshToken,
                record: record,
                storedAuthURL: storedAuthURL,
                updateActiveAuth: true,
                onDebug: onDebug
            )
            return .refreshed
        } catch AuthAccountRefreshError.reloginRequired {
            await emit("matching active auth also could not refresh.", onDebug: onDebug)
            return nil
        }
    }

    private func freshestMatchingAuthFile(
        record: AuthAccountRecord,
        storedAuthURL: URL,
        onDebug: AuthAccountRefreshDebugSink?
    ) async throws -> AuthFileSelection {
        let storedAuthFile = try StoredAuthFile(url: storedAuthURL)
        guard storedAuthFile.isAPIKeyAuth == false else {
            return AuthFileSelection(source: .stored, authFile: storedAuthFile)
        }

        let storedIdentityMatches = storedAuthFile.identityMatches(record: record)
        if storedIdentityMatches {
            await emit("saved file identity matches registry.", onDebug: onDebug)
        } else {
            await emit("saved file identity does not match registry.", onDebug: onDebug)
        }

        if storedIdentityMatches == false {
            await emit("Switch may be reading the wrong saved account file.", onDebug: onDebug)
            throw AuthAccountRefreshError.storedAuthIdentityMismatch
        }

        let activeURL = store.activeAuthURL
        guard fileManager.fileExists(atPath: activeURL.path) else {
            return AuthFileSelection(source: .stored, authFile: storedAuthFile)
        }

        guard let activeAuthFile = try? StoredAuthFile(url: activeURL),
              activeAuthFile.isAPIKeyAuth == false,
              activeAuthFile.identityMatches(record: record),
              activeAuthFile.refreshToken != nil else {
            await emit("active auth ~/.codex/auth.json is a different account. This is normal while switching.", onDebug: onDebug)
            return AuthFileSelection(source: .stored, authFile: storedAuthFile)
        }

        let activeAuthIsNewer = isActiveAuthNewer(
            activeAuthFile,
            activeURL: activeURL,
            than: storedAuthFile,
            storedAuthURL: storedAuthURL
        )
        if activeAuthIsNewer {
            await emit("active auth ~/.codex/auth.json is newer than saved copy.", onDebug: onDebug)
        } else {
            await emit("active auth ~/.codex/auth.json is not newer than saved copy.", onDebug: onDebug)
        }

        guard activeAuthIsNewer else {
            return AuthFileSelection(source: .stored, authFile: storedAuthFile)
        }

        do {
            try writeAuthFile(activeAuthFile, storedAuthURL)
        } catch {
            await emit("failed to copy newer active auth into \(displayPath(storedAuthURL)): \(error.localizedDescription)", onDebug: onDebug)
            await emit("saved account file is still stale. Switch cannot continue safely.", onDebug: onDebug)
            throw AuthAccountRefreshError.transient(error.localizedDescription)
        }
        await emit("saved account file was stale; copied newer active auth into saved account file.", onDebug: onDebug)
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

    private func emit(_ message: String, onDebug: AuthAccountRefreshDebugSink?) async {
        guard let onDebug else {
            return
        }
        await onDebug(AuthAccountRefreshDebugEvent(message: message))
    }

    private func displayPath(_ url: URL) -> String {
        let homePath = store.homeDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == homePath {
            return "~"
        }
        if path.hasPrefix("\(homePath)/") {
            return "~\(path.dropFirst(homePath.count))"
        }
        return path
    }

    private static func tokenFingerprint(_ token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
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
