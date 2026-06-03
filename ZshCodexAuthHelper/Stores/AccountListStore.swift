import Foundation

enum AccountListState: Equatable {
    case loading
    case loaded([AccountListItem])
    case empty
    case missingRegistry
    case unreadableRegistry
}
@MainActor
final class AccountListStore: ObservableObject {
    @Published private(set) var state: AccountListState = .loading

    private let accountStore: AuthAccountStore
    private let pollIntervalNanoseconds: UInt64
    private var lastRegistryFingerprint: AuthSessionFileFingerprint?
    private var pollTask: Task<Void, Never>?

    init(
        accountStore: AuthAccountStore = AuthAccountStore(),
        pollIntervalNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.accountStore = accountStore
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
    }

    deinit {
        pollTask?.cancel()
    }

    func start() {
        refresh()
        startPollingIfNeeded()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() {
        lastRegistryFingerprint = registryFingerprint()

        do {
            let registry = try accountStore.readRegistry()
            let items = Self.items(from: registry)
            state = items.isEmpty ? .empty : .loaded(items)
        } catch AuthAccountStoreError.missingRegistry {
            state = .missingRegistry
        } catch {
            state = .unreadableRegistry
        }
    }

    func checkForChanges() {
        let currentFingerprint = registryFingerprint()
        guard currentFingerprint != lastRegistryFingerprint else {
            return
        }
        refresh()
    }

    static func items(from registry: AuthAccountRegistry) -> [AccountListItem] {
        let orderedAccounts = registry.displayOrderedAccounts()

        return orderedAccounts.enumerated().map { index, record in
            AccountListItem(
                accountKey: record.accountKey,
                email: record.email,
                alias: record.alias.trimmedNonEmpty,
                accountName: record.accountName?.trimmedNonEmpty,
                plan: record.plan?.trimmedNonEmpty,
                authMode: record.authMode?.trimmedNonEmpty,
                isActive: registry.activeAccountKey == record.accountKey,
                rowNumber: index + 1,
                safeSelector: safeSelector(for: record, rowNumber: index + 1, registry: registry),
                lastUsageAt: record.lastUsageAt?.trimmedNonEmpty
            )
        }
    }

    private static func safeSelector(
        for record: AuthAccountRecord,
        rowNumber: Int,
        registry: AuthAccountRegistry
    ) -> String {
        let candidates = [
            record.alias.trimmedNonEmpty,
            record.email.trimmedNonEmpty,
            record.accountName?.trimmedNonEmpty
        ].compactMap { $0 }

        if let uniqueCandidate = candidates.first(where: { matchingAccountCount(query: $0, registry: registry) == 1 }) {
            return uniqueCandidate
        }

        return "\(rowNumber)"
    }

    private static func matchingAccountCount(query: String, registry: AuthAccountRegistry) -> Int {
        registry.accounts.filter { record in
            record.email.localizedCaseInsensitiveContains(query) ||
                record.alias.localizedCaseInsensitiveContains(query) ||
                (record.accountName?.localizedCaseInsensitiveContains(query) ?? false)
        }.count
    }

    private func startPollingIfNeeded() {
        guard pollTask == nil else {
            return
        }

        pollTask = Task { [weak self] in
            while Task.isCancelled == false {
                guard let self else {
                    return
                }

                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                await MainActor.run {
                    self.checkForChanges()
                }
            }
        }
    }

    private func registryFingerprint() -> AuthSessionFileFingerprint {
        let url = accountStore.registryURL
        guard let attributes = try? accountStore.fileManager.attributesOfItem(atPath: url.path) else {
            return AuthSessionFileFingerprint(path: url.path, exists: false, modificationDate: nil, size: nil)
        }

        return AuthSessionFileFingerprint(
            path: url.path,
            exists: true,
            modificationDate: attributes[.modificationDate] as? Date,
            size: (attributes[.size] as? NSNumber)?.uint64Value
        )
    }
}
