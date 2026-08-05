import Foundation

struct ClaudeOAuthRefreshClient: Sendable {
    private static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let defaultClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let clientIDEnvironmentKey = "TOKEN_CHECKER_CLAUDE_OAUTH_CLIENT_ID"

    private static var clientID: String {
        ProcessInfo.processInfo.environment[clientIDEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? defaultClientID
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(
            configuration: config,
            delegate: OAuthNoRedirectDelegate.shared,
            delegateQueue: nil
        )
    }()

    func refresh(_ credentials: ClaudeOAuthCredentials) async throws -> ClaudeOAuthCredentials {
        guard let refreshToken = credentials.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            throw DomainError.anthropicOAuthRefreshFailed
        }

        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: Self.clientID),
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            throw DomainError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw DomainError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw DomainError.anthropicOAuthRefreshFailed
        }

        do {
            let token = try JSONDecoder().decode(TokenResponse.self, from: data)
            return ClaudeOAuthCredentials(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken?.nilIfEmpty ?? refreshToken,
                expiresAt: Date(timeIntervalSinceNow: TimeInterval(token.expiresIn)),
                scopes: credentials.scopes,
                rateLimitTier: credentials.rateLimitTier,
                subscriptionType: credentials.subscriptionType
            )
        } catch {
            throw DomainError.decoding("Claude OAuth refresh: \(error.localizedDescription)")
        }
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private final class OAuthNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = OAuthNoRedirectDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
