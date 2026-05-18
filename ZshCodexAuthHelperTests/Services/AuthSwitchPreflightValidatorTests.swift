import Foundation
import Testing
@testable import ZshCodexAuthHelper

struct AuthSwitchPreflightValidatorTests {
    @Test func rowNumberUsesCodexAuthDisplayOrderBeforeRefreshing() async throws {
        let fixture = try AuthSwitchPreflightFixture()
        try fixture.writeRegistry(
            activeAccountKey: "user_damar::acct_damar",
            accounts: [
                .init(accountKey: "user_damar::acct_damar", email: "damar227@tuta.io", alias: "damar", plan: "plus"),
                .init(accountKey: "user_aisy::acct_aisy", email: "aisy.ahkusmawati938@gmail.com", alias: "aisy2", plan: "plus")
            ]
        )
        try fixture.writeStoredAuth(
            accountKey: "user_damar::acct_damar",
            email: "damar227@tuta.io",
            userID: "user_damar",
            accountID: "acct_damar",
            refreshToken: "refresh-damar"
        )
        try fixture.writeStoredAuth(
            accountKey: "user_aisy::acct_aisy",
            email: "aisy.ahkusmawati938@gmail.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-aisy"
        )
        let refresher = FakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy": .success(.init(
                    idToken: AuthSwitchPreflightFixture.jwt(email: "aisy.ahkusmawati938@gmail.com", userID: "user_aisy", accountID: "acct_aisy"),
                    accessToken: "access-aisy-new",
                    refreshToken: "refresh-aisy-new"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { Date(timeIntervalSince1970: 1_779_000_000) }
        )

        let account = try await validator.validateAndRefresh(query: "01")

