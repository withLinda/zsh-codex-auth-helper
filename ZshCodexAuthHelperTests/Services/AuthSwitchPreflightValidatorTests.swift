import Foundation
import Testing
@testable import ZshCodexAuthHelper

struct AuthSwitchPreflightValidatorTests {
    private let now = Date(timeIntervalSince1970: 1_779_000_000)

    @Test func nearExpiryAccessTokenRefreshesAndWritesRotatedToken() async throws {
        let fixture = try AuthSwitchPreflightFixture()
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
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now.addingTimeInterval(5 * 60))
        )
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy": .success(.init(
                    idToken: AuthSwitchPreflightFixture.jwt(email: "aisy@example.com", userID: "user_aisy", accountID: "acct_aisy"),
                    accessToken: "access-aisy-new",
                    refreshToken: "refresh-aisy-new"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        let result = try await validator.prepareForSwitch(query: "aisy")

        #expect(result.status == .refreshed)
        #expect(await refresher.requests == ["refresh-aisy"])
        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy-new")
        #expect(auth.tokens.accessToken == "access-aisy-new")
        #expect(auth.lastRefresh == "2026-05-17T06:40:00Z")
    }

    @Test func freshAccessTokenDoesNotSpendRefreshToken() async throws {
        let fixture = try AuthSwitchPreflightFixture()
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
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now.addingTimeInterval(5 * 60 + 1))
        )
        let refresher = PreflightFakeOAuthTokenRefresher(responses: [:])
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        let result = try await validator.prepareForSwitch(query: "aisy")

        #expect(result.status == .readyWithoutRefresh)
        #expect(result.transcriptLine == "Saved access token does not need refresh yet for aisy@example.com.")
        #expect(await refresher.requests.isEmpty)
        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy")
    }

    @Test func unreadableAccessTokenAtEightDayBoundaryDoesNotSpendRefreshToken() async throws {
        let fixture = try AuthSwitchPreflightFixture()
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
            accessToken: "not-a-jwt",
            lastRefresh: "2026-05-09T06:40:00Z"
        )
        let refresher = PreflightFakeOAuthTokenRefresher(responses: [:])
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        let result = try await validator.prepareForSwitch(query: "aisy")

        #expect(result.status == .readyWithoutRefresh)
        #expect(result.transcriptLine == "Saved access token does not need refresh yet for aisy@example.com.")
        #expect(await refresher.requests.isEmpty)
    }

    @Test func unreadableAccessTokenOlderThanEightDaysRefreshes() async throws {
        let fixture = try AuthSwitchPreflightFixture()
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
            accessToken: "not-a-jwt",
            lastRefresh: "2026-05-09T06:39:59Z"
        )
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy": .success(.init(
                    idToken: AuthSwitchPreflightFixture.jwt(email: "aisy@example.com", userID: "user_aisy", accountID: "acct_aisy"),
                    accessToken: "access-aisy-new",
                    refreshToken: "refresh-aisy-new"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        let result = try await validator.prepareForSwitch(query: "aisy")

        #expect(result.status == .refreshed)
        #expect(await refresher.requests == ["refresh-aisy"])
    }

    @Test func permanentRefreshFailuresBlockSwitchAndExplainRelogin() async throws {
        let cases: [(String, OAuthRefreshFailureReason)] = [
            ("expired", .expired),
            ("reused", .reused),
            ("revoked", .revoked)
        ]

        for testCase in cases {
            let fixture = try AuthSwitchPreflightFixture()
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
                accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now)
            )
            let refresher = PreflightFakeOAuthTokenRefresher(
                responses: [
                    "refresh-aisy": .failure(.reloginRequired(testCase.1))
                ]
            )
            let validator = AuthSwitchPreflightValidator(
                homeDirectory: fixture.homeDirectory,
                refresher: refresher,
                now: { now }
            )

            do {
                _ = try await validator.prepareForSwitch(query: "aisy")
                Issue.record("Expected \(testCase.0) refresh token to block the switch.")
            } catch let error as AuthSwitchPreflightError {
                #expect(error == .reloginRequired(email: "aisy@example.com", reason: testCase.1))
                #expect(error.localizedDescription.contains("Click Login and finish browser login, then switch again."))
                #expect(error.localizedDescription.contains("Save / Update Login only if you want to set or change an alias."))
            }

            #expect(await refresher.requests == ["refresh-aisy"])
        }
    }

    @Test func transientRefreshFailureBlocksSwitch() async throws {
        let fixture = try AuthSwitchPreflightFixture()
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
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now)
        )
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy": .failure(.transient("offline"))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        do {
            _ = try await validator.prepareForSwitch(query: "aisy")
            Issue.record("Expected transient refresh failure to block the switch.")
        } catch let error as AuthSwitchPreflightError {
            #expect(error == .transient(email: "aisy@example.com", message: "offline"))
        }

        #expect(await refresher.requests == ["refresh-aisy"])
    }

    @Test func invalidRefreshResponsesBlockSwitchAndKeepStoredAuthUnchanged() async throws {
        let cases: [(String, OAuthRefreshResponse, AuthSwitchPreflightError)] = [
            (
                "missing rotated token",
                .init(
                    idToken: AuthSwitchPreflightFixture.jwt(email: "aisy@example.com", userID: "user_aisy", accountID: "acct_aisy"),
                    accessToken: "access-aisy-new",
                    refreshToken: nil
                ),
                .invalidRefreshResponse(email: "aisy@example.com")
            ),
            (
                "different account",
                .init(
                    idToken: AuthSwitchPreflightFixture.jwt(email: "other@example.com", userID: "user_other", accountID: "acct_other"),
                    accessToken: "access-other-new",
                    refreshToken: "refresh-other-new"
                ),
                .accountMismatch(email: "aisy@example.com")
            )
        ]

        for testCase in cases {
            let fixture = try AuthSwitchPreflightFixture()
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
                accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now)
            )
            let refresher = PreflightFakeOAuthTokenRefresher(
                responses: [
                    "refresh-aisy": .success(testCase.1)
                ]
            )
            let validator = AuthSwitchPreflightValidator(
                homeDirectory: fixture.homeDirectory,
                refresher: refresher,
                now: { now }
            )

            do {
                _ = try await validator.prepareForSwitch(query: "aisy")
                Issue.record("Expected \(testCase.0) to block the switch.")
            } catch let error as AuthSwitchPreflightError {
                #expect(error == testCase.2)
            }

            let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
            #expect(auth.tokens.refreshToken == "refresh-aisy")
        }
    }

    @Test func matchingActiveAuthRepairsStaleStoredRefreshTokenOnce() async throws {
        let fixture = try AuthSwitchPreflightFixture()
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
            refreshToken: "refresh-stale",
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now),
            lastRefresh: "2026-05-17T06:30:00Z"
        )
        try fixture.writeActiveAuth(
            email: "aisy@example.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-active",
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now),
            lastRefresh: "2026-05-17T06:20:00Z"
        )
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-stale": .failure(.reloginRequired(.reused)),
                "refresh-active": .success(.init(
                    idToken: AuthSwitchPreflightFixture.jwt(email: "aisy@example.com", userID: "user_aisy", accountID: "acct_aisy"),
                    accessToken: "access-repaired",
                    refreshToken: "refresh-repaired"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        let result = try await validator.prepareForSwitch(query: "aisy")

        #expect(result.status == .refreshed)
        #expect(await refresher.requests == ["refresh-stale", "refresh-active"])
        let storedAuth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(storedAuth.tokens.refreshToken == "refresh-repaired")
        let activeAuth = try fixture.readActiveAuth()
        #expect(activeAuth.tokens.refreshToken == "refresh-repaired")
    }

    @Test func differentAccountActiveAuthIsNeverUsedForRepair() async throws {
        let fixture = try AuthSwitchPreflightFixture()
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
            refreshToken: "refresh-stale",
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now)
        )
        try fixture.writeActiveAuth(
            email: "damar@example.com",
            userID: "user_damar",
            accountID: "acct_damar",
            refreshToken: "refresh-damar"
        )
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-stale": .failure(.reloginRequired(.reused)),
                "refresh-damar": .success(.init(
                    idToken: AuthSwitchPreflightFixture.jwt(email: "damar@example.com", userID: "user_damar", accountID: "acct_damar"),
                    accessToken: "access-damar-new",
                    refreshToken: "refresh-damar-new"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        do {
            _ = try await validator.prepareForSwitch(query: "aisy")
            Issue.record("Expected stale stored token to block the switch.")
        } catch let error as AuthSwitchPreflightError {
            #expect(error == .reloginRequired(email: "aisy@example.com", reason: .reused))
        }

        #expect(await refresher.requests == ["refresh-stale"])
    }

    @Test func apiKeyAuthSkipsOAuthRefresh() async throws {
        let fixture = try AuthSwitchPreflightFixture()
        try fixture.writeRegistry(
            activeAccountKey: nil,
            accounts: [
                .init(accountKey: "apikey::user::abc", email: "api@example.com", alias: "api", plan: "plus")
            ]
        )
        try fixture.writeAPIKeyAuth(accountKey: "apikey::user::abc")
        let refresher = PreflightFakeOAuthTokenRefresher(responses: [:])
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        let result = try await validator.prepareForSwitch(query: "api")

        #expect(result.status == .skippedAPIKey)
        #expect(await refresher.requests.isEmpty)
    }

    @Test func rowNumberUsesCodexAuthDisplayOrderAndRefreshesSelectedAccount() async throws {
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
            refreshToken: "refresh-aisy",
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now)
        )
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy": .success(AuthSwitchPreflightFixture.refreshResponse(
                    email: "aisy.ahkusmawati938@gmail.com",
                    userID: "user_aisy",
                    accountID: "acct_aisy",
                    accessToken: "access-aisy-new",
                    refreshToken: "refresh-aisy-new"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        let account = try await validator.prepareForSwitch(query: "01")

        #expect(account.account.email == "aisy.ahkusmawati938@gmail.com")
        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy-new")
        #expect(auth.tokens.accessToken == "access-aisy-new")
        #expect(auth.lastRefresh == "2026-05-17T06:40:00Z")
    }

    @Test func nearExpiryActiveAccountPreflightRotatesActiveAuthFile() async throws {
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
            refreshToken: "refresh-damar",
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now)
        )
        try fixture.copyStoredAuthToActive(accountKey: "user_damar::acct_damar")
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-damar": .success(AuthSwitchPreflightFixture.refreshResponse(
                    email: "damar227@tuta.io",
                    userID: "user_damar",
                    accountID: "acct_damar",
                    accessToken: "access-damar-new",
                    refreshToken: "refresh-damar-new"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        _ = try await validator.prepareForSwitch(query: "damar")

        let activeAuth = try fixture.readActiveAuth()
        #expect(activeAuth.tokens.refreshToken == "refresh-damar-new")
        #expect(activeAuth.tokens.accessToken == "access-damar-new")
    }

    @Test func nearExpiryStoredRefreshTimestampRefreshesDuringSwitch() async throws {
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
            refreshToken: "refresh-aisy",
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now),
            lastRefresh: "2026-05-17T06:20:00Z"
        )
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy": .success(AuthSwitchPreflightFixture.refreshResponse(
                    email: "aisy.ahkusmawati938@gmail.com",
                    userID: "user_aisy",
                    accountID: "acct_aisy",
                    accessToken: "access-aisy-new",
                    refreshToken: "refresh-aisy-new"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        let account = try await validator.prepareForSwitch(query: "aisy")

        #expect(account.account.email == "aisy.ahkusmawati938@gmail.com")
        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy-new")
    }

    @Test func nearExpiryFractionalStoredRefreshTimestampRefreshesDuringSwitch() async throws {
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
            refreshToken: "refresh-aisy",
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now),
            lastRefresh: "2026-05-17T06:20:00.123456Z"
        )
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy": .success(AuthSwitchPreflightFixture.refreshResponse(
                    email: "aisy.ahkusmawati938@gmail.com",
                    userID: "user_aisy",
                    accountID: "acct_aisy",
                    accessToken: "access-aisy-new",
                    refreshToken: "refresh-aisy-new"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        let account = try await validator.prepareForSwitch(query: "aisy")

        #expect(account.account.email == "aisy.ahkusmawati938@gmail.com")
        #expect(await refresher.requests == ["refresh-aisy"])
    }

    @Test func newerMatchingActiveAuthIsCopiedToStoredAuthThenRefreshed() async throws {
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
            refreshToken: "refresh-aisy-stored",
            lastRefresh: "2026-05-17T05:00:00Z"
        )
        try fixture.writeActiveAuth(
            email: "aisy.ahkusmawati938@gmail.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-aisy-active",
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now),
            lastRefresh: "2026-05-17T06:25:00Z"
        )
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy-active": .success(AuthSwitchPreflightFixture.refreshResponse(
                    email: "aisy.ahkusmawati938@gmail.com",
                    userID: "user_aisy",
                    accountID: "acct_aisy",
                    accessToken: "access-aisy-new",
                    refreshToken: "refresh-aisy-new"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        _ = try await validator.prepareForSwitch(query: "aisy")

        let storedAuth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(storedAuth.tokens.refreshToken == "refresh-aisy-new")
        #expect(await refresher.requests == ["refresh-aisy-active"])
    }

    @Test func newerMatchingActiveAuthIsCopiedToStoredAuthThenRefreshedOutsideRecentWindow() async throws {
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
            refreshToken: "refresh-aisy-stored",
            lastRefresh: "2026-05-17T05:00:00Z"
        )
        try fixture.writeActiveAuth(
            email: "aisy.ahkusmawati938@gmail.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-aisy-active",
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now),
            lastRefresh: "2026-05-17T06:00:00Z"
        )
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy-active": .success(AuthSwitchPreflightFixture.refreshResponse(
                    email: "aisy.ahkusmawati938@gmail.com",
                    userID: "user_aisy",
                    accountID: "acct_aisy",
                    accessToken: "access-aisy-new",
                    refreshToken: "refresh-aisy-new"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        _ = try await validator.prepareForSwitch(query: "aisy")

        let storedAuth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(storedAuth.tokens.refreshToken == "refresh-aisy-new")
        #expect(storedAuth.tokens.accessToken == "access-aisy-new")
        let activeAuth = try fixture.readActiveAuth()
        #expect(activeAuth.tokens.refreshToken == "refresh-aisy-new")
        #expect(activeAuth.tokens.accessToken == "access-aisy-new")
    }

    @Test func olderActiveAuthIsIgnoredAndStoredAuthRefreshes() async throws {
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
            refreshToken: "refresh-aisy-stored",
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now),
            lastRefresh: "2026-05-17T06:00:00Z"
        )
        try fixture.writeActiveAuth(
            email: "aisy.ahkusmawati938@gmail.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-aisy-active",
            lastRefresh: "2026-05-17T05:00:00Z"
        )
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy-stored": .success(AuthSwitchPreflightFixture.refreshResponse(
                    email: "aisy.ahkusmawati938@gmail.com",
                    userID: "user_aisy",
                    accountID: "acct_aisy",
                    accessToken: "access-aisy-new",
                    refreshToken: "refresh-aisy-new"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        _ = try await validator.prepareForSwitch(query: "aisy")

        let storedAuth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(storedAuth.tokens.refreshToken == "refresh-aisy-new")
    }

    @Test func differentAccountActiveAuthIsNormalAndFreshStoredAuthDoesNotRefresh() async throws {
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
            refreshToken: "refresh-aisy-stored",
            lastRefresh: "2026-05-17T06:00:00Z"
        )
        try fixture.writeActiveAuth(
            email: "damar227@tuta.io",
            userID: "user_damar",
            accountID: "acct_damar",
            refreshToken: "refresh-damar-active",
            lastRefresh: "2026-05-17T06:25:00Z"
        )
        let refresher = PreflightFakeOAuthTokenRefresher(responses: [:])
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )
        let logs = SwitchDebugLogCollector()

        let result = try await validator.prepareForSwitch(query: "aisy") { event in
            await logs.append(event)
        }

        #expect(result.status == .readyWithoutRefresh)
        #expect(await refresher.requests.isEmpty)
        let storedAuth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(storedAuth.tokens.refreshToken == "refresh-aisy-stored")
        let lines = await logs.lines()
        #expect(lines.contains("Switch check: active auth ~/.codex/auth.json is a different account. This is normal while switching."))
        #expect(lines.contains("Switch check: saved access token is fresh enough; no OpenAI refresh needed before switch."))
    }

    @Test func nearExpiryStoredRefreshTokenIsSpentDuringSwitchPreflight() async throws {
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
            refreshToken: "refresh-aisy",
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now)
        )
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy": .success(AuthSwitchPreflightFixture.refreshResponse(
                    email: "aisy.ahkusmawati938@gmail.com",
                    userID: "user_aisy",
                    accountID: "acct_aisy",
                    accessToken: "access-aisy-new",
                    refreshToken: "refresh-aisy-new"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        let account = try await validator.prepareForSwitch(query: "aisy")

        #expect(account.account.email == "aisy.ahkusmawati938@gmail.com")
        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy-new")
    }

    @Test func matchingActiveAuthIsCopiedToStoredAuthAndRefreshed() async throws {
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
            refreshToken: "refresh-aisy-active",
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now),
            lastRefresh: "2026-05-17T06:25:00Z"
        )
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy-active": .success(AuthSwitchPreflightFixture.refreshResponse(
                    email: "aisy.ahkusmawati938@gmail.com",
                    userID: "user_aisy",
                    accountID: "acct_aisy",
                    accessToken: "access-aisy-new",
                    refreshToken: "refresh-aisy-new"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        let account = try await validator.prepareForSwitch(query: "aisy")

        #expect(account.account.email == "aisy.ahkusmawati938@gmail.com")
        let storedAuth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(storedAuth.tokens.refreshToken == "refresh-aisy-new")
        #expect(storedAuth.tokens.accessToken == "access-aisy-new")
        let activeAuth = try fixture.readActiveAuth()
        #expect(activeAuth.tokens.refreshToken == "refresh-aisy-new")
        #expect(activeAuth.tokens.accessToken == "access-aisy-new")
    }

    @Test func differentActiveAuthDoesNotRepairButStoredAuthRefreshes() async throws {
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
            refreshToken: "refresh-aisy-stale",
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now)
        )
        try fixture.writeActiveAuth(
            email: "damar227@tuta.io",
            userID: "user_damar",
            accountID: "acct_damar",
            refreshToken: "refresh-damar-active"
        )
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy-stale": .success(AuthSwitchPreflightFixture.refreshResponse(
                    email: "aisy.ahkusmawati938@gmail.com",
                    userID: "user_aisy",
                    accountID: "acct_aisy",
                    accessToken: "access-aisy-new",
                    refreshToken: "refresh-aisy-new"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        let account = try await validator.prepareForSwitch(query: "aisy")

        #expect(account.account.email == "aisy.ahkusmawati938@gmail.com")
        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy-new")
    }

    @Test func sameActiveRefreshTokenStillRefreshesStoredAuth() async throws {
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
            refreshToken: "refresh-aisy-stale",
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now)
        )
        try fixture.writeActiveAuth(
            email: "aisy.ahkusmawati938@gmail.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-aisy-stale"
        )
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy-stale": .success(AuthSwitchPreflightFixture.refreshResponse(
                    email: "aisy.ahkusmawati938@gmail.com",
                    userID: "user_aisy",
                    accountID: "acct_aisy",
                    accessToken: "access-aisy-new",
                    refreshToken: "refresh-aisy-new"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        let account = try await validator.prepareForSwitch(query: "aisy")

        #expect(account.account.email == "aisy.ahkusmawati938@gmail.com")
        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy-new")
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
        let validator = AuthSwitchPreflightValidator(homeDirectory: fixture.homeDirectory)

        do {
            _ = try await validator.prepareForSwitch(query: "same")
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
            refreshToken: "refresh-sultan",
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now)
        )
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-sultan": .success(AuthSwitchPreflightFixture.refreshResponse(
                    email: "sultan1819@example.com",
                    userID: "user_sultan",
                    accountID: "acct_sultan",
                    accessToken: "access-sultan-new",
                    refreshToken: "refresh-sultan-new"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )

        let account = try await validator.prepareForSwitch(query: "1819")

        #expect(account.account.email == "sultan1819@example.com")
        #expect(await refresher.requests == ["refresh-sultan"])
    }

    @Test func heldAccountLockStopsBeforeSwitchAndKeepsStoredAuthUnchanged() async throws {
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
        let lock = AuthAccountFileLock(homeDirectory: fixture.homeDirectory)
        let heldLock = try #require(try lock.tryLock(accountKey: "user_aisy::acct_aisy"))
        let validator = AuthSwitchPreflightValidator(homeDirectory: fixture.homeDirectory, lock: lock)

        do {
            _ = try await validator.prepareForSwitch(query: "aisy")
            Issue.record("Expected held account lock to stop the switch.")
        } catch let error as AuthSwitchPreflightError {
            #expect(error == .accountBusy(email: "aisy.ahkusmawati938@gmail.com"))
        }

        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy")
        heldLock.release()
    }

    @Test func freshAccessTokenDoesNotRefreshAndLogsSafeSwitchDetails() async throws {
        let fixture = try AuthSwitchPreflightFixture()
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
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now.addingTimeInterval(3600))
        )
        let refresher = PreflightFakeOAuthTokenRefresher(responses: [:])
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )
        let logs = SwitchDebugLogCollector()

        let result = try await validator.prepareForSwitch(query: "aisy") { event in
            await logs.append(event)
        }

        #expect(result.status == .readyWithoutRefresh)
        #expect(await refresher.requests.isEmpty)
        let storedAuth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(storedAuth.tokens.refreshToken == "refresh-aisy")
        let lines = await logs.lines()
        #expect(lines.contains("Switch check: selected aisy@example.com."))
        #expect(lines.contains { $0.hasPrefix("Switch check: saved file ") })
        #expect(lines.contains("Switch check: saved file identity matches registry."))
        #expect(lines.contains("Switch check: saved access token is fresh enough; no OpenAI refresh needed before switch."))
        #expect(lines.contains { $0.hasPrefix("Switch check: asking OpenAI to validate refresh token ") } == false)
        #expect(lines.joined(separator: "\n").contains("refresh-aisy") == false)
    }

    @Test func reusedRefreshTokenWithoutNewerActiveAuthLogsLikelyStaleOrOtherProcess() async throws {
        let fixture = try AuthSwitchPreflightFixture()
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
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now)
        )
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy": .failure(.reloginRequired(.reused))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )
        let logs = SwitchDebugLogCollector()

        do {
            _ = try await validator.prepareForSwitch(query: "aisy") { event in
                await logs.append(event)
            }
            Issue.record("Expected reused refresh token to block the switch.")
        } catch let error as AuthSwitchPreflightError {
            #expect(error == .reloginRequired(email: "aisy@example.com", reason: .reused))
        }

        let lines = await logs.lines()
        #expect(lines.contains("Switch check: OpenAI says this refresh token was already used."))
        #expect(lines.contains("Switch check: no newer matching active auth was found. Another Codex or codex-auth process may have refreshed this token first, or the saved account file may be stale."))
        #expect(lines.joined(separator: "\n").contains("refresh-aisy") == false)
    }

    @Test func newerActiveAuthLogsStaleSavedCopyAndRepairRefresh() async throws {
        let fixture = try AuthSwitchPreflightFixture()
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
            refreshToken: "refresh-stale",
            lastRefresh: "2026-05-17T05:00:00Z"
        )
        try fixture.writeActiveAuth(
            email: "aisy@example.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-active",
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now),
            lastRefresh: "2026-05-17T06:30:00Z"
        )
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-active": .success(AuthSwitchPreflightFixture.refreshResponse(
                    email: "aisy@example.com",
                    userID: "user_aisy",
                    accountID: "acct_aisy",
                    accessToken: "access-repaired",
                    refreshToken: "refresh-repaired"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )
        let logs = SwitchDebugLogCollector()

        _ = try await validator.prepareForSwitch(query: "aisy") { event in
            await logs.append(event)
        }

        let lines = await logs.lines()
        #expect(lines.contains("Switch check: active auth ~/.codex/auth.json is newer than saved copy."))
        #expect(lines.contains("Switch check: saved account file was stale; copied newer active auth into saved account file."))
        #expect(await refresher.requests == ["refresh-active"])
        let storedAuth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(storedAuth.tokens.refreshToken == "refresh-repaired")
    }

    @Test func reusedRefreshTokenWithNewerActiveAuthLogsRepairAttempt() async throws {
        let fixture = try AuthSwitchPreflightFixture()
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
            refreshToken: "refresh-stale",
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now),
            lastRefresh: "2026-05-17T05:00:00Z"
        )
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-stale": .failure(.reloginRequired(.reused)),
                "refresh-active": .success(AuthSwitchPreflightFixture.refreshResponse(
                    email: "aisy@example.com",
                    userID: "user_aisy",
                    accountID: "acct_aisy",
                    accessToken: "access-repaired",
                    refreshToken: "refresh-repaired"
                ))
            ],
            beforeResponse: { refreshToken in
                guard refreshToken == "refresh-stale" else {
                    return
                }
                try? fixture.writeActiveAuth(
                    email: "aisy@example.com",
                    userID: "user_aisy",
                    accountID: "acct_aisy",
                    refreshToken: "refresh-active",
                    accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now),
                    lastRefresh: "2026-05-17T06:30:00Z"
                )
            }
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )
        let logs = SwitchDebugLogCollector()

        let result = try await validator.prepareForSwitch(query: "aisy") { event in
            await logs.append(event)
        }

        #expect(result.status == .refreshed)
        #expect(await refresher.requests == ["refresh-stale", "refresh-active"])
        let lines = await logs.lines()
        #expect(lines.contains("Switch check: OpenAI says this refresh token was already used."))
        #expect(lines.contains("Switch check: found newer matching active auth; trying it as repair."))
        #expect(lines.contains("Switch check: saved new token into saved account file."))
        #expect(lines.joined(separator: "\n").contains("refresh-stale") == false)
        #expect(lines.joined(separator: "\n").contains("refresh-active") == false)
        #expect(lines.joined(separator: "\n").contains("refresh-repaired") == false)
    }

    @Test func staleSavedCopySaveFailureLogsAndBlocksSwitch() async throws {
        let fixture = try AuthSwitchPreflightFixture()
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
            refreshToken: "refresh-stale",
            lastRefresh: "2026-05-17T05:00:00Z"
        )
        try fixture.writeActiveAuth(
            email: "aisy@example.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-active",
            lastRefresh: "2026-05-17T06:30:00Z"
        )
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-active": .success(AuthSwitchPreflightFixture.refreshResponse(
                    email: "aisy@example.com",
                    userID: "user_aisy",
                    accountID: "acct_aisy",
                    accessToken: "access-repaired",
                    refreshToken: "refresh-repaired"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            writeAuthFile: { _, url in
                throw TestAuthFileWriteError(path: url.path)
            },
            now: { now }
        )
        let logs = SwitchDebugLogCollector()

        do {
            _ = try await validator.prepareForSwitch(query: "aisy") { event in
                await logs.append(event)
            }
            Issue.record("Expected stale saved-copy write failure to block the switch.")
        } catch let error as AuthSwitchPreflightError {
            guard case .transient(email: "aisy@example.com", _) = error else {
                Issue.record("Wrong error: \(error)")
                return
            }
        }

        #expect(await refresher.requests.isEmpty)
        let lines = await logs.lines()
        #expect(lines.contains("Switch check: active auth ~/.codex/auth.json is newer than saved copy."))
        #expect(lines.contains { $0.hasPrefix("Switch check: failed to copy newer active auth into ") })
        #expect(lines.contains("Switch check: saved account file is still stale. Switch cannot continue safely."))
        #expect(lines.joined(separator: "\n").contains("refresh-active") == false)
    }

    @Test func storedAuthIdentityMismatchLogsWrongFileAndBlocksSwitch() async throws {
        let fixture = try AuthSwitchPreflightFixture()
        try fixture.writeRegistry(
            activeAccountKey: nil,
            accounts: [
                .init(accountKey: "user_aisy::acct_aisy", email: "aisy@example.com", alias: "aisy", plan: "plus")
            ]
        )
        try fixture.writeStoredAuth(
            accountKey: "user_aisy::acct_aisy",
            email: "damar@example.com",
            userID: "user_damar",
            accountID: "acct_damar",
            refreshToken: "refresh-wrong-file"
        )
        let refresher = PreflightFakeOAuthTokenRefresher(responses: [:])
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )
        let logs = SwitchDebugLogCollector()

        do {
            _ = try await validator.prepareForSwitch(query: "aisy") { event in
                await logs.append(event)
            }
            Issue.record("Expected mismatched saved auth file to block the switch.")
        } catch let error as AuthSwitchPreflightError {
            #expect(error == .storedAuthIdentityMismatch(email: "aisy@example.com"))
        }

        #expect(await refresher.requests.isEmpty)
        let lines = await logs.lines()
        #expect(lines.contains("Switch check: saved file identity does not match registry."))
        #expect(lines.contains("Switch check: Switch may be reading the wrong saved account file."))
        #expect(lines.joined(separator: "\n").contains("refresh-wrong-file") == false)
    }

    @Test func storedAuthIdentityMismatchWithMatchingActiveAuthStillBlocksSwitch() async throws {
        let fixture = try AuthSwitchPreflightFixture()
        try fixture.writeRegistry(
            activeAccountKey: nil,
            accounts: [
                .init(accountKey: "user_aisy::acct_aisy", email: "aisy@example.com", alias: "aisy", plan: "plus")
            ]
        )
        try fixture.writeStoredAuth(
            accountKey: "user_aisy::acct_aisy",
            email: "damar@example.com",
            userID: "user_damar",
            accountID: "acct_damar",
            refreshToken: "refresh-wrong-file"
        )
        try fixture.writeActiveAuth(
            email: "aisy@example.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-active",
            lastRefresh: "2026-05-17T06:30:00Z"
        )
        let refresher = PreflightFakeOAuthTokenRefresher(responses: [:])
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            now: { now }
        )
        let logs = SwitchDebugLogCollector()

        do {
            _ = try await validator.prepareForSwitch(query: "aisy") { event in
                await logs.append(event)
            }
            Issue.record("Expected mismatched saved auth file to block the switch.")
        } catch let error as AuthSwitchPreflightError {
            #expect(error == .storedAuthIdentityMismatch(email: "aisy@example.com"))
        }

        #expect(await refresher.requests.isEmpty)
        let lines = await logs.lines()
        #expect(lines.contains("Switch check: saved file identity does not match registry."))
        #expect(lines.contains("Switch check: Switch may be reading the wrong saved account file."))
        #expect(lines.contains("Switch check: active auth ~/.codex/auth.json is newer than saved copy.") == false)
    }

    @Test func saveFailureAfterSuccessfulRefreshLogsLocalFileProblem() async throws {
        let fixture = try AuthSwitchPreflightFixture()
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
            accessToken: AuthSwitchPreflightFixture.accessJWT(expiration: now)
        )
        let refresher = PreflightFakeOAuthTokenRefresher(
            responses: [
                "refresh-aisy": .success(AuthSwitchPreflightFixture.refreshResponse(
                    email: "aisy@example.com",
                    userID: "user_aisy",
                    accountID: "acct_aisy",
                    accessToken: "access-aisy-new",
                    refreshToken: "refresh-aisy-new"
                ))
            ]
        )
        let validator = AuthSwitchPreflightValidator(
            homeDirectory: fixture.homeDirectory,
            refresher: refresher,
            writeAuthFile: { _, url in
                throw TestAuthFileWriteError(path: url.path)
            },
            now: { now }
        )
        let logs = SwitchDebugLogCollector()

        do {
            _ = try await validator.prepareForSwitch(query: "aisy") { event in
                await logs.append(event)
            }
            Issue.record("Expected local save failure to block the switch.")
        } catch let error as AuthSwitchPreflightError {
            guard case .transient(email: "aisy@example.com", _) = error else {
                Issue.record("Wrong error: \(error)")
                return
            }
        }

        let lines = await logs.lines()
        #expect(lines.contains { $0.hasPrefix("Switch check: failed to save the new refresh token into ") })
        #expect(lines.contains("Switch check: OpenAI already returned a rotated token, so the old local refresh token may now be already used. Click Login if the next check says already used."))
        #expect(lines.joined(separator: "\n").contains("refresh-aisy-new") == false)
    }
}

