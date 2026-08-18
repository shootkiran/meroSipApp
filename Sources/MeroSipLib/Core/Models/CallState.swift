import Foundation

/// Represents the lifecycle state of a SIP VoIP call session.
public enum CallState: Equatable, Sendable {
    case idle
    case connecting
    case dialing(destination: String)
    case ringing(isIncoming: Bool)
    case connected(duration: TimeInterval)
    case holding
    case transferring(target: String)
    case disconnected(reason: DisconnectReason)
    
    public var isCallActive: Bool {
        switch self {
        case .dialing, .ringing, .connected, .holding, .transferring:
            return true
        case .idle, .connecting, .disconnected:
            return false
        }
    }
    
    public var statusDescription: String {
        switch self {
        case .idle:
            return "Ready"
        case .connecting:
            return "Connecting..."
        case .dialing:
            return "Calling..."
        case .ringing(let isIncoming):
            return isIncoming ? "Incoming Call..." : "Ringing..."
        case .connected:
            return "Connected"
        case .holding:
            return "On Hold"
        case .transferring(let target):
            return "Transferring to \(target)..."
        case .disconnected(let reason):
            return reason.rawValue
        }
    }
}

/// Reasons for call termination.
public enum DisconnectReason: String, Sendable, Equatable {
    case normal = "Call Ended"
    case busy = "User Busy"
    case declined = "Call Declined"
    case failed = "Call Failed"
    case networkError = "Network Error"
    case timeout = "No Answer"
}
