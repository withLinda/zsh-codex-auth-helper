import Foundation
import Testing
@testable import ZshCodexAuthHelper

struct AuthHealthCheckServiceTests {
    private let now = Date(timeIntervalSince1970: 1_779_000_000)

    @Test func staleAccountRefreshesAndWritesRotatedToken() async throws {
        let fixture = try AuthHealthCheckFixture()
        try fixture.writeRegistry(
            activeAccountKey: nil,
            accounts: [
                .init(accountKey: "user_aisy::acct_aisy", email: "aisy@example.com", alias: "aisy", plan: "plus")
            ]
        )
        try fixture.writeStoredAuth(
            accountKey: "user_aisy::acct_aisy",
            email: "aisy@example.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-aisy",
            lastRefresh: "2026-05-16T00:00:00Z"
        )
        let refresher = HealthCheckFakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy": .success(.init(
                    idToken: AuthHealthCheckFixture.jwt(email: "aisy@example.com", userID: "user_aisy", accountID: "acct_aisy"),
                    accessToken: "access-aisy-new",
                    refreshToken: "refresh-aisy-new"
                ))
            ]
        )
        let service = AuthHealthCheckService(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        let summary = await service.run(onProgress: { _ in })

        #expect(summary.refreshed == 1)
        #expect(summary.results.map(\.status) == [.refreshed])
        #expect(await refresher.requests == ["refresh-aisy"])
        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy-new")
        #expect(auth.tokens.accessToken == "access-aisy-new")
        #expect(auth.lastRefresh == "2026-05-17T06:40:00Z")
    }

    @Test func accountRefreshedWithinTwentyFourHoursIsStillCheckedAndRefreshed() async throws {
        let fixture = try AuthHealthCheckFixture()
        try fixture.writeRegistry(
            activeAccountKey: nil,
            accounts: [
                .init(accountKey: "user_aisy::acct_aisy", email: "aisy@example.com", alias: "aisy", plan: "plus")
            ]
        )
        try fixture.writeStoredAuth(
            accountKey: "user_aisy::acct_aisy",
            email: "aisy@example.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-aisy",
            lastRefresh: "2026-05-17T05:45:00Z"
        )
        let refresher = HealthCheckFakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy": .success(.init(
                    idToken: AuthHealthCheckFixture.jwt(email: "aisy@example.com", userID: "user_aisy", accountID: "acct_aisy"),
                    accessToken: "access-aisy-new",
                    refreshToken: "refresh-aisy-new"
                ))
            ]
        )
        let service = AuthHealthCheckService(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        let summary = await service.run(onProgress: { _ in })

        #expect(summary.refreshed == 1)
        #expect(summary.results.map(\.status) == [.refreshed])
        #expect(await refresher.requests == ["refresh-aisy"])
        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy-new")
        #expect(auth.tokens.accessToken == "access-aisy-new")
    }

    @Test func fractionalLastRefreshWithinTwentyFourHoursIsStillCheckedAndRefreshed() async throws {
        let fixture = try AuthHealthCheckFixture()
        try fixture.writeRegistry(
            activeAccountKey: nil,
            accounts: [
                .init(accountKey: "user_aisy::acct_aisy", email: "aisy@example.com", alias: "aisy", plan: "plus")
            ]
        )
        try fixture.writeStoredAuth(
            accountKey: "user_aisy::acct_aisy",
            email: "aisy@example.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-aisy",
            lastRefresh: "2026-05-17T05:45:00.123456Z"
        )
        let refresher = HealthCheckFakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy": .success(.init(
                    idToken: AuthHealthCheckFixture.jwt(email: "aisy@example.com", userID: "user_aisy", accountID: "acct_aisy"),
                    accessToken: "access-aisy-new",
                    refreshToken: "refresh-aisy-new"
                ))
            ]
        )
        let service = AuthHealthCheckService(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        let summary = await service.run(onProgress: { _ in })

        #expect(summary.results.map(\.status) == [.refreshed])
        #expect(await refresher.requests == ["refresh-aisy"])
    }

    @Test func recentAccountWithReusedRefreshTokenReportsReloginRequired() async throws {
        let fixture = try AuthHealthCheckFixture()
        try fixture.writeRegistry(
            activeAccountKey: nil,
            accounts: [
                .init(accountKey: "user_aisy::acct_aisy", email: "aisy@example.com", alias: "aisy", plan: "plus")
            ]
        )
        try fixture.writeStoredAuth(
            accountKey: "user_aisy::acct_aisy",
            email: "aisy@example.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-aisy",
            lastRefresh: "2026-05-17T05:45:00Z"
        )
        let refresher = HealthCheckFakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy": .failure(.reloginRequired(.reused))
            ]
        )
        let service = AuthHealthCheckService(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        var transcriptLines: [String] = []
        let summary = await service.run { event in
            transcriptLines.append(event.transcriptLine)
        }

        #expect(summary.failed == 1)
        #expect(summary.results.map(\.status) == [.reloginRequired(.reused)])
        #expect(await refresher.requests == ["refresh-aisy"])
        #expect(transcriptLines.contains("aisy@example.com: needs login; refresh token was already used"))
        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy")
        #expect(auth.tokens.accessToken == "access-old")
    }

    @Test func missingLastRefreshIsCheckedAndRefreshed() async throws {
        let fixture = try AuthHealthCheckFixture()
        try fixture.writeRegistry(
            activeAccountKey: nil,
            accounts: [
                .init(accountKey: "user_aisy::acct_aisy", email: "aisy@example.com", alias: "aisy", plan: "plus")
            ]
        )
        try fixture.writeStoredAuth(
            accountKey: "user_aisy::acct_aisy",
            email: "aisy@example.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-aisy",
            lastRefresh: nil
        )
        let refresher = HealthCheckFakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy": .success(.init(
                    idToken: AuthHealthCheckFixture.jwt(email: "aisy@example.com", userID: "user_aisy", accountID: "acct_aisy"),
                    accessToken: "access-aisy-new",
                    refreshToken: "refresh-aisy-new"
                ))
            ]
        )
        let service = AuthHealthCheckService(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        let summary = await service.run(onProgress: { _ in })

        #expect(summary.results.map(\.status) == [.refreshed])
        #expect(await refresher.requests == ["refresh-aisy"])
    }

    @Test func apiKeyAuthIsSkippedWithoutRefreshRequest() async throws {
        let fixture = try AuthHealthCheckFixture()
        try fixture.writeRegistry(
            activeAccountKey: nil,
            accounts: [
                .init(
                    accountKey: "apikey::user::abc",
                    email: "aisy@example.com",
                    alias: "api",
                    plan: "plus",
                    authMode: "apikey"
                )
            ]
        )
        try fixture.writeAPIKeyAuth(accountKey: "apikey::user::abc")
        let refresher = HealthCheckFakeOAuthTokenRefresher(responses: [:])
        let service = AuthHealthCheckService(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        let summary = await service.run(onProgress: { _ in })

        #expect(summary.results.map(\.status) == [.skippedAPIKey])
        #expect(await refresher.requests.isEmpty)
    }

    @Test func activeAccountRefreshAlsoUpdatesActiveAuthFile() async throws {
        let fixture = try AuthHealthCheckFixture()
        try fixture.writeRegistry(
            activeAccountKey: "user_aisy::acct_aisy",
            accounts: [
                .init(accountKey: "user_aisy::acct_aisy", email: "aisy@example.com", alias: "aisy", plan: "plus")
            ]
        )
        try fixture.writeStoredAuth(
            accountKey: "user_aisy::acct_aisy",
            email: "aisy@example.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-aisy",
            lastRefresh: "2026-05-16T00:00:00Z"
        )
        try fixture.copyStoredAuthToActive(accountKey: "user_aisy::acct_aisy")
        let refresher = HealthCheckFakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy": .success(.init(
                    idToken: AuthHealthCheckFixture.jwt(email: "aisy@example.com", userID: "user_aisy", accountID: "acct_aisy"),
                    accessToken: "access-aisy-new",
                    refreshToken: "refresh-aisy-new"
                ))
            ]
        )
        let service = AuthHealthCheckService(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        _ = await service.run(onProgress: { _ in })

        let activeAuth = try fixture.readActiveAuth()
        #expect(activeAuth.tokens.refreshToken == "refresh-aisy-new")
        #expect(activeAuth.tokens.accessToken == "access-aisy-new")
    }

    @Test func failedRefreshOutcomesKeepStoredAuthUnchanged() async throws {
        let cases: [(String, Result<OAuthRefreshResponse, OAuthRefreshFailure>, AuthHealthCheckStatus)] = [
            ("reused", .failure(.reloginRequired(.reused)), .reloginRequired(.reused)),
            ("missing-rotation", .success(.init(
                idToken: AuthHealthCheckFixture.jwt(email: "aisy@example.com", userID: "user_aisy", accountID: "acct_aisy"),
                accessToken: "access-aisy-new",
                refreshToken: nil
            )), .invalidRefreshResponse),
            ("same-token", .success(.init(
                idToken: AuthHealthCheckFixture.jwt(email: "aisy@example.com", userID: "user_aisy", accountID: "acct_aisy"),
                accessToken: "access-aisy-new",
                refreshToken: "refresh-aisy"
            )), .invalidRefreshResponse),
            ("mismatch", .success(.init(
                idToken: AuthHealthCheckFixture.jwt(email: "aisy@example.com", userID: "user_other", accountID: "acct_other"),
                accessToken: "access-aisy-new",
                refreshToken: "refresh-aisy-new"
            )), .accountMismatch)
        ]

        for testCase in cases {
            let fixture = try AuthHealthCheckFixture()
            try fixture.writeRegistry(
                activeAccountKey: nil,
                accounts: [
                    .init(accountKey: "user_aisy::acct_aisy", email: "aisy@example.com", alias: "aisy", plan: "plus")
                ]
            )
            try fixture.writeStoredAuth(
                accountKey: "user_aisy::acct_aisy",
                email: "aisy@example.com",
                userID: "user_aisy",
                accountID: "acct_aisy",
                refreshToken: "refresh-aisy",
                lastRefresh: "2026-05-16T00:00:00Z"
            )
            let refresher = HealthCheckFakeOAuthTokenRefresher(responses: ["refresh-aisy": testCase.1])
            let service = AuthHealthCheckService(
                homeDirectory: fixture.homeDirectory,
                refresher: refresher,
                now: { now }
            )

            let summary = await service.run(onProgress: { _ in })

            #expect(summary.results.map(\.status) == [testCase.2], "case \(testCase.0)")
            let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
            #expect(auth.tokens.refreshToken == "refresh-aisy", "case \(testCase.0)")
            #expect(auth.tokens.accessToken == "access-old", "case \(testCase.0)")
        }
    }

    @Test func healthCheckRefreshesOneAccountAtATime() async throws {
        let fixture = try AuthHealthCheckFixture()
        try fixture.writeRegistry(
            activeAccountKey: nil,
            accounts: [
                .init(accountKey: "user_a::acct_a", email: "a@example.com", alias: "a", plan: "plus"),
                .init(accountKey: "user_b::acct_b", email: "b@example.com", alias: "b", plan: "plus")
            ]
        )
        try fixture.writeStoredAuth(
            accountKey: "user_a::acct_a",
            email: "a@example.com",
            userID: "user_a",
            accountID: "acct_a",
            refreshToken: "refresh-a",
            lastRefresh: "2026-05-16T00:00:00Z"
        )
        try fixture.writeStoredAuth(
            accountKey: "user_b::acct_b",
            email: "b@example.com",
            userID: "user_b",
            accountID: "acct_b",
            refreshToken: "refresh-b",
            lastRefresh: "2026-05-16T00:00:00Z"
        )
        let refresher = HealthCheckFakeOAuthTokenRefresher(
            responses: [
                "refresh-a": .success(.init(
                    idToken: AuthHealthCheckFixture.jwt(email: "a@example.com", userID: "user_a", accountID: "acct_a"),
                    accessToken: "access-a-new",
                    refreshToken: "refresh-a-new"
                )),
                "refresh-b": .success(.init(
                    idToken: AuthHealthCheckFixture.jwt(email: "b@example.com", userID: "user_b", accountID: "acct_b"),
                    accessToken: "access-b-new",
                    refreshToken: "refresh-b-new"
                ))
            ],
            delay: 25_000_000
        )
        let service = AuthHealthCheckService(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        let summary = await service.run(onProgress: { _ in })

        #expect(summary.refreshed == 2)
        #expect(await refresher.maxConcurrentRequests == 1)
    }

    @Test func heldAccountLockSkipsAccountWithoutRefreshRequest() async throws {
        let fixture = try AuthHealthCheckFixture()
        try fixture.writeRegistry(
            activeAccountKey: nil,
            accounts: [
                .init(accountKey: "user_aisy::acct_aisy", email: "aisy@example.com", alias: "aisy", plan: "plus")
            ]
        )
        try fixture.writeStoredAuth(
            accountKey: "user_aisy::acct_aisy",
            email: "aisy@example.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-aisy",
            lastRefresh: "2026-05-16T00:00:00Z"
        )
        let lock = AuthAccountFileLock(homeDirectory: fixture.homeDirectory)
        let heldLock = try #require(try lock.tryLock(accountKey: "user_aisy::acct_aisy"))
        let refresher = HealthCheckFakeOAuthTokenRefresher(responses: [:])
        let service = AuthHealthCheckService(
            homeDirectory: fixture.homeDirectory,
            lock: lock,
            refresher: refresher,
            now: { now }
        )

        let summary = await service.run(onProgress: { _ in })

        #expect(summary.results.map(\.status) == [.busy])
        #expect(await refresher.requests.isEmpty)
        heldLock.release()
    }
}

