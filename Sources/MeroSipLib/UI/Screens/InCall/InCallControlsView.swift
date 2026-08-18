import SwiftUI

/// Control action buttons during an active call (Mute, Keypad, Audio Route, Hold, Transfer).
public struct InCallControlsView: View {
    @ObservedObject var callManager: CallManager
    let call: CallSession
    
    @State private var showDTMFSheet = false
    @State private var showTransferSheet = false
    @State private var showAudioRoutePicker = false
    
    public init(callManager: CallManager, call: CallSession) {
        self.callManager = callManager
        self.call = call
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            // Row 1: Mute, DTMF Keypad, Audio Routing
            HStack(spacing: 28) {
                // Mute Button
                InCallButton(
                    icon: call.isMuted ? "mic.slash.fill" : "mic.fill",
                    title: call.isMuted ? "Muted" : "Mute",
                    isActive: call.isMuted
                ) {
                    callManager.toggleMute()
                }
                
                // Keypad Button
                InCallButton(
                    icon: "circle.grid.3x3.fill",
                    title: "Keypad",
                    isActive: false
                ) {
                    showDTMFSheet = true
                }
                
                // Audio Route Button
                InCallButton(
                    icon: callManager.audioRouteManager.currentRoute.systemImage,
                    title: callManager.audioRouteManager.currentRoute.rawValue,
                    isActive: false
                ) {
                    showAudioRoutePicker = true
                }
            }
            
            // Row 2: Hold, Transfer, Blank placeholder
            HStack(spacing: 28) {
                // Hold Button
                InCallButton(
                    icon: call.isOnHold ? "play.fill" : "pause.fill",
                    title: call.isOnHold ? "Resume" : "Hold",
                    isActive: call.isOnHold
                ) {
                    callManager.toggleHold()
                }
                
                // Transfer Button
                InCallButton(
                    icon: "arrow.right.arrow.left",
                    title: "Transfer",
                    isActive: false
                ) {
                    showTransferSheet = true
                }
            }
        }
        .sheet(isPresented: $showDTMFSheet) {
            DTMFKeypadSheet(callManager: callManager)
        }
        .sheet(isPresented: $showTransferSheet) {
            TransferSheetView(callManager: callManager)
        }
        .confirmationDialog("Select Audio Output", isPresented: $showAudioRoutePicker, titleVisibility: .visible) {
            ForEach(callManager.audioRouteManager.availableRoutes) { route in
                Button(route.rawValue) {
                    callManager.audioRouteManager.setRoute(route)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Circular in-call action button with label.
struct InCallButton: View {
    let icon: String
    let title: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isActive ? Color.white : Color.secondary.opacity(0.18))
                        .frame(width: 64, height: 64)
                    
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(isActive ? Color.black : Color.primary)
                }
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 72)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}
