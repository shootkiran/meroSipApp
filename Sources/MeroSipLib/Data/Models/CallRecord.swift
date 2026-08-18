import Foundation

/// Persistent record of a completed or missed call.
public struct CallRecord: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let remoteUri: String
    public let remoteDisplayName: String
    public let direction: CallDirection
    public let date: Date
    public let duration: TimeInterval
    public let isMissed: Bool
    
    public init(
        id: UUID = UUID(),
        remoteUri: String,
        remoteDisplayName: String = "",
        direction: CallDirection,
        date: Date = Date(),
        duration: TimeInterval = 0,
        isMissed: Bool = false
    ) {
        self.id = id
        self.remoteUri = remoteUri
        self.remoteDisplayName = remoteDisplayName.isEmpty ? remoteUri : remoteDisplayName
        self.direction = direction
        self.date = date
        self.duration = duration
        self.isMissed = isMissed
    }
    
    public var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