private struct AuthSwitchPreflightFixture: Sendable {
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
        refreshToken: String,
        accessToken: String = AuthSwitchPreflightFixture.freshAccessJWT,
        lastRefresh: String = "2026-05-11T00:00:00Z"
    ) throws {
        let directory = homeDirectory.appendingPathComponent(".codex/accounts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try authJSON(
            email: email,
            userID: userID,
            accountID: accountID,
            refreshToken: refreshToken,
            accessToken: accessToken,
            lastRefresh: lastRefresh
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

    func writeAPIKeyAuth(accountKey: String) throws {
        let directory = homeDirectory.appendingPathComponent(".codex/accounts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #"{"OPENAI_API_KEY":"sk-test"}"#
            .write(to: directory.appendingPathComponent("\(Self.encodedAccountKey(accountKey)).auth.json"), atomically: true, encoding: .utf8)
    }

    func writeActiveAuth(
        email: String,
        userID: String,
        accountID: String,
        refreshToken: String,
        accessToken: String = AuthSwitchPreflightFixture.freshAccessJWT,
        lastRefresh: String = "2026-05-11T00:00:00Z"
    ) throws {
        let directory = homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try authJSON(
            email: email,
            userID: userID,
            accountID: accountID,
            refreshToken: refreshToken,
            accessToken: accessToken,
            lastRefresh: lastRefresh
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

    static func accessJWT(expiration: Date) -> String {
        "\(base64URL(["alg": "none"])).\(base64URL(["exp": expiration.timeIntervalSince1970])).signature"
    }

    static func refreshResponse(
        email: String,
        userID: String,
        accountID: String,
        accessToken: String,
        refreshToken: String
    ) -> OAuthRefreshResponse {
        OAuthRefreshResponse(
            idToken: jwt(email: email, userID: userID, accountID: accountID),
            accessToken: accessToken,
            refreshToken: refreshToken
        )
    }

    static let freshAccessJWT = accessJWT(expiration: Date(timeIntervalSince1970: 2_000_000_000))

    private func authJSON(
        email: String,
        userID: String,
        accountID: String,
        refreshToken: String,
        accessToken: String,
        lastRefresh: String
    ) -> String {
        """
        {
          "tokens": {
            "id_token": "\(Self.jwt(email: email, userID: userID, accountID: accountID))",
            "access_token": "\(accessToken)",
            "refresh_token": "\(refreshToken)",
            "account_id": "\(accountID)"
          },
          "last_refresh": "\(lastRefresh)"
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

private actor PreflightFakeOAuthTokenRefresher: OAuthTokenRefreshing {
    private let responses: [String: Result<OAuthRefreshResponse, OAuthRefreshFailure>]
    private let beforeResponse: @Sendable (String) async -> Void
    private(set) var requests: [String] = []

    init(
        responses: [String: Result<OAuthRefreshResponse, OAuthRefreshFailure>],
        beforeResponse: @escaping @Sendable (String) async -> Void = { _ in }
    ) {
        self.responses = responses
        self.beforeResponse = beforeResponse
    }

    func refresh(refreshToken: String) async throws -> OAuthRefreshResponse {
        requests.append(refreshToken)
        await beforeResponse(refreshToken)
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

private actor SwitchDebugLogCollector {
    private var collectedLines: [String] = []

    func append(_ event: AuthAccountRefreshDebugEvent) {
        collectedLines.append(event.transcriptLine)
    }

    func lines() -> [String] {
        collectedLines
    }
}

private struct TestAuthFileWriteError: LocalizedError {
    var path: String

    var errorDescription: String? {
        "test writer could not save \(path)"
    }
}
