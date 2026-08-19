import Foundation

/// Supported SIP Transport protocols.
public enum SIPTransport: String, Codable, Sendable {
    case udp = "UDP"
    case tcp = "TCP"
    case tls = "TLS"
}

/// Registration status of a SIP account.
public enum RegistrationState: Sendable, Equatable {
    case unconfigured
    case registering
    case registered
    case registrationFailed
    case retrying(seconds: Int)
    case unregistered
    
    public var rawValue: String {
        switch self {
        case .unconfigured:
            return "Unconfigured"
        case .registering:
            return "Connecting..."
        case .registered:
            return "Online"
        case .registrationFailed:
            return "Registration Failed"
        case .retrying(let seconds):
            return "Retrying in \(seconds)s"
        case .unregistered:
            return "Offline"
        }
    }
}

/// Provisioned SIP Account configuration.
public struct SIPAccount: Codable, Sendable, Equatable {
    public let username: String
    public let password: String?
    public let domain: String
    public let displayName: String
    public let proxy: String?
    public let port: Int
    public let transport: SIPTransport
    public let srtpEnabled: Bool
    public let stunServer: String?
    public let token: String?
    
    public init(
        username: String,
        password: String? = nil,
        domain: String,
        displayName: String = "",
        proxy: String? = nil,
        port: Int = 5060,
        transport: SIPTransport = .udp,
        srtpEnabled: Bool = false,
        stunServer: String? = "stun.l.google.com:19302",
        token: String? = nil
    ) {
        self.username = username
        self.password = password
        self.domain = domain
        self.displayName = displayName.isEmpty ? username : displayName
        self.proxy = proxy
        self.port = port
        self.transport = transport
        self.srtpEnabled = srtpEnabled
        self.stunServer = stunServer
        self.token = token
    }
    
    public var sipUri: String {
        return "sip:\(username)@\(domain)"
    }
    
    public var fullRegistrationUri: String {
        return "sip:\(domain):\(port)"
    }
}
