import Foundation

/// Authenticated user profile returned by the cloud backend.
public struct AuthUser: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let email: String
    public let fullName: String
    public let organization: String
    public let sipExtension: String
    public let avatarUrl: String?
    
    public init(
        id: String,
        email: String,
        fullName: String,
        organization: String,
        sipExtension: String,
        avatarUrl: String? = nil
    ) {
        self.id = id
        self.email = email
        self.fullName = fullName
        self.organization = organization
        self.sipExtension = sipExtension
        self.avatarUrl = avatarUrl
    }
}

/// Cloud provisioned response payload.
public struct ProvisioningResponse: Codable, Sendable {
    public let user: AuthUser
    public let sipAccount: SIPAccount
    public let authToken: String
    
    public init(user: AuthUser, sipAccount: SIPAccount, authToken: String) {
        self.user = user
        self.sipAccount = sipAccount
        self.authToken = authToken
    }
}
