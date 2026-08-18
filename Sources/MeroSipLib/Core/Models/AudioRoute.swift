import Foundation

/// Audio output routing representation across macOS and iOS.
public enum AudioRoute: String, CaseIterable, Sendable, Identifiable {
    case builtInReceiver = "Receiver"
    case builtInSpeaker = "Speaker"
    case bluetooth = "Bluetooth Headset"
    case headphones = "Headphones"
    
    public var id: String { rawValue }
    
    public var systemImage: String {
        switch self {
        case .builtInReceiver:
            return "phone.fill"
        case .builtInSpeaker:
            return "speaker.wave.3.fill"
        case .bluetooth:
            return "headphones"
        case .headphones:
            return "earbuds"
        }
    }
}
