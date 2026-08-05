import Foundation

/// Keychain → Anthropic OAuth usage エンドポイント。
struct ClaudeUsageProvider: UsageProvider {
    let keychain: KeychainTokenSource
    let api: AnthropicUsageAPIClient
    let refreshClient: ClaudeOAuthRefreshClient

    init(
        keychain: KeychainTokenSource = .init(),
        api: AnthropicUsageAPIClient = .init(),
        refreshClient: ClaudeOAuthRefreshClient = .init()
    ) {
        self.keychain = keychain
        self.api = api
        self.refreshClient = refreshClient
    }

    func fetch() async throws -> ServiceUsage {
        var credentials = try await keychain.readCredentials()
        if credentials.isExpired {
            credentials = try await refreshAndCache(credentials)
        }

        let dto: AnthropicUsageDTO
        do {
            dto = try await api.fetch(accessToken: credentials.accessToken)
        } catch DomainError.anthropicUnauthorized {
            let refreshed = try await refreshAndCache(credentials)
            dto = try await api.fetch(accessToken: refreshed.accessToken)
        }

        let weekly = dto.sevenDay?.toRateLimit()
        return ServiceUsage(
            fiveHour: dto.fiveHour?.toRateLimit(),
            weekly: weekly,
            weeklySonnet: dto.sevenDaySonnet?.toRateLimit(),
            scopedWeekly: dto.scopedWeeklyRateLimits(defaultResetsAt: weekly?.resetsAt)
        )
    }

    private func refreshAndCache(_ credentials: ClaudeOAuthCredentials) async throws -> ClaudeOAuthCredentials {
        let refreshed = try await refreshClient.refresh(credentials)
        try keychain.cacheCredentials(refreshed)
        return refreshed
    }
}
