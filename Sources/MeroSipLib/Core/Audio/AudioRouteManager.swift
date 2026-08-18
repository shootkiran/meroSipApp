import Foundation
import AVFoundation

/// Manages audio input and output routing across macOS and iOS.
@MainActor
public final class AudioRouteManager: ObservableObject {
    public static let shared = AudioRouteManager()
    
    @Published public private(set) var currentRoute: AudioRoute = .builtInSpeaker
    @Published public private(set) var availableRoutes: [AudioRoute] = [.builtInSpeaker, .builtInReceiver, .bluetooth]
    
    public init() {
        configureAudioSession()
    }
    
    public func setRoute(_ route: AudioRoute) {
        self.currentRoute = route
        
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            switch route {
            case .builtInSpeaker:
                try session.overrideOutputAudioPort(.speaker)
            case .builtInReceiver:
                try session.overrideOutputAudioPort(.none)
            case .bluetooth, .headphones:
                try session.overrideOutputAudioPort(.none)
            }
        } catch {
            print("Failed to set audio route: \(error)")
        }
        #endif
    }
    
    public func configureAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("Failed to configure AVAudioSession: \(error)")
        }
        #endif
    }
}
