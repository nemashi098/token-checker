import Foundation
import Security
import CryptoKit

struct ClaudeOAuthCredentials: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let scopes: [String]
    let rateLimitTier: String?
    let subscriptionType: String?
    var sourceFingerprint: String? = nil

    var fingerprint: String {
        sourceFingerprint ?? SHA256.hash(data: Data((accessToken + "\0" + (refreshToken ?? "")).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// Refresh slightly early so a token does not expire between fetching and calling the usage API.
    var isExpired: Bool {
        guard let expiresAt else { return true }
        return Date() >= expiresAt.addingTimeInterval(-60)
    }
}

/// macOS Keychain から Claude Code の OAuth トークンを読み取る。
///
/// `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w` を spawn する。
/// 直接 Security framework を叩いてもよいが、CLI 経由のほうが ACL 確認のダイアログ UX が
/// 安定する。
struct KeychainTokenSource: Sendable {
    static let serviceName = "Claude Code-credentials"
    let location: ClaudeCredentialLocation
    private let cache: ClaudeOAuthCache

    init(location: ClaudeCredentialLocation = .init()) {
        self.location = location
        self.cache = ClaudeOAuthCache(account: location.serviceName)
    }

    /// 旧呼び出し向け。新しい実装では refreshToken / expiresAt も読む。
    func readAccessToken() async throws -> String {
        try await readCredentials().accessToken
    }

    func readCredentials() async throws -> ClaudeOAuthCredentials {
        let cliCredentials = try await readClaudeCodeCredentials()
        guard cliCredentials.isExpired else { return cliCredentials }

        if let cached = cache.read(),
           cached.sourceFingerprint == cliCredentials.fingerprint, !cached.isExpired {
            return cached
        }

        return cliCredentials
    }

    func cacheCredentials(_ credentials: ClaudeOAuthCredentials) throws {
        try cache.save(credentials)
    }

    private func readClaudeCodeCredentials() async throws -> ClaudeOAuthCredentials {
        var keychainError: DomainError = .keychainTokenMissing
        do {
            return try await readClaudeCodeCredentialsWithSecurityTool()
        } catch let error as DomainError {
            keychainError = error
        }
        // Current Claude Code also uses this file when macOS Keychain writes fail.
        // Only read the selected profile; never fall back to a different account.
        if FileManager.default.fileExists(atPath: location.credentialsURL.path) {
            do {
                return try KeychainPayload.credentials(from: Data(contentsOf: location.credentialsURL))
            } catch let error as DomainError {
                throw error
            } catch {
                // Decoder errors can contain credential values. Do not expose their details.
                throw DomainError.decoding("Claude credential file")
            }
        }
        throw keychainError
    }

    private func readClaudeCodeCredentialsWithSecurityTool() async throws -> ClaudeOAuthCredentials {
        let username = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()
        let argumentSets = [
            ["find-generic-password", "-a", username, "-s", location.serviceName, "-w"],
            ["find-generic-password", "-s", location.serviceName, "-w"],
        ]
        for arguments in argumentSets {
            do {
                return try await readClaudeCodeCredentialsWithSecurityTool(arguments: arguments)
            } catch DomainError.keychainTokenMissing {
                continue
            }
        }
        throw DomainError.keychainTokenMissing
    }

    private func readClaudeCodeCredentialsWithSecurityTool(arguments: [String]) async throws -> ClaudeOAuthCredentials {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        // stderr は捨て読みもしない。FileHandle.nullDevice に向けてパイプバッファ詰まりと
        // waitUntilExit のデッドロック経路をそもそも作らない。
        process.standardError = FileHandle.nullDevice

        // 旧実装は process.waitUntilExit() を同期で呼んでおり、Keychain ACL ダイアログ
        // 表示中に Swift Concurrency の Cooperative Thread Pool を奪っていた。
        // terminationHandler ベースで Continuation を解決し、async に整合させる。
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in cont.resume() }
                do {
                    try process.run()
                } catch {
                    // run() が throw すると terminationHandler は発火しない。
                    // ここで Continuation を一度だけ resume する。
                    process.terminationHandler = nil
                    cont.resume(throwing: DomainError.keychainTokenMissing)
                }
            }
        } catch {
            throw DomainError.keychainTokenMissing
        }

        guard process.terminationStatus == 0 else {
            if process.terminationStatus == 44 { throw DomainError.keychainTokenMissing }
            throw DomainError.keychainReadFailed(status: process.terminationStatus)
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        do {
            return try KeychainPayload.credentials(from: data)
        } catch let error as DomainError {
            throw error
        } catch {
            throw DomainError.decoding("Claude Keychain payload")
        }
    }
}

