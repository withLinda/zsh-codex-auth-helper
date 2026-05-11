import Foundation

@MainActor
final class AuthSessionMonitor: ObservableObject {
    @Published private(set) var info: AuthSessionInfo = .missingFile

    private let read: (String) -> AuthSessionInfo
    private let fingerprint: (String) -> AuthSessionFingerprint
    private var authFilePath: String?
    private var lastFingerprint: AuthSessionFingerprint?
    private var pollTask: Task<Void, Never>?

    convenience init(reader: AuthSessionReader = AuthSessionReader()) {
        self.init(
            read: { reader.read(authFilePath: $0) },
            fingerprint: { reader.fingerprint(authFilePath: $0) }
        )
    }

    init(
        read: @escaping (String) -> AuthSessionInfo,
        fingerprint: @escaping (String) -> AuthSessionFingerprint
    ) {
        self.read = read
        self.fingerprint = fingerprint
    }

    deinit {
        pollTask?.cancel()
    }

    func start(authFilePath: String) {
        self.authFilePath = authFilePath
        refreshCurrent()
        startPollingIfNeeded()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func updateAuthFilePath(_ authFilePath: String) {
        guard self.authFilePath != authFilePath else {
            return
        }

        self.authFilePath = authFilePath
        refreshCurrent()
        startPollingIfNeeded()
    }

    func refreshCurrent() {
        guard let authFilePath else {
            return
        }

        lastFingerprint = fingerprint(authFilePath)
        info = read(authFilePath)
    }

    func checkForChanges() {
        guard let authFilePath else {
            return
        }

        let currentFingerprint = fingerprint(authFilePath)
        guard currentFingerprint != lastFingerprint else {
            return
        }

        lastFingerprint = currentFingerprint
        info = read(authFilePath)
    }

    private func startPollingIfNeeded() {
        guard pollTask == nil else {
            return
        }

        pollTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    self?.checkForChanges()
                }
            }
        }
    }
}
