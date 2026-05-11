import Foundation
import Testing
@testable import ZshCodexAuthHelper

struct AuthSessionReaderTests {
    @Test func jwtAuthExtractsEmailPlanAndRecordIdentity() throws {
        let fixture = try AuthSessionFixture()
        let authPath = try fixture.writeActiveAuth(
            email: "LINDA@EXAMPLE.COM",
            userID: "user_123",
            accountID: "acct_456",
            plan: "pro"
        )
        let reader = AuthSessionReader(homeDirectory: fixture.homeDirectory)

        let info = reader.read(authFilePath: authPath.path)

        #expect(info.status == .activeAuth)
        #expect(info.email == "linda@example.com")
        #expect(info.plan == .pro)
        #expect(info.accountKey == "user_123::acct_456")
    }

    @Test func malformedJWTDoesNotCrashAndShowsNoSignedInAccount() throws {
        let fixture = try AuthSessionFixture()
        let authPath = try fixture.writeActiveAuth(idToken: "not-a-jwt", accountID: "acct_456")
        let reader = AuthSessionReader(homeDirectory: fixture.homeDirectory)

        let info = reader.read(authFilePath: authPath.path)

        #expect(info.status == .noSignedInAccount)
        #expect(info.email == nil)
    }

    @Test func activeRegistryRecordAddsAliasAccountNameAndPlan() throws {
        let fixture = try AuthSessionFixture()
        let authPath = try fixture.writeActiveAuth(
            email: "linda@example.com",
            userID: "user_123",
            accountID: "acct_456",
            plan: nil
        )
        try fixture.writeRegistry(
            activeAccountKey: "user_123::acct_456",
            accounts: [
                .init(
                    accountKey: "user_123::acct_456",
                    email: "linda@example.com",
                    alias: "work",
                    accountName: "Design Team",
                    plan: "team"
                )
            ]
        )
        let reader = AuthSessionReader(homeDirectory: fixture.homeDirectory)

        let info = reader.read(authFilePath: authPath.path)

        #expect(info.status == .activeAuth)
        #expect(info.alias == "work")
        #expect(info.accountName == "Design Team")
        #expect(info.plan == .business)
    }

    @Test func selectedAuthFileThatIsNotActiveStillShowsSelectedEmail() throws {
        let fixture = try AuthSessionFixture()
        _ = try fixture.writeActiveAuth(
            email: "active@example.com",
            userID: "user_active",
            accountID: "acct_active",
            plan: "plus"
        )
        let selectedPath = try fixture.writeSelectedAuth(
            email: "selected@example.com",
            userID: "user_selected",
            accountID: "acct_selected",
            plan: "pro"
        )
        try fixture.writeRegistry(
            activeAccountKey: "user_active::acct_active",
            accounts: [
                .init(
                    accountKey: "user_active::acct_active",
                    email: "active@example.com",
                    alias: "main",
                    accountName: nil,
                    plan: "plus"
                )
            ]
        )
        let reader = AuthSessionReader(homeDirectory: fixture.homeDirectory)

        let info = reader.read(authFilePath: selectedPath.path)

        #expect(info.status == .selectedFile)
        #expect(info.email == "selected@example.com")
        #expect(info.alias == nil)
        #expect(info.plan == .pro)
    }

    @Test func missingAuthFileShowsMissingFileState() throws {
        let fixture = try AuthSessionFixture()
        let reader = AuthSessionReader(homeDirectory: fixture.homeDirectory)

        let info = reader.read(authFilePath: fixture.homeDirectory.appendingPathComponent(".codex/missing.json").path)

        #expect(info.status == .missingFile)
        #expect(info.email == nil)
    }

    @Test func malformedAuthJSONShowsUnreadableAuthState() throws {
        let fixture = try AuthSessionFixture()
        let authPath = fixture.homeDirectory.appendingPathComponent(".codex/auth.json")
        try fixture.createCodexDirectory()
        try "{".write(to: authPath, atomically: true, encoding: .utf8)
        let reader = AuthSessionReader(homeDirectory: fixture.homeDirectory)

        let info = reader.read(authFilePath: authPath.path)

        #expect(info.status == .unreadableAuth)
        #expect(info.email == nil)
    }

