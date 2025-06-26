import Foundation
import Security
import UIKit
import os.log

// MARK: - JWT Token Model
struct JWT: Codable, Sendable {
    let token: String
    let expiresAt: Date
    let refreshToken: String?
    
    var expiryDate: Date { expiresAt }
    
    var isExpired: Bool {
        JWTValidator.isExpired(self)
    }
    
    var needsRefresh: Bool {
        // Refresh if less than 5 minutes remaining
        expiresAt.timeIntervalSinceNow < 300
    }
}

// MARK: - JWT Validator
struct JWTValidator {
    static let clockSkewTolerance: TimeInterval = 30 // ±30 seconds
    
    static func isValid(_ token: JWT) -> Bool {
        let now = Date()
        let expiry = token.expiryDate
        
        // Allow for clock skew
        return expiry > now.addingTimeInterval(-clockSkewTolerance)
    }
    
    static func isExpired(_ token: JWT) -> Bool {
        !isValid(token)
    }
}

// MARK: - JWT Manager
@MainActor
class JWTManager: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isRefreshing = false
    
    private var currentToken: JWT?
    private let keychain = KeychainHelper()
    private let networkManager = NetworkManager.shared
    private let logger = Logger(subsystem: "com.voicenote", category: "JWTManager")
    
    private let keychainKey = "com.voicenote.jwt"
    private let refreshKeychainKey = "com.voicenote.jwt.refresh"
    
    init() {
        Task {
            await loadStoredToken()
        }
    }
    
    // MARK: - Public Methods
    
    func getValidToken() async throws -> String {
        // Check if we have a token
        guard let token = currentToken else {
            logger.info("No token found, authenticating...")
            return try await authenticate()
        }
        
        // Check if token needs refresh
        if token.needsRefresh && !isRefreshing {
            logger.info("Token needs refresh")
            do {
                return try await refreshToken()
            } catch {
                // If refresh fails, try full authentication
                logger.warning("Refresh failed, re-authenticating: \(error)")
                return try await authenticate()
            }
        }
        
        // Check if token is valid
        if JWTValidator.isValid(token) {
            return token.token
        } else {
            logger.info("Token expired, authenticating...")
            return try await authenticate()
        }
    }
    
    func signOut() async {
        currentToken = nil
        isAuthenticated = false
        
        // Clear keychain
        try? keychain.delete(key: keychainKey)
        try? keychain.delete(key: refreshKeychainKey)
    }
    
    // MARK: - Private Methods
    
    private func authenticate() async throws -> String {
        isRefreshing = true
        defer { isRefreshing = false }
        
        // Bootstrap token endpoint - no auth required!
        guard let url = URL(string: "\(Config.backendURL)/api/auth/bootstrap") else {
            throw AIError.authenticationFailed(needsRefresh: false)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Generate anonymous device ID for privacy
        let deviceId = getOrCreateAnonymousDeviceId()
        let bootstrapRequest = BootstrapRequest(
            deviceId: deviceId,
            platform: "iOS",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            systemVersion: UIDevice.current.systemVersion
        )
        
        request.httpBody = try JSONEncoder().encode(bootstrapRequest)
        
        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            logger.error("Bootstrap failed with status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            throw AIError.authenticationFailed(needsRefresh: false)
        }
        
        // Parse response
        let bootstrapResponse = try JSONDecoder().decode(BootstrapResponse.self, from: data)
        
        // Convert to JWT format
        let jwt = JWT(
            token: bootstrapResponse.token,
            expiresAt: Date().addingTimeInterval(bootstrapResponse.expiresIn),
            refreshToken: bootstrapResponse.refreshToken
        )
        
        // Store token
        await storeToken(jwt)
        
        #if DEBUG
        logger.info("Bootstrap token obtained, expires in \(bootstrapResponse.expiresIn)s")
        #endif
        
        return jwt.token
    }
    
    private func refreshToken() async throws -> String {
        guard let currentToken = currentToken,
              let refreshToken = currentToken.refreshToken else {
            throw AIError.authenticationFailed(needsRefresh: true)
        }
        
        isRefreshing = true
        defer { isRefreshing = false }
        
        // Create request
        guard let url = URL(string: "\(Config.backendURL)/api/auth/refresh") else {
            throw AIError.authenticationFailed(needsRefresh: true)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["refreshToken": refreshToken]
        request.httpBody = try JSONEncoder().encode(body)
        
        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AIError.authenticationFailed(needsRefresh: true)
        }
        
        // Parse response
        let jwt = try JSONDecoder().decode(JWT.self, from: data)
        
        // Store new token
        await storeToken(jwt)
        
        return jwt.token
    }
    
    private func storeToken(_ jwt: JWT) async {
        currentToken = jwt
        isAuthenticated = true
        
        // Store in keychain
        do {
            let tokenData = try JSONEncoder().encode(jwt)
            try keychain.save(tokenData, key: keychainKey)
        } catch {
            logger.error("Failed to store token in keychain: \(error)")
        }
    }
    
    private func loadStoredToken() async {
        do {
            guard let tokenData = try keychain.load(key: keychainKey) else { return }
            let jwt = try JSONDecoder().decode(JWT.self, from: tokenData)
            
            if JWTValidator.isValid(jwt) {
                currentToken = jwt
                isAuthenticated = true
                logger.debug("Loaded valid token from keychain")
            } else {
                logger.debug("Stored token is expired")
                try keychain.delete(key: keychainKey)
            }
        } catch {
            logger.error("Failed to load token from keychain: \(error)")
        }
    }
    
    // MARK: - Anonymous Device ID
    
    private func getOrCreateAnonymousDeviceId() -> String {
        let deviceIdKey = "com.voicenote.anonymous.deviceId"
        
        // Try to load existing anonymous ID
        if let existingId = UserDefaults.standard.string(forKey: deviceIdKey) {
            return existingId
        }
        
        // Generate new anonymous ID
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: deviceIdKey)
        return newId
    }
}

// MARK: - Keychain Helper
class KeychainHelper {
    func save(_ data: Data, key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete any existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.unableToSave
        }
    }
    
    func load(key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataRef)
        
        if status == errSecSuccess {
            return dataRef as? Data
        } else if status == errSecItemNotFound {
            return nil
        } else {
            throw KeychainError.unableToLoad
        }
    }
    
    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete
        }
    }
}

enum KeychainError: Error {
    case unableToSave
    case unableToLoad
    case unableToDelete
}

// MARK: - Bootstrap Models
struct BootstrapRequest: Codable {
    let deviceId: String
    let platform: String
    let appVersion: String
    let systemVersion: String
}

struct BootstrapResponse: Codable {
    let token: String
    let expiresIn: TimeInterval
    let refreshToken: String?
    let scope: [String]?
}