import Foundation

/// Represents the direction of a call.
public enum CallDirection: String, Codable, Sendable {
    case incoming
    case outgoing
}

/// Represents an active or historical call session.
public struct CallSession: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let callId: Int32
    public let remoteUri: String
    public let remoteDisplayName: String
    public let direction: CallDirection
    public var state: CallState
    public let startTime: Date
    public var connectTime: Date?
    public var endTime: Date?
    public var isMuted: Bool
    public var isOnHold: Bool
    
    public init(
        id: UUID = UUID(),
        callId: Int32 = -1,
        remoteUri: String,
        remoteDisplayName: String = "",
        direction: CallDirection,
        state: CallState = .idle,
        startTime: Date = Date(),
        connectTime: Date? = nil,
        endTime: Date? = nil,
        isMuted: Bool = false,
        isOnHold: Bool = false
    ) {
        self.id = id
        self.callId = callId
        self.remoteUri = remoteUri
        self.remoteDisplayName = remoteDisplayName.isEmpty ? remoteUri : remoteDisplayName
        self.direction = direction
        self.state = state
        self.startTime = startTime
        self.connectTime = connectTime
        self.endTime = endTime
        self.isMuted = isMuted
        self.isOnHold = isOnHold
    }
    
    public var duration: TimeInterval {
        guard let connectTime = connectTime else { return 0 }
        let end = endTime ?? Date()
        return max(0, end.timeIntervalSince(connectTime))
    }
}
