import Foundation

protocol OAuthTokenRefreshing: Sendable {
    func refresh(refreshToken: String) async throws -> OAuthRefreshResponse
}

struct OAuthRefreshResponse: Decodable, Equatable, Sendable {
    var idToken: String?
    var accessToken: String?
    var refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

enum OAuthRefreshFailureReason: Equatable, Sendable {
    case expired
    case reused
    case revoked
    case other

    var displayName: String {
        switch self {
        case .expired:
            return "expired"
        case .reused:
            return "already used"
        case .revoked:
            return "revoked"
        case .other:
            return "not accepted"
        }
    }
}

enum OAuthRefreshFailure: LocalizedError, Equatable, Sendable {
    case reloginRequired(OAuthRefreshFailureReason)
    case transient(String)

    var errorDescription: String? {
        switch self {
        case .reloginRequired(let reason):
            return "Refresh token \(reason.displayName)."
        case .transient(let message):
            return message
        }
    }
}

struct URLSessionOAuthTokenRefresher: OAuthTokenRefreshing {
    typealias RequestExecutor = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private static let endpoint = URL(string: "https://auth.openai.com/oauth/token")!
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let executeRequest: RequestExecutor

    init(
        executeRequest: @escaping RequestExecutor = {
            try await URLSession.shared.data(for: $0)
        }
    ) {
        self.executeRequest = executeRequest
    }

    func refresh(refreshToken: String) async throws -> OAuthRefreshResponse {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": Self.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await executeRequest(request)
        } catch {
            throw OAuthRefreshFailure.transient(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthRefreshFailure.transient("Refresh server returned a non-HTTP response")
        }

        if (200...299).contains(httpResponse.statusCode) {
            return try JSONDecoder().decode(OAuthRefreshResponse.self, from: data)
        }

        let failureReason = Self.failureReason(from: data)
        if httpResponse.statusCode == 401 || failureReason != .other {
            throw OAuthRefreshFailure.reloginRequired(failureReason)
        }

        throw OAuthRefreshFailure.transient("Refresh server returned HTTP \(httpResponse.statusCode)")
    }

    private static func failureReason(from data: Data) -> OAuthRefreshFailureReason {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .other
        }

        let code: String?
        if let error = object["error"] as? [String: Any] {
            code = error["code"] as? String
        } else {
            code = object["error"] as? String ?? object["code"] as? String
        }

        switch code?.lowercased() {
        case "refresh_token_expired":
            return .expired
        case "refresh_token_reused":
            return .reused
        case "refresh_token_invalidated":
            return .revoked
        default:
            return .other
        }
    }
}