/// Match Claude Code's profile-specific storage naming (including Unicode normalization).
struct ClaudeCredentialLocation: Sendable {
    let directory: URL
    let serviceName: String
    var credentialsURL: URL { directory.appendingPathComponent(".credentials.json") }

    init(environment: [String: String] = ProcessInfo.processInfo.environment,
         home: String = NSHomeDirectory()) {
        let secureDirectory = environment["CLAUDE_SECURESTORAGE_CONFIG_DIR"]
        let configDirectory = environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 }
        let customDirectory: String?
        if let secureDirectory {
            customDirectory = secureDirectory.isEmpty ? nil : secureDirectory
        } else {
            customDirectory = configDirectory
        }
        let path = (customDirectory ?? home + "/.claude").precomposedStringWithCanonicalMapping
        directory = URL(fileURLWithPath: path, isDirectory: true)
        if customDirectory != nil {
            let suffix = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined().prefix(8)
            serviceName = KeychainTokenSource.serviceName + "-" + suffix
        } else {
            serviceName = KeychainTokenSource.serviceName
        }
    }
}

/// Claude Code が Keychain / fallback file に保存する JSON 構造。
struct KeychainPayload: Decodable {
    let claudeAiOauth: OAuth?

    enum CodingKeys: String, CodingKey {
        case claudeAiOauth = "claudeAiOauth"
    }

    struct OAuth: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let expiresAt: Double?
        let scopes: [String]?
        let rateLimitTier: String?
        let subscriptionType: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "accessToken"
            case refreshToken = "refreshToken"
            case expiresAt = "expiresAt"
            case scopes = "scopes"
            case rateLimitTier = "rateLimitTier"
            case subscriptionType = "subscriptionType"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            accessToken = try? container.decode(String.self, forKey: .accessToken)
            refreshToken = try? container.decode(String.self, forKey: .refreshToken)
            expiresAt = Self.decodeTimestamp(from: container, forKey: .expiresAt)
            scopes = (try? container.decode([String].self, forKey: .scopes))
                ?? (try? container.decode(String.self, forKey: .scopes).split(separator: " ").map(String.init))
            rateLimitTier = try? container.decode(String.self, forKey: .rateLimitTier)
            subscriptionType = try? container.decode(String.self, forKey: .subscriptionType)
        }

        private static func decodeTimestamp(
            from container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) -> Double? {
            if let value = try? container.decode(Double.self, forKey: key) {
                return value
            }
            if let string = try? container.decode(String.self, forKey: key) {
                return Double(string)
            }
            return nil
        }
    }

    static func credentials(from data: Data) throws -> ClaudeOAuthCredentials {
        let payload = try JSONDecoder().decode(KeychainPayload.self, from: data)
        guard let oauth = payload.claudeAiOauth else {
            throw DomainError.keychainTokenMissing
        }

        let accessToken = oauth.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !accessToken.isEmpty else {
            throw DomainError.keychainTokenMissing
        }

        return ClaudeOAuthCredentials(
            accessToken: accessToken,
            refreshToken: oauth.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            expiresAt: oauth.expiresAt.flatMap { value in
                guard value.isFinite, value > 0 else { return nil }
                return Date(timeIntervalSince1970: value > 100_000_000_000 ? value / 1000.0 : value)
            },
            scopes: oauth.scopes ?? [],
            rateLimitTier: oauth.rateLimitTier,
            subscriptionType: oauth.subscriptionType
        )
    }
}

private struct ClaudeOAuthCache: Sendable {
    private static let service = "TokenChecker Claude OAuth Cache"
    let account: String

    func read() -> ClaudeOAuthCredentials? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(ClaudeOAuthCredentials.self, from: data)
    }

    func save(_ credentials: ClaudeOAuthCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: account,
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw DomainError.keychainCacheFailed(status: updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw DomainError.keychainCacheFailed(status: addStatus)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
