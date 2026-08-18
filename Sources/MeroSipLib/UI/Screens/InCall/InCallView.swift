import SwiftUI

/// Active call screen presented during dialing, incoming ring, or active connected call.
public struct InCallView: View {
    @ObservedObject var callManager: CallManager
    let call: CallSession
    
    public init(callManager: CallManager, call: CallSession) {
        self.callManager = callManager
        self.call = call
    }
    
    private var isIncomingRinging: Bool {
        if case .ringing(let isIncoming) = call.state {
            return isIncoming
        }
        return false
    }
    
    public var body: some View {
        ZStack {
            // Background blur & gradient
            LinearGradient(
                colors: [Color(white: 0.12), Color(white: 0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                // Remote Caller Avatar
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.blue.opacity(0.8), .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 96, height: 96)
                        .shadow(color: .blue.opacity(0.3), radius: 14, x: 0, y: 8)
                    
                    Text(initials(from: call.remoteDisplayName))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                // Caller Name and Status
                VStack(spacing: 6) {
                    Text(call.remoteDisplayName)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(call.remoteUri)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    // Call Status or Duration
                    if case .connected = call.state {
                        HStack(spacing: 8) {
                            WaveformView(isActive: !call.isOnHold)
                            Text(formatDuration(call.duration))
                                .font(.system(size: 18, weight: .medium, design: .monospaced))
                                .foregroundColor(.green)
                        }
                        .padding(.top, 4)
                    } else {
                        Text(call.state.statusDescription)
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.top, 4)
                    }
                }
                
                Spacer()
                
                // In-Call Controls (shown only when connected or dialing)
                if !isIncomingRinging {
                    InCallControlsView(callManager: callManager, call: call)
                        .padding(.bottom, 16)
                }
                
                // Bottom Call Actions (Answer / Decline / Hangup)
                HStack(spacing: 48) {
                    if isIncomingRinging {
                        // Decline Call
                        Button(action: {
                            callManager.declineCall()
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: "phone.down.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                                    .frame(width: 72, height: 72)
                                    .background(Color.red)
                                    .clipShape(Circle())
                                    .shadow(color: .red.opacity(0.4), radius: 8, x: 0, y: 4)
                                
                                Text("Decline")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // Answer Call
                        Button(action: {
                            callManager.answerCall()
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                                    .frame(width: 72, height: 72)
                                    .background(Color.green)
                                    .clipShape(Circle())
                                    .shadow(color: .green.opacity(0.4), radius: 8, x: 0, y: 4)
                                
                                Text("Answer")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        // End Call
                        Button(action: {
                            callManager.endCall()
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: "phone.down.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                                    .frame(width: 72, height: 72)
                                    .background(Color.red)
                                    .clipShape(Circle())
                                    .shadow(color: .red.opacity(0.45), radius: 10, x: 0, y: 5)
                                
                                Text("End Call")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 36)
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 520)
        #endif
    }
    
    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2, let first = parts.first?.first, let second = parts.last?.first {
            return "\(first)\(second)".uppercased()
        } else if let first = parts.first?.first {
            return "\(first)".uppercased()
        }
        return "?"
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