private actor HealthCheckFakeOAuthTokenRefresher: OAuthTokenRefreshing {
    private let responses: [String: Result<OAuthRefreshResponse, OAuthRefreshFailure>]
    private let delay: UInt64
    private(set) var requests: [String] = []
    private(set) var maxConcurrentRequests = 0
    private var currentRequests = 0

    init(
        responses: [String: Result<OAuthRefreshResponse, OAuthRefreshFailure>],
        delay: UInt64 = 0
    ) {
        self.responses = responses
        self.delay = delay
    }

    func refresh(refreshToken: String) async throws -> OAuthRefreshResponse {
        requests.append(refreshToken)
        currentRequests += 1
        maxConcurrentRequests = max(maxConcurrentRequests, currentRequests)
        if delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
        defer {
            currentRequests -= 1
        }

        switch responses[refreshToken] {
        case .success(let response):
            return response
        case .failure(let failure):
            throw failure
        case nil:
            throw OAuthRefreshFailure.transient("missing fake response")
        }
    }
}

private struct AuthHealthCheckFixture {
    let homeDirectory: URL

    init() throws {
        homeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zsh-codex-auth-helper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
    }

    func writeRegistry(activeAccountKey: String?, accounts: [RegistryAccount]) throws {
        let directory = homeDirectory.appendingPathComponent(".codex/accounts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var payload: [String: Any] = [
            "schema_version": 4,
            "accounts": accounts.map(\.json)
        ]
        if let activeAccountKey {
            payload["active_account_key"] = activeAccountKey
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try data.write(to: directory.appendingPathComponent("registry.json"), options: .atomic)
    }

    func writeStoredAuth(
        accountKey: String,
        email: String,
        userID: String,
        accountID: String,
        refreshToken: String,
        lastRefresh: String?
    ) throws {
        let directory = homeDirectory.appendingPathComponent(".codex/accounts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try authJSON(
            email: email,
            userID: userID,
            accountID: accountID,
            refreshToken: refreshToken,
            lastRefresh: lastRefresh
        )
        .write(to: directory.appendingPathComponent("\(Self.encodedAccountKey(accountKey)).auth.json"), atomically: true, encoding: .utf8)
    }

    func writeAPIKeyAuth(accountKey: String) throws {
        let directory = homeDirectory.appendingPathComponent(".codex/accounts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #"{"OPENAI_API_KEY":"sk-test"}"#
            .write(to: directory.appendingPathComponent("\(Self.encodedAccountKey(accountKey)).auth.json"), atomically: true, encoding: .utf8)
    }

    func copyStoredAuthToActive(accountKey: String) throws {
        let source = homeDirectory
            .appendingPathComponent(".codex/accounts")
            .appendingPathComponent("\(Self.encodedAccountKey(accountKey)).auth.json")
        let destination = homeDirectory.appendingPathComponent(".codex/auth.json")
        try FileManager.default.copyItem(at: source, to: destination)
    }

    func readStoredAuth(accountKey: String) throws -> TestAuthFile {
        let path = homeDirectory
            .appendingPathComponent(".codex/accounts")
            .appendingPathComponent("\(Self.encodedAccountKey(accountKey)).auth.json")
        return try JSONDecoder().decode(TestAuthFile.self, from: Data(contentsOf: path))
    }

    func readActiveAuth() throws -> TestAuthFile {
        try JSONDecoder().decode(TestAuthFile.self, from: Data(contentsOf: homeDirectory.appendingPathComponent(".codex/auth.json")))
    }

    static func jwt(email: String, userID: String, accountID: String) -> String {
        let payload: [String: Any] = [
            "email": email,
            "https://api.openai.com/auth": [
                "chatgpt_account_id": accountID,
                "chatgpt_user_id": userID,
                "chatgpt_plan_type": "plus"
            ]
        ]
        return "\(base64URL(["alg": "none"])).\(base64URL(payload)).signature"
    }

    private func authJSON(
        email: String,
        userID: String,
        accountID: String,
        refreshToken: String,
        lastRefresh: String?
    ) -> String {
        let lastRefreshLine = lastRefresh.map { #","last_refresh":"\#($0)""# } ?? ""
        return """
        {
          "tokens": {
            "id_token": "\(Self.jwt(email: email, userID: userID, accountID: accountID))",
            "access_token": "access-old",
            "refresh_token": "\(refreshToken)",
            "account_id": "\(accountID)"
          }\(lastRefreshLine)
        }
        """
    }

    private static func encodedAccountKey(_ accountKey: String) -> String {
        Data(accountKey.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URL(_ value: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    struct RegistryAccount {
        var accountKey: String
        var email: String
        var alias: String
        var plan: String
        var authMode: String?

        var json: [String: Any] {
            var value: [String: Any] = [
                "account_key": accountKey,
                "chatgpt_account_id": accountKey.components(separatedBy: "::").last ?? "",
                "chatgpt_user_id": accountKey.components(separatedBy: "::").first ?? "",
                "email": email,
                "alias": alias,
                "created_at": 1,
                "plan": plan
            ]
            if let authMode {
                value["auth_mode"] = authMode
            }
            return value
        }
    }

    struct TestAuthFile: Decodable {
        var tokens: Tokens
        var lastRefresh: String?

        enum CodingKeys: String, CodingKey {
            case tokens
            case lastRefresh = "last_refresh"
        }
    }

    struct Tokens: Decodable {
        var accessToken: String
        var refreshToken: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
        }
    }
}