        #expect(account.email == "aisy.ahkusmawati938@gmail.com")
        #expect(await refresher.requests == ["refresh-aisy"])
        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy-new")
        #expect(auth.tokens.accessToken == "access-aisy-new")
        #expect(auth.lastRefresh == "2026-05-17T06:40:00Z")
    }

    @Test func activeAccountRefreshAlsoUpdatesActiveAuthFile() async throws {
        let fixture = try AuthSwitchPreflightFixture()
        try fixture.writeRegistry(
            activeAccountKey: "user_damar::acct_damar",
            accounts: [
                .init(accountKey: "user_damar::acct_damar", email: "damar227@tuta.io", alias: "damar", plan: "plus")
            ]
        )
        try fixture.writeStoredAuth(
            accountKey: "user_damar::acct_damar",
            email: "damar227@tuta.io",
            userID: "user_damar",
            accountID: "acct_damar",
            refreshToken: "refresh-damar"
        )
        try fixture.copyStoredAuthToActive(accountKey: "user_damar::acct_damar")
        let refresher = FakeOAuthTokenRefresher(
            responses: [
                "refresh-damar": .success(.init(
                    idToken: AuthSwitchPreflightFixture.jwt(email: "damar227@tuta.io", userID: "user_damar", accountID: "acct_damar"),
                    accessToken: "access-damar-new",
                    refreshToken: "refresh-damar-new"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { Date(timeIntervalSince1970: 1_779_000_000) }
        )

        _ = try await validator.validateAndRefresh(query: "damar")

        let activeAuth = try fixture.readActiveAuth()
        #expect(activeAuth.tokens.refreshToken == "refresh-damar-new")
        #expect(activeAuth.tokens.accessToken == "access-damar-new")
    }

    @Test func reusedRefreshTokenStopsBeforeSwitchAndKeepsStoredAuthUnchanged() async throws {
        let fixture = try AuthSwitchPreflightFixture()
        try fixture.writeRegistry(
            activeAccountKey: "user_damar::acct_damar",
            accounts: [
                .init(accountKey: "user_aisy::acct_aisy", email: "aisy.ahkusmawati938@gmail.com", alias: "aisy2", plan: "plus")
            ]
        )
        try fixture.writeStoredAuth(
            accountKey: "user_aisy::acct_aisy",
            email: "aisy.ahkusmawati938@gmail.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-aisy"
        )
        let refresher = FakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy": .failure(.reloginRequired(.reused))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { Date(timeIntervalSince1970: 1_779_000_000) }
        )

        do {
            _ = try await validator.validateAndRefresh(query: "aisy")
            Issue.record("Expected reused refresh token to stop the switch.")
        } catch let error as AuthSwitchPreflightError {
            #expect(error == .reloginRequired(email: "aisy.ahkusmawati938@gmail.com", reason: .reused))
        }

        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy")
    }

    @Test func reusedStoredRefreshTokenRepairsFromMatchingActiveAuth() async throws {
        let fixture = try AuthSwitchPreflightFixture()
        try fixture.writeRegistry(
            activeAccountKey: "user_damar::acct_damar",
            accounts: [
                .init(accountKey: "user_aisy::acct_aisy", email: "aisy.ahkusmawati938@gmail.com", alias: "aisy2", plan: "plus")
            ]
        )
        try fixture.writeStoredAuth(
            accountKey: "user_aisy::acct_aisy",
            email: "aisy.ahkusmawati938@gmail.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-aisy-stale"
        )
        try fixture.writeActiveAuth(
            email: "aisy.ahkusmawati938@gmail.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-aisy-active"
        )
        let refresher = FakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy-stale": .failure(.reloginRequired(.reused)),
                "refresh-aisy-active": .success(.init(
                    idToken: AuthSwitchPreflightFixture.jwt(email: "aisy.ahkusmawati938@gmail.com", userID: "user_aisy", accountID: "acct_aisy"),
                    accessToken: "access-aisy-new",
                    refreshToken: "refresh-aisy-new"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { Date(timeIntervalSince1970: 1_779_000_000) }
        )

        let account = try await validator.validateAndRefresh(query: "aisy")

        #expect(account.email == "aisy.ahkusmawati938@gmail.com")
        #expect(await refresher.requests == ["refresh-aisy-stale", "refresh-aisy-active"])
        let storedAuth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(storedAuth.tokens.refreshToken == "refresh-aisy-new")
        #expect(storedAuth.tokens.accessToken == "access-aisy-new")
        let activeAuth = try fixture.readActiveAuth()
        #expect(activeAuth.tokens.refreshToken == "refresh-aisy-new")
        #expect(activeAuth.tokens.accessToken == "access-aisy-new")
    }

    @Test func reusedStoredRefreshTokenDoesNotRepairFromDifferentActiveAccount() async throws {
        let fixture = try AuthSwitchPreflightFixture()
        try fixture.writeRegistry(
            activeAccountKey: "user_damar::acct_damar",
            accounts: [
                .init(accountKey: "user_aisy::acct_aisy", email: "aisy.ahkusmawati938@gmail.com", alias: "aisy2", plan: "plus")
            ]
        )
        try fixture.writeStoredAuth(
            accountKey: "user_aisy::acct_aisy",
            email: "aisy.ahkusmawati938@gmail.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-aisy-stale"
        )
        try fixture.writeActiveAuth(
            email: "damar227@tuta.io",
            userID: "user_damar",
            accountID: "acct_damar",
            refreshToken: "refresh-damar-active"
        )
        let refresher = FakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy-stale": .failure(.reloginRequired(.reused))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { Date(timeIntervalSince1970: 1_779_000_000) }
        )

        do {
            _ = try await validator.validateAndRefresh(query: "aisy")
            Issue.record("Expected different active auth account to be rejected.")
        } catch let error as AuthSwitchPreflightError {
            #expect(error == .reloginRequired(email: "aisy.ahkusmawati938@gmail.com", reason: .reused))
        }

        #expect(await refresher.requests == ["refresh-aisy-stale"])
        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy-stale")
    }

    @Test func reusedStoredRefreshTokenDoesNotRetrySameActiveRefreshToken() async throws {
        let fixture = try AuthSwitchPreflightFixture()
        try fixture.writeRegistry(
            activeAccountKey: nil,
            accounts: [
                .init(accountKey: "user_aisy::acct_aisy", email: "aisy.ahkusmawati938@gmail.com", alias: "aisy2", plan: "plus")
            ]
        )
        try fixture.writeStoredAuth(
            accountKey: "user_aisy::acct_aisy",
            email: "aisy.ahkusmawati938@gmail.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-aisy-stale"
        )
        try fixture.writeActiveAuth(
            email: "aisy.ahkusmawati938@gmail.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-aisy-stale"
        )
        let refresher = FakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy-stale": .failure(.reloginRequired(.reused))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { Date(timeIntervalSince1970: 1_779_000_000) }
        )

        do {
            _ = try await validator.validateAndRefresh(query: "aisy")
            Issue.record("Expected same active refresh token to be rejected.")
        } catch let error as AuthSwitchPreflightError {
            #expect(error == .reloginRequired(email: "aisy.ahkusmawati938@gmail.com", reason: .reused))
        }

        #expect(await refresher.requests == ["refresh-aisy-stale"])
        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy-stale")
    }

    @Test func refreshResponseWithoutNewRefreshTokenStopsAndKeepsStoredAuthUnchanged() async throws {
        let fixture = try AuthSwitchPreflightFixture()
        try fixture.writeRegistry(
            activeAccountKey: nil,
            accounts: [
                .init(accountKey: "user_aisy::acct_aisy", email: "aisy.ahkusmawati938@gmail.com", alias: "aisy2", plan: "plus")
            ]
        )
        try fixture.writeStoredAuth(
            accountKey: "user_aisy::acct_aisy",
            email: "aisy.ahkusmawati938@gmail.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-aisy"
        )
        let refresher = FakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy": .success(.init(
                    idToken: AuthSwitchPreflightFixture.jwt(email: "aisy.ahkusmawati938@gmail.com", userID: "user_aisy", accountID: "acct_aisy"),
                    accessToken: "access-aisy-new",
                    refreshToken: nil
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { Date(timeIntervalSince1970: 1_779_000_000) }
        )

        do {
            _ = try await validator.validateAndRefresh(query: "aisy")
            Issue.record("Expected missing rotated refresh token to stop the switch.")
        } catch let error as AuthSwitchPreflightError {
            #expect(error == .invalidRefreshResponse(email: "aisy.ahkusmawati938@gmail.com"))
        }

        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy")
        #expect(auth.tokens.accessToken == "access-old")
    }

    @Test func refreshResponseWithSameRefreshTokenStopsAndKeepsStoredAuthUnchanged() async throws {
        let fixture = try AuthSwitchPreflightFixture()
        try fixture.writeRegistry(
            activeAccountKey: nil,
            accounts: [
                .init(accountKey: "user_aisy::acct_aisy", email: "aisy.ahkusmawati938@gmail.com", alias: "aisy2", plan: "plus")
            ]
        )
        try fixture.writeStoredAuth(
            accountKey: "user_aisy::acct_aisy",
            email: "aisy.ahkusmawati938@gmail.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-aisy"
        )
        let refresher = FakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy": .success(.init(
                    idToken: AuthSwitchPreflightFixture.jwt(email: "aisy.ahkusmawati938@gmail.com", userID: "user_aisy", accountID: "acct_aisy"),
                    accessToken: "access-aisy-new",
                    refreshToken: "refresh-aisy"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { Date(timeIntervalSince1970: 1_779_000_000) }
        )

        do {
            _ = try await validator.validateAndRefresh(query: "aisy")
            Issue.record("Expected unrotated refresh token to stop the switch.")
        } catch let error as AuthSwitchPreflightError {
            #expect(error == .invalidRefreshResponse(email: "aisy.ahkusmawati938@gmail.com"))
        }

        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy")
        #expect(auth.tokens.accessToken == "access-old")
    }

    @Test func ambiguousQueryRequiresMoreSpecificSelector() async throws {
        let fixture = try AuthSwitchPreflightFixture()
        try fixture.writeRegistry(
            activeAccountKey: nil,
            accounts: [
                .init(accountKey: "user_a::acct_a", email: "same@example.com", alias: "work", plan: "plus"),
                .init(accountKey: "user_b::acct_b", email: "same@example.com", alias: "personal", plan: "plus")
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: FakeOAuthTokenRefresher(responses: [:]),
            now: { Date(timeIntervalSince1970: 1_779_000_000) }
        )

        do {
            _ = try await validator.validateAndRefresh(query: "same")
            Issue.record("Expected ambiguous query to be rejected.")
        } catch let error as AuthSwitchPreflightError {
            #expect(error == .ambiguousAccount(query: "same"))
        }
    }

    @Test func outOfRangeNumericQueryCanStillMatchEmailText() async throws {
        let fixture = try AuthSwitchPreflightFixture()
        try fixture.writeRegistry(
            activeAccountKey: nil,
            accounts: [
                .init(accountKey: "user_sultan::acct_sultan", email: "sultan1819@example.com", alias: "", plan: "plus")
            ]
        )
        try fixture.writeStoredAuth(
            accountKey: "user_sultan::acct_sultan",
            email: "sultan1819@example.com",
            userID: "user_sultan",
            accountID: "acct_sultan",
            refreshToken: "refresh-sultan"
        )
        let refresher = FakeOAuthTokenRefresher(
            responses: [
                "refresh-sultan": .success(.init(
                    idToken: AuthSwitchPreflightFixture.jwt(email: "sultan1819@example.com", userID: "user_sultan", accountID: "acct_sultan"),
                    accessToken: "access-sultan-new",
                    refreshToken: "refresh-sultan-new"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { Date(timeIntervalSince1970: 1_779_000_000) }
        )

        let account = try await validator.validateAndRefresh(query: "1819")

        #expect(account.email == "sultan1819@example.com")
        #expect(await refresher.requests == ["refresh-sultan"])
    }
}

private actor FakeOAuthTokenRefresher: OAuthTokenRefreshing {
    private let responses: [String: Result<OAuthRefreshResponse, OAuthRefreshFailure>]
    private(set) var requests: [String] = []

    init(responses: [String: Result<OAuthRefreshResponse, OAuthRefreshFailure>]) {
        self.responses = responses
    }

    func refresh(refreshToken: String) async throws -> OAuthRefreshResponse {
        requests.append(refreshToken)

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

private struct AuthSwitchPreflightFixture {
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
            "schema_version": 3,
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
        refreshToken: String
    ) throws {
        let directory = homeDirectory.appendingPathComponent(".codex/accounts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try authJSON(
            email: email,
            userID: userID,
            accountID: accountID,
            refreshToken: refreshToken
        )
        .write(to: directory.appendingPathComponent("\(Self.encodedAccountKey(accountKey)).auth.json"), atomically: true, encoding: .utf8)
    }

    func copyStoredAuthToActive(accountKey: String) throws {
        let source = homeDirectory
            .appendingPathComponent(".codex/accounts")
            .appendingPathComponent("\(Self.encodedAccountKey(accountKey)).auth.json")
        let destination = homeDirectory.appendingPathComponent(".codex/auth.json")
        try FileManager.default.copyItem(at: source, to: destination)
    }

    func writeActiveAuth(
        email: String,
        userID: String,
        accountID: String,
        refreshToken: String
    ) throws {
        let directory = homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try authJSON(
            email: email,
            userID: userID,
            accountID: accountID,
            refreshToken: refreshToken
        )
        .write(to: directory.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
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

    private func authJSON(email: String, userID: String, accountID: String, refreshToken: String) -> String {
        """
        {
          "tokens": {
            "id_token": "\(Self.jwt(email: email, userID: userID, accountID: accountID))",
            "access_token": "access-old",
            "refresh_token": "\(refreshToken)",
            "account_id": "\(accountID)"
          },
          "last_refresh": "2026-05-11T00:00:00Z"
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

        var json: [String: Any] {
            [
                "account_key": accountKey,
                "chatgpt_account_id": accountKey.components(separatedBy: "::").last ?? "",
                "chatgpt_user_id": accountKey.components(separatedBy: "::").first ?? "",
                "email": email,
                "alias": alias,
                "created_at": 1,
                "plan": plan
            ]
        }
    }

    struct TestAuthFile: Decodable {
        var tokens: Tokens
        var lastRefresh: String

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
