import Foundation

/// Protocol for authentication and cloud provisioning service.
public protocol AuthServiceProtocol: Sendable {
    func login(email: String, password: String) async throws -> ProvisioningResponse
    func restoreSession() async -> ProvisioningResponse?
    func logout() async
}

/// Errors occurring during cloud login & provisioning.
public enum AuthError: LocalizedError, Sendable {
    case invalidCredentials
    case networkFailure(String)
    case serverError(String)
    case decodingError
    case unauthenticated
    
    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid username or password. Please check credentials."
        case .networkFailure(let msg):
            return "Network connection error: \(msg)"
        case .serverError(let msg):
            return msg
        case .decodingError:
            return "Failed to parse provisioning response from server."
        case .unauthenticated:
            return "User session has expired. Please log in again."
        }
    }
}

/// Cloud authentication and SIP provisioning client.
public final class AuthService: AuthServiceProtocol, @unchecked Sendable {
    public static let shared = AuthService()
    
    private let baseUrl: URL
    private let session: URLSession
    private let keychain: KeychainManager
    
    private let sessionUserKey = "merosip.auth.user"
    private let sessionAccountKey = "merosip.sip.account"
    private let tokenKey = "merosip.auth.jwt"
    
    public init(
        baseUrl: URL = URL(string: "https://sipbackend.mims.top/api/v1")!,
        session: URLSession = .shared,
        keychain: KeychainManager = .shared
    ) {
        self.baseUrl = baseUrl
        self.session = session
        self.keychain = keychain
    }
    
    public var baseURL: URL {
        baseUrl
    }
    
    public func login(email: String, password: String) async throws -> ProvisioningResponse {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            throw AuthError.invalidCredentials
        }
        
        let loginUrl = baseUrl.appendingPathComponent("auth/login")
        var request = URLRequest(url: loginUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10.0
        
        let body: [String: String] = [
            "email": trimmedEmail,
            "password": password
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AuthError.serverError("No response received from production server.")
            }
            
            if http.statusCode == 200 {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let provisioned = try decoder.decode(ProvisioningResponse.self, from: data)
                saveSession(response: provisioned)
                print("[AuthService] Successfully authenticated with production server. User: \(provisioned.user.email), SIP Extension: \(provisioned.sipAccount.username) on \(provisioned.sipAccount.domain)")
                return provisioned
            } else if http.statusCode == 401 || http.statusCode == 422 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["message"] as? String {
                    throw AuthError.serverError(message)
                }
                throw AuthError.invalidCredentials
            } else {
                throw AuthError.serverError("Server returned status code \(http.statusCode)")
            }
        } catch let err as AuthError {
            throw err
        } catch {
            print("[AuthService] Network error during login: \(error)")
            throw AuthError.networkFailure(error.localizedDescription)
        }
    }
    
    public func restoreSession() async -> ProvisioningResponse? {
        guard let userData = keychain.get(key: sessionUserKey),
              let accountData = keychain.get(key: sessionAccountKey),
              let token = keychain.getString(key: tokenKey) else {
            return nil
        }
        
        do {
            let user = try JSONDecoder().decode(AuthUser.self, from: userData)
            let account = try JSONDecoder().decode(SIPAccount.self, from: accountData)
            return ProvisioningResponse(user: user, sipAccount: account, authToken: token)
        } catch {
            return nil
        }
    }
    
    public func logout() async {
        _ = keychain.delete(key: sessionUserKey)
        _ = keychain.delete(key: sessionAccountKey)
        _ = keychain.delete(key: tokenKey)
    }
    
    private func saveSession(response: ProvisioningResponse) {
        if let userData = try? JSONEncoder().encode(response.user) {
            _ = keychain.save(key: sessionUserKey, data: userData)
        }
        if let accountData = try? JSONEncoder().encode(response.sipAccount) {
            _ = keychain.save(key: sessionAccountKey, data: accountData)
        }
        _ = keychain.save(key: tokenKey, string: response.authToken)
    }
}
