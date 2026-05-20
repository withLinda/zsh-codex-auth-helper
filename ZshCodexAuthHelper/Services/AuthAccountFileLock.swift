import Darwin
import Foundation

final class AuthAccountFileLock {
    private let homeDirectory: URL
    private let fileManager: FileManager

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    func tryLock(accountKey: String) throws -> AuthAccountHeldLock? {
        let accountsDirectory = homeDirectory.appendingPathComponent(".codex/accounts", isDirectory: true)
        try fileManager.createDirectory(at: accountsDirectory, withIntermediateDirectories: true)

        let lockURL = accountsDirectory.appendingPathComponent("\(AuthAccountStore.accountFileKey(accountKey)).lock")
        let fileDescriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        let lockResult = flock(fileDescriptor, LOCK_EX | LOCK_NB)
        guard lockResult == 0 else {
            let lockErrno = errno
            close(fileDescriptor)
            if lockErrno == EWOULDBLOCK || lockErrno == EAGAIN {
                return nil
            }
            throw POSIXError(POSIXErrorCode(rawValue: lockErrno) ?? .EIO)
        }

        return AuthAccountHeldLock(fileDescriptor: fileDescriptor)
    }
}

final class AuthAccountHeldLock {
    private let lock = NSLock()
    private var fileDescriptor: Int32?

    init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        release()
    }

    func release() {
        lock.lock()
        let descriptor = fileDescriptor
        fileDescriptor = nil
        lock.unlock()

        guard let descriptor else {
            return
        }

        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
