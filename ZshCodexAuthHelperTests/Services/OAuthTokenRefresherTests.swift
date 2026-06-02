import Foundation
import Testing
@testable import ZshCodexAuthHelper

struct OAuthTokenRefresherTests {
    @Test
    func knownFailuresFromHTTP400RequireRelogin() async throws {
        let cases: [(String, OAuthRefreshFailureReason)] = [
            ("refresh_token_expired", .expired),
            ("refresh_token_reused", .reused),
            ("refresh_token_invalidated", .revoked)
        ]

        for testCase in cases {
            let refresher = URLSessionOAuthTokenRefresher(executeRequest: { request in
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 400,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = try JSONSerialization.data(withJSONObject: [
                    "error": ["code": testCase.0]
                ])
                return (data, response)
            })

            do {
                _ = try await refresher.refresh(refreshToken: "refresh-old")
                Issue.record("Expected \(testCase.0) to be a permanent refresh failure.")
            } catch let failure as OAuthRefreshFailure {
                #expect(failure == .reloginRequired(testCase.1))
            }
        }
    }

    @Test
    func unknownFailureFromHTTP401RequiresRelogin() async throws {
        let refresher = URLSessionOAuthTokenRefresher(executeRequest: { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(#"{"error":{"code":"unknown"}}"#.utf8), response)
        })

        do {
            _ = try await refresher.refresh(refreshToken: "refresh-old")
            Issue.record("Expected HTTP 401 to require login.")
        } catch let failure as OAuthRefreshFailure {
            #expect(failure == .reloginRequired(.other))
        }
    }

    @Test
    func unknownFailureFromHTTP500IsTransient() async throws {
        let refresher = URLSessionOAuthTokenRefresher(executeRequest: { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(#"{"error":{"code":"server_error"}}"#.utf8), response)
        })

        do {
            _ = try await refresher.refresh(refreshToken: "refresh-old")
            Issue.record("Expected a transient refresh failure.")
        } catch let failure as OAuthRefreshFailure {
            #expect(failure == .transient("Refresh server returned HTTP 500"))
        }
    }

    @Test
    func successfulResponseDecodesRotatedTokens() async throws {
        let refresher = URLSessionOAuthTokenRefresher(executeRequest: { request in
            #expect(request.url == URL(string: "https://auth.openai.com/oauth/token"))
            let body = try #require(request.httpBody)
            let parameters = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: String]
            )
            #expect(parameters["client_id"] == "app_EMoamEEZ73f0CkXaXp7hrann")
            #expect(parameters["grant_type"] == "refresh_token")
            #expect(parameters["refresh_token"] == "refresh-old")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (
                Data(
                    #"""
                    {
                      "id_token": "id-new",
                      "access_token": "access-new",
                      "refresh_token": "refresh-new"
                    }
                    """#.utf8
                ),
                response
            )
        })

        let response = try await refresher.refresh(refreshToken: "refresh-old")

        #expect(
            response == OAuthRefreshResponse(
                idToken: "id-new",
                accessToken: "access-new",
                refreshToken: "refresh-new"
            )
        )
    }
}
