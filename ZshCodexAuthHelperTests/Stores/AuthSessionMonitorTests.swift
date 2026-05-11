import Foundation
import Testing
@testable import ZshCodexAuthHelper

@MainActor
struct AuthSessionMonitorTests {
    @Test func startRefreshesImmediately() {
        var readPaths: [String] = []
        let expectedInfo = AuthSessionInfo(status: .activeAuth, email: "linda@example.com")
        let monitor = AuthSessionMonitor(
            read: { path in
                readPaths.append(path)
                return expectedInfo
            },
            fingerprint: { _ in .empty }
        )

        monitor.start(authFilePath: "/Users/linda/.codex/auth.json")

        #expect(readPaths == ["/Users/linda/.codex/auth.json"])
        #expect(monitor.info == expectedInfo)
        monitor.stop()
    }

    @Test func updatingAuthFilePathRefreshesWhenPathChanges() {
        var readPaths: [String] = []
        let monitor = AuthSessionMonitor(
            read: { path in
                readPaths.append(path)
                return AuthSessionInfo(status: .selectedFile, email: path)
            },
            fingerprint: { _ in .empty }
        )

        monitor.start(authFilePath: "/first/auth.json")
        monitor.updateAuthFilePath("/second/auth.json")

        #expect(readPaths == ["/first/auth.json", "/second/auth.json"])
        #expect(monitor.info.email == "/second/auth.json")
        monitor.stop()
    }

    @Test func checkForChangesRefreshesWhenFingerprintChanges() {
        var currentFingerprint = AuthSessionFingerprint(
            auth: .init(path: "/auth.json", exists: true, modificationDate: Date(timeIntervalSince1970: 1), size: 10),
            registry: .init(path: "/registry.json", exists: true, modificationDate: Date(timeIntervalSince1970: 1), size: 20)
        )
        var readCount = 0
        let monitor = AuthSessionMonitor(
            read: { _ in
                readCount += 1
                return AuthSessionInfo(status: .activeAuth, email: "read-\(readCount)@example.com")
            },
            fingerprint: { _ in currentFingerprint }
        )

        monitor.start(authFilePath: "/auth.json")
        currentFingerprint.auth = .init(
            path: "/auth.json",
            exists: true,
            modificationDate: Date(timeIntervalSince1970: 2),
            size: 10
        )
        monitor.checkForChanges()

        #expect(readCount == 2)
        #expect(monitor.info.email == "read-2@example.com")
        monitor.stop()
    }
}

private extension AuthSessionFingerprint {
    static let empty = AuthSessionFingerprint(
        auth: .init(path: "", exists: false, modificationDate: nil, size: nil),
        registry: .init(path: "", exists: false, modificationDate: nil, size: nil)
    )
}