    @Test func apiKeyAuthWithoutRegistryMetadataShowsNoSignedInAccount() throws {
        let fixture = try AuthSessionFixture()
        let authPath = fixture.homeDirectory.appendingPathComponent(".codex/auth.json")
        try fixture.createCodexDirectory()
        try #"{"OPENAI_API_KEY":"sk-test"}"#.write(to: authPath, atomically: true, encoding: .utf8)
        let reader = AuthSessionReader(homeDirectory: fixture.homeDirectory)

        let info = reader.read(authFilePath: authPath.path)

        #expect(info.status == .noSignedInAccount)
        #expect(info.email == nil)
    }
}

private struct AuthSessionFixture {
    let homeDirectory: URL

    init() throws {
        homeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zsh-codex-auth-helper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
    }

    func createCodexDirectory() throws {
        try FileManager.default.createDirectory(
            at: homeDirectory.appendingPathComponent(".codex"),
            withIntermediateDirectories: true
        )
    }

    func writeActiveAuth(
        email: String,
        userID: String,
        accountID: String,
        plan: String?
    ) throws -> URL {
        try writeActiveAuth(idToken: Self.jwt(email: email, userID: userID, accountID: accountID, plan: plan), accountID: accountID)
    }

    func writeActiveAuth(idToken: String, accountID: String) throws -> URL {
        try createCodexDirectory()
        let path = homeDirectory.appendingPathComponent(".codex/auth.json")
        try Self.authJSON(idToken: idToken, accountID: accountID).write(to: path, atomically: true, encoding: .utf8)
        return path
    }

    func writeSelectedAuth(
        email: String,
        userID: String,
        accountID: String,
        plan: String?
    ) throws -> URL {
        let directory = homeDirectory.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("auth.json")
        let token = Self.jwt(email: email, userID: userID, accountID: accountID, plan: plan)
        try Self.authJSON(idToken: token, accountID: accountID).write(to: path, atomically: true, encoding: .utf8)
        return path
    }

    func writeRegistry(activeAccountKey: String, accounts: [RegistryAccount]) throws {
        let directory = homeDirectory.appendingPathComponent(".codex/accounts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload: [String: Any] = [
            "schema_version": 4,
            "active_account_key": activeAccountKey,
            "accounts": accounts.map(\.json)
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try data.write(to: directory.appendingPathComponent("registry.json"), options: .atomic)
    }

    struct RegistryAccount {
        var accountKey: String
        var email: String
        var alias: String
        var accountName: String?
        var plan: String?

        var json: [String: Any] {
            var value: [String: Any] = [
                "account_key": accountKey,
                "chatgpt_account_id": accountKey.components(separatedBy: "::").last ?? "",
                "chatgpt_user_id": accountKey.components(separatedBy: "::").first ?? "",
                "email": email,
                "alias": alias,
                "created_at": 1
            ]
            if let accountName {
                value["account_name"] = accountName
            }
            if let plan {
                value["plan"] = plan
            }
            return value
        }
    }

    private static func authJSON(idToken: String, accountID: String) -> String {
        """
        {
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "secret-access-token",
            "refresh_token": "secret-refresh-token",
            "account_id": "\(accountID)"
          },
          "last_refresh": "2026-05-12T00:00:00Z"
        }
        """
    }

    private static func jwt(email: String, userID: String, accountID: String, plan: String?) -> String {
        var authClaims: [String: Any] = [
            "chatgpt_account_id": accountID,
            "chatgpt_user_id": userID
        ]
        if let plan {
            authClaims["chatgpt_plan_type"] = plan
        }
        let payload: [String: Any] = [
            "email": email,
            "https://api.openai.com/auth": authClaims
        ]
        return "\(base64URL(["alg": "none"])).\(base64URL(payload)).signature"
    }

    private static func base64URL(_ value: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
