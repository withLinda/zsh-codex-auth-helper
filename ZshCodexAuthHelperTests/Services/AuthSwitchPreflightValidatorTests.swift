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
        #expect(await refresher.requests.isEmpty)
    }

    @Test func unreadableAccessTokenUsesEightDayFallbackExactly() async throws {
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

    @Test func rowNumberUsesCodexAuthDisplayOrderWithoutRefreshing() async throws {
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
        let validator = AuthSwitchPreflightValidator(homeDirectory: fixture.homeDirectory)

        let account = try await validator.prepareForSwitch(query: "01")

        #expect(account.account.email == "aisy.ahkusmawati938@gmail.com")
        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy")
        #expect(auth.tokens.accessToken == AuthSwitchPreflightFixture.freshAccessJWT)
        #expect(auth.lastRefresh == "2026-05-11T00:00:00Z")
    }

    @Test func activeAccountPreflightDoesNotRotateActiveAuthFile() async throws {
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
        let validator = AuthSwitchPreflightValidator(homeDirectory: fixture.homeDirectory)

        _ = try await validator.prepareForSwitch(query: "damar")

        let activeAuth = try fixture.readActiveAuth()
        #expect(activeAuth.tokens.refreshToken == "refresh-damar")
        #expect(activeAuth.tokens.accessToken == AuthSwitchPreflightFixture.freshAccessJWT)
    }

    @Test func storedRefreshTimestampDoesNotTriggerPreflightRefresh() async throws {
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
            lastRefresh: "2026-05-17T06:20:00Z"
        )
        let validator = AuthSwitchPreflightValidator(homeDirectory: fixture.homeDirectory)

        let account = try await validator.prepareForSwitch(query: "aisy")

        #expect(account.account.email == "aisy.ahkusmawati938@gmail.com")
        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy")
    }

    @Test func fractionalStoredRefreshTimestampDoesNotTriggerPreflightRefresh() async throws {
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
            lastRefresh: "2026-05-17T06:20:00.123456Z"
        )
        let validator = AuthSwitchPreflightValidator(homeDirectory: fixture.homeDirectory)

        let account = try await validator.prepareForSwitch(query: "aisy")

        #expect(account.account.email == "aisy.ahkusmawati938@gmail.com")
    }

    @Test func newerMatchingActiveAuthIsCopiedToStoredAuthWithoutRefreshing() async throws {
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
            lastRefresh: "2026-05-17T06:25:00Z"
        )
        let validator = AuthSwitchPreflightValidator(homeDirectory: fixture.homeDirectory)

        _ = try await validator.prepareForSwitch(query: "aisy")

        let storedAuth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(storedAuth.tokens.refreshToken == "refresh-aisy-active")
    }

    @Test func newerMatchingActiveAuthIsCopiedToStoredAuthWithoutRefreshingOutsideRecentWindow() async throws {
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
            lastRefresh: "2026-05-17T06:00:00Z"
        )
        let validator = AuthSwitchPreflightValidator(homeDirectory: fixture.homeDirectory)

        _ = try await validator.prepareForSwitch(query: "aisy")

        let storedAuth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(storedAuth.tokens.refreshToken == "refresh-aisy-active")
        #expect(storedAuth.tokens.accessToken == AuthSwitchPreflightFixture.freshAccessJWT)
        let activeAuth = try fixture.readActiveAuth()
        #expect(activeAuth.tokens.refreshToken == "refresh-aisy-active")
        #expect(activeAuth.tokens.accessToken == AuthSwitchPreflightFixture.freshAccessJWT)
    }

    @Test func olderActiveAuthIsIgnoredWithoutRefreshing() async throws {
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
            email: "aisy.ahkusmawati938@gmail.com",
            userID: "user_aisy",
            accountID: "acct_aisy",
            refreshToken: "refresh-aisy-active",
            lastRefresh: "2026-05-17T05:00:00Z"
        )
        let validator = AuthSwitchPreflightValidator(homeDirectory: fixture.homeDirectory)

        _ = try await validator.prepareForSwitch(query: "aisy")

        let storedAuth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(storedAuth.tokens.refreshToken == "refresh-aisy-stored")
    }

    @Test func differentAccountActiveAuthIsIgnoredWithoutRefreshing() async throws {
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
        let validator = AuthSwitchPreflightValidator(homeDirectory: fixture.homeDirectory)

        _ = try await validator.prepareForSwitch(query: "aisy")

        let storedAuth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(storedAuth.tokens.refreshToken == "refresh-aisy-stored")
    }

    @Test func storedRefreshTokenIsNotSpentDuringSwitchPreflight() async throws {
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
        let validator = AuthSwitchPreflightValidator(homeDirectory: fixture.homeDirectory)

        let account = try await validator.prepareForSwitch(query: "aisy")

        #expect(account.account.email == "aisy.ahkusmawati938@gmail.com")
        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy")
    }

    @Test func matchingActiveAuthIsCopiedToStoredAuthWithoutRepairRefresh() async throws {
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
            lastRefresh: "2026-05-17T06:25:00Z"
        )
        let validator = AuthSwitchPreflightValidator(homeDirectory: fixture.homeDirectory)

        let account = try await validator.prepareForSwitch(query: "aisy")

        #expect(account.account.email == "aisy.ahkusmawati938@gmail.com")
        let storedAuth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(storedAuth.tokens.refreshToken == "refresh-aisy-active")
        #expect(storedAuth.tokens.accessToken == AuthSwitchPreflightFixture.freshAccessJWT)
        let activeAuth = try fixture.readActiveAuth()
        #expect(activeAuth.tokens.refreshToken == "refresh-aisy-active")
        #expect(activeAuth.tokens.accessToken == AuthSwitchPreflightFixture.freshAccessJWT)
    }

    @Test func differentActiveAuthDoesNotTriggerRefreshOrRepair() async throws {
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
        let validator = AuthSwitchPreflightValidator(homeDirectory: fixture.homeDirectory)

        let account = try await validator.prepareForSwitch(query: "aisy")

        #expect(account.account.email == "aisy.ahkusmawati938@gmail.com")
        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy-stale")
    }

    @Test func sameActiveRefreshTokenDoesNotTriggerRefresh() async throws {
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
        let validator = AuthSwitchPreflightValidator(homeDirectory: fixture.homeDirectory)

        let account = try await validator.prepareForSwitch(query: "aisy")

        #expect(account.account.email == "aisy.ahkusmawati938@gmail.com")
        let auth = try fixture.readStoredAuth(accountKey: "user_aisy::acct_aisy")
        #expect(auth.tokens.refreshToken == "refresh-aisy-stale")
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
            refreshToken: "refresh-sultan"
        )
        let validator = AuthSwitchPreflightValidator(homeDirectory: fixture.homeDirectory)

        let account = try await validator.prepareForSwitch(query: "1819")

        #expect(account.account.email == "sultan1819@example.com")
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
