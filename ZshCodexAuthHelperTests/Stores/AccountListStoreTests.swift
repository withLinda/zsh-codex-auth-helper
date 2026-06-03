import Foundation
import Testing
@testable import ZshCodexAuthHelper

@MainActor
struct AccountListStoreTests {
    @Test func loadsSortedRegistryAndMarksActiveAccount() throws {
        let fixture = try AccountListFixture()
        try fixture.writeRegistry(
            activeAccountKey: "user_b::acct_b",
            accounts: [
                .init(accountKey: "user_b::acct_b", email: "beta@example.com", alias: "beta", plan: "plus"),
                .init(accountKey: "user_a::acct_a", email: "alpha@example.com", alias: "alpha", plan: "pro")
            ]
        )
        let store = AccountListStore(
            accountStore: AuthAccountStore(homeDirectory: fixture.homeDirectory, fileManager: .default)
        )

        store.refresh()

        guard case .loaded(let items) = store.state else {
            Issue.record("Expected loaded state, got \(store.state).")
            return
        }
        #expect(items.map(\.email) == ["alpha@example.com", "beta@example.com"])
        #expect(items.map(\.rowNumber) == [1, 2])
        #expect(items.map(\.isActive) == [false, true])
        #expect(items[0].planLabel == "Pro")
        #expect(items[1].planLabel == "Plus")
    }

    @Test func reportsMissingUnreadableAndEmptyRegistryStates() throws {
        let missingFixture = try AccountListFixture()
        let missingStore = AccountListStore(
            accountStore: AuthAccountStore(homeDirectory: missingFixture.homeDirectory, fileManager: .default)
        )

        missingStore.refresh()

        #expect(missingStore.state == .missingRegistry)

        let unreadableFixture = try AccountListFixture()
        try unreadableFixture.writeRawRegistry("{not json")
        let unreadableStore = AccountListStore(
            accountStore: AuthAccountStore(homeDirectory: unreadableFixture.homeDirectory, fileManager: .default)
        )

        unreadableStore.refresh()

        #expect(unreadableStore.state == .unreadableRegistry)

        let emptyFixture = try AccountListFixture()
        try emptyFixture.writeRegistry(activeAccountKey: nil, accounts: [])
        let emptyStore = AccountListStore(
            accountStore: AuthAccountStore(homeDirectory: emptyFixture.homeDirectory, fileManager: .default)
        )

        emptyStore.refresh()

        #expect(emptyStore.state == .empty)
    }

    @Test func safeSelectorChoosesUniqueAliasEmailAccountNameThenRowNumber() throws {
        let fixture = try AccountListFixture()
        try fixture.writeRegistry(
            activeAccountKey: nil,
            accounts: [
                .init(accountKey: "user_alias::acct_alias", email: "alias@example.com", alias: "personal", accountName: "Personal", plan: "plus"),
                .init(accountKey: "user_dup_a::acct_dup_a", email: "duplicate-a@example.com", alias: "shared", accountName: "Unique A", plan: "plus"),
                .init(accountKey: "user_dup_b::acct_dup_b", email: "duplicate-b@example.com", alias: "shared", accountName: "Unique B", plan: "plus"),
                .init(accountKey: "user_name::acct_name", email: "named@example.com", alias: "", accountName: "Named", plan: "plus"),
                .init(accountKey: "user_same_a::acct_same_a", email: "same@example.com", alias: "", accountName: "Same", plan: "plus"),
                .init(accountKey: "user_same_b::acct_same_b", email: "same@example.com", alias: "", accountName: "Same", plan: "plus")
            ]
        )
        let store = AccountListStore(
            accountStore: AuthAccountStore(homeDirectory: fixture.homeDirectory, fileManager: .default)
        )

        store.refresh()

        guard case .loaded(let items) = store.state else {
            Issue.record("Expected loaded state, got \(store.state).")
            return
        }

        let selectors = Dictionary(uniqueKeysWithValues: items.map { ($0.accountKey, $0.safeSelector) })
        #expect(selectors["user_alias::acct_alias"] == "personal")
        #expect(selectors["user_dup_a::acct_dup_a"] == "duplicate-a@example.com")
        #expect(selectors["user_dup_b::acct_dup_b"] == "duplicate-b@example.com")
        #expect(selectors["user_name::acct_name"] == "named@example.com")
        #expect(selectors["user_same_a::acct_same_a"] == "5")
        #expect(selectors["user_same_b::acct_same_b"] == "6")
    }

    @Test func accountSearchMatchesVisibleAccountFields() throws {
        let item = AccountListItem(
            accountKey: "user_aisy::acct_aisy",
            email: "aisy@example.com",
            alias: "daily",
            accountName: "Personal Login",
            plan: "chatgpt-plus",
            authMode: "oauth",
            isActive: false,
            rowNumber: 7,
            safeSelector: "daily",
            lastUsageAt: nil
        )

        #expect(item.matchesSearchQuery(""))
        #expect(item.matchesSearchQuery("   "))
        #expect(item.matchesSearchQuery("aisy@"))
        #expect(item.matchesSearchQuery("DAILY"))
        #expect(item.matchesSearchQuery("personal"))
        #expect(item.matchesSearchQuery("plus"))
        #expect(item.matchesSearchQuery("oauth"))
        #expect(item.matchesSearchQuery("missing") == false)
    }

    @Test func accountSearchIgnoresCaseWhitespaceAndDiacritics() throws {
        let item = AccountListItem(
            accountKey: "user_renee::acct_renee",
            email: "renee@example.com",
            alias: "Renée Work",
            accountName: "Café Team",
            plan: "pro",
            authMode: nil,
            isActive: false,
            rowNumber: 3,
            safeSelector: "renee@example.com",
            lastUsageAt: nil
        )

        #expect(item.matchesSearchQuery("  RENEE  "))
        #expect(item.matchesSearchQuery("cafe"))
        #expect(item.matchesSearchQuery("PRO"))
    }
}

private struct AccountListFixture {
    let homeDirectory: URL

    init() throws {
        homeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zsh-codex-auth-helper-account-list-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
    }

    func writeRegistry(activeAccountKey: String?, accounts: [TestRegistryAccount]) throws {
        var payload: [String: Any] = [
            "schema_version": 4,
            "accounts": accounts.map(\.json)
        ]
        if let activeAccountKey {
            payload["active_account_key"] = activeAccountKey
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try writeRegistryData(data)
    }

    func writeRawRegistry(_ raw: String) throws {
        try writeRegistryData(Data(raw.utf8))
    }

    private func writeRegistryData(_ data: Data) throws {
        let directory = homeDirectory.appendingPathComponent(".codex/accounts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("registry.json"), options: .atomic)
    }
}

private struct TestRegistryAccount {
    var accountKey: String
    var email: String
    var alias: String
    var accountName: String?
    var plan: String
    var authMode: String?

    init(
        accountKey: String,
        email: String,
        alias: String,
        accountName: String? = nil,
        plan: String,
        authMode: String? = nil
    ) {
        self.accountKey = accountKey
        self.email = email
        self.alias = alias
        self.accountName = accountName
        self.plan = plan
        self.authMode = authMode
    }

    var json: [String: Any] {
        var value: [String: Any] = [
            "account_key": accountKey,
            "chatgpt_account_id": accountKey.components(separatedBy: "::").last ?? accountKey,
            "chatgpt_user_id": accountKey.components(separatedBy: "::").first ?? accountKey,
            "email": email,
            "alias": alias,
            "plan": plan
        ]
        if let accountName {
            value["account_name"] = accountName
        }
        if let authMode {
            value["auth_mode"] = authMode
        }
        return value
    }
}
