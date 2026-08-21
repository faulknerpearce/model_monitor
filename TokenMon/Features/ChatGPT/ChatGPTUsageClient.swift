import Foundation

enum ChatGPTUsageError: LocalizedError, ProviderUsageError {
    case notSignedIn
    case unauthorized
    case badResponse(String)
    case network(String)

    var usageError: UsageError {
        switch self {
        case .notSignedIn: return .notSignedIn
        case .unauthorized: return .unauthorized
        case let .badResponse(message): return .badResponse(message)
        case let .network(message): return .network(message)
        }
    }

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to ChatGPT to load usage."
        case .unauthorized:
            return "ChatGPT session expired. Sign in again."
        case let .badResponse(message):
            return "ChatGPT response error: \(message)"
        case let .network(message):
            return "ChatGPT network error: \(message)"
        }
    }
}

/// Fetches Codex/ChatGPT rate-limit usage.
///
/// Two-step flow: the captured session cookie exchanges for a short-lived web
/// access token at `/api/auth/session`, which authorizes the internal
/// `/backend-api/wham/usage` endpoint.
struct ChatGPTUsageClient: Sendable {
    static let baseURL = URL(string: "https://chatgpt.com")!

    private let cookieHeader: String

    init(cookieHeader: String) {
        self.cookieHeader = cookieHeader
    }

    func fetchUsage(now: Date = Date()) async throws -> (ChatGPTUsageResponse, Date) {
        let accessToken = try await fetchAccessToken()
        let accountID = ChatGPTAccountID.fromAccessToken(accessToken)
        let data = try await whamUsage(accessToken: accessToken, accountID: accountID)
        let response = try ChatGPTUsageResponse.parse(data)
        return (response, now)
    }

    /// Parses the `/api/auth/session` payload for the bearer access token.
    static func parseSessionToken(_ data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = JSON.string(root["accessToken"]), !token.isEmpty
        else {
            throw ChatGPTUsageError.unauthorized
        }
        return token
    }

    private func fetchAccessToken() async throws -> String {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/auth/session"))
        request.httpMethod = "GET"
        AuthenticatedRequest.applyHeaders(
            to: &request,
            cookieHeader: cookieHeader,
            bearerToken: nil,
            referer: "https://chatgpt.com/"
        )
        let data = try await AuthenticatedRequest.perform(request) { usageError in
            switch usageError {
            case .notSignedIn: return ChatGPTUsageError.notSignedIn
            case .unauthorized: return ChatGPTUsageError.unauthorized
            case let .network(message): return ChatGPTUsageError.network(message)
            case let .badResponse(message): return ChatGPTUsageError.badResponse(message)
            }
        }
        return try Self.parseSessionToken(data)
    }

    private func whamUsage(accessToken: String, accountID: String?) async throws -> Data {
        var request = URLRequest(
            url: URL(string: "/backend-api/wham/usage", relativeTo: Self.baseURL)!.absoluteURL
        )
        request.httpMethod = "GET"
        AuthenticatedRequest.applyHeaders(
            to: &request,
            cookieHeader: cookieHeader,
            bearerToken: accessToken,
            referer: "https://chatgpt.com/"
        )
        if let accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        return try await AuthenticatedRequest.perform(request) { usageError in
            switch usageError {
            case .notSignedIn: return ChatGPTUsageError.notSignedIn
            case .unauthorized: return ChatGPTUsageError.unauthorized
            case let .network(message): return ChatGPTUsageError.network(message)
            case let .badResponse(message): return ChatGPTUsageError.badResponse(message)
            }
        }
    }
}
