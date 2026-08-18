import SwiftUI

/// Compact popover dialer and status view shown from the macOS menu bar icon.
public struct MenuBarStatusItemView: View {
    @ObservedObject var callManager: CallManager
    
    public init(callManager: CallManager) {
        self.callManager = callManager
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("MeroSip Quick Dialer")
                    .font(.headline)
                Spacer()
                StatusBadge(state: callManager.registrationState)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            Divider()
            
            if let call = callManager.activeCall {
                // Active Call Mini Card
                VStack(spacing: 8) {
                    Text(call.remoteDisplayName)
                        .font(.headline)
                    Text(call.state.statusDescription)
                        .font(.subheadline)
                        .foregroundColor(.green)
                    
                    HStack(spacing: 16) {
                        Button("Mute") {
                            callManager.toggleMute()
                        }
                        .tint(call.isMuted ? .orange : .secondary)
                        
                        Button("End") {
                            callManager.endCall()
                        }
                        .tint(.red)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
            } else {
                // Compact Keypad
                KeypadView(callManager: callManager)
                    .frame(height: 380)
            }
            
            Divider()
            
            HStack {
                if let ext = callManager.provisionedAccount?.username {
                    Text("My Extension: \(ext)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Quit") {
                    #if os(macOS)
                    NSApplication.shared.terminate(nil)
                    #endif
                }
                .font(.caption)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .frame(width: 320)
    }
}
