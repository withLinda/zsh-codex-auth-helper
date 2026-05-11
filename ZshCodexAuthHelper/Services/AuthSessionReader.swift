import Foundation

struct AuthSessionReader {
    private let homeDirectory: URL
    private let fileManager: FileManager

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    func read(authFilePath: String) -> AuthSessionInfo {
        let trimmedPath = authFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.isEmpty == false else {
            return .missingFile
        }

        let authURL = normalizedURL(for: trimmedPath)
        guard fileManager.fileExists(atPath: authURL.path) else {
            return .missingFile
        }

        let registry = readRegistry()

        do {
            let data = try Data(contentsOf: authURL)
            let authFile = try JSONDecoder().decode(AuthFile.self, from: data)

            if let apiKey = authFile.openAIAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines),
               apiKey.isEmpty == false {
                return infoFromRegistryForAPIKeyAuth(registry: registry, authURL: authURL)
            }

            guard let tokenInfo = tokenInfo(from: authFile), let email = tokenInfo.email else {
                return .noSignedInAccount
            }

            let matchingRecord = tokenInfo.accountKey.flatMap { registry.record(accountKey: $0) }
            let status: AuthSessionStatus = isActiveAuthURL(authURL) ? .activeAuth : .selectedFile

            return AuthSessionInfo(
                status: status,
                email: email,
                plan: tokenInfo.plan ?? matchingRecord?.plan,
                alias: matchingRecord?.alias,
                accountName: matchingRecord?.accountName,
                accountKey: tokenInfo.accountKey
            )
        } catch is DecodingError {
            return .unreadableAuth
        } catch {
            return .unreadableAuth
        }
    }

    func fingerprint(authFilePath: String) -> AuthSessionFingerprint {
        let trimmedPath = authFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let authURL = trimmedPath.isEmpty ? nil : normalizedURL(for: trimmedPath)

        return AuthSessionFingerprint(
            auth: fileFingerprint(for: authURL),
            registry: fileFingerprint(for: registryURL)
        )
    }

    private var activeAuthURL: URL {
        homeDirectory.appendingPathComponent(".codex/auth.json").standardizedFileURL
    }

    private var registryURL: URL {
        homeDirectory.appendingPathComponent(".codex/accounts/registry.json").standardizedFileURL
    }

    private func normalizedURL(for path: String) -> URL {
        let expandedPath = NSString(string: path).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath).standardizedFileURL
    }

    private func isActiveAuthURL(_ url: URL) -> Bool {
        url.standardizedFileURL.path == activeAuthURL.path
    }

    private func readRegistry() -> AuthRegistry {
        guard fileManager.fileExists(atPath: registryURL.path),
              let data = try? Data(contentsOf: registryURL),
              let registry = try? JSONDecoder().decode(AuthRegistry.self, from: data) else {
            return .empty
        }
        return registry
    }

    private func infoFromRegistryForAPIKeyAuth(registry: AuthRegistry, authURL: URL) -> AuthSessionInfo {
        guard isActiveAuthURL(authURL),
              let record = registry.activeRecord,
              let email = record.email?.nilIfBlank else {
            return .noSignedInAccount
        }

        return AuthSessionInfo(
            status: .activeAuth,
            email: email.lowercased(),
            plan: record.plan,
            alias: record.alias,
            accountName: record.accountName,
            accountKey: record.accountKey
        )
    }

    private func tokenInfo(from authFile: AuthFile) -> TokenInfo? {
        guard let tokens = authFile.tokens,
              let idToken = tokens.idToken.nilIfBlank,
              let payload = jwtPayload(from: idToken) else {
            return nil
        }

        let email = (payload["email"] as? String)?.nilIfBlank?.lowercased()
        let authClaims = payload["https://api.openai.com/auth"] as? [String: Any]
        let jwtAccountID = (authClaims?["chatgpt_account_id"] as? String)?.nilIfBlank
        let tokenAccountID = tokens.accountID.nilIfBlank
        let userID = ((authClaims?["chatgpt_user_id"] as? String) ?? (authClaims?["user_id"] as? String))?.nilIfBlank
        let plan = AuthSessionPlan(rawValue: authClaims?["chatgpt_plan_type"] as? String)

        let accountID: String?
        if let tokenAccountID, let jwtAccountID, tokenAccountID == jwtAccountID {
            accountID = tokenAccountID
        } else if tokenAccountID == nil {
            accountID = jwtAccountID
        } else if jwtAccountID == nil {
            accountID = tokenAccountID
        } else {
            accountID = nil
        }

        let accountKey: String?
        if let userID, let accountID {
            accountKey = "\(userID)::\(accountID)"
        } else {
            accountKey = nil
        }

        return TokenInfo(email: email, plan: plan, accountKey: accountKey)
    }

    private func jwtPayload(from idToken: String) -> [String: Any]? {
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2,
              let data = base64URLData(String(parts[1])),
              let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any] else {
            return nil
        }
        return payload
    }

    private func base64URLData(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }

    private func fileFingerprint(for url: URL?) -> AuthSessionFileFingerprint {
        guard let url else {
            return AuthSessionFileFingerprint(path: "", exists: false, modificationDate: nil, size: nil)
        }

        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
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

struct AuthSessionFingerprint: Equatable {
    var auth: AuthSessionFileFingerprint
    var registry: AuthSessionFileFingerprint
}

struct AuthSessionFileFingerprint: Equatable {
    var path: String
    var exists: Bool
    var modificationDate: Date?
    var size: UInt64?
}

private struct TokenInfo {
    var email: String?
    var plan: AuthSessionPlan?
    var accountKey: String?
}

private struct AuthFile: Decodable {
    var openAIAPIKey: String?
    var tokens: Tokens?

    enum CodingKeys: String, CodingKey {
        case openAIAPIKey = "OPENAI_API_KEY"
        case tokens
    }
}

private struct Tokens: Decodable {
    var idToken: String
    var accountID: String

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accountID = "account_id"
    }
}

private struct AuthRegistry: Decodable {
    static let empty = AuthRegistry(activeAccountKey: nil, accounts: [])

    var activeAccountKey: String?
    var accounts: [AuthRegistryAccount]

    var activeRecord: AuthRegistryAccount? {
        activeAccountKey.flatMap { record(accountKey: $0) }
    }

    enum CodingKeys: String, CodingKey {
        case activeAccountKey = "active_account_key"
        case accounts
    }

    func record(accountKey: String) -> AuthRegistryAccount? {
        accounts.first { $0.accountKey == accountKey }
    }
}

private struct AuthRegistryAccount: Decodable {
    var accountKey: String
    var email: String?
    var alias: String?
    var accountName: String?
    var plan: AuthSessionPlan?

    enum CodingKeys: String, CodingKey {
        case accountKey = "account_key"
        case email
        case alias
        case accountName = "account_name"
        case plan
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountKey = try container.decode(String.self, forKey: .accountKey)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        alias = try container.decodeIfPresent(String.self, forKey: .alias)
        accountName = try container.decodeIfPresent(String.self, forKey: .accountName)
        plan = AuthSessionPlan(rawValue: try container.decodeIfPresent(String.self, forKey: .plan))
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
