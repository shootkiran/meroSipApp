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
                    isActive: call.isMuted,
                    activeColor: .orange
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
            
            // Row 2: Hold, Transfer
            HStack(spacing: 28) {
                // Hold Button
                InCallButton(
                    icon: call.isOnHold ? "play.fill" : "pause.fill",
                    title: call.isOnHold ? "Resume" : "Hold",
                    isActive: call.isOnHold,
                    activeColor: .yellow
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

/// Circular in-call action button with label and bright high-contrast dark-mode visibility.
struct InCallButton: View {
    let icon: String
    let title: String
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void
    
    init(icon: String, title: String, isActive: Bool, activeColor: Color = .white, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.isActive = isActive
        self.activeColor = activeColor
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isActive ? activeColor : Color.white.opacity(0.18))
                        .frame(width: 64, height: 64)
                        .overlay(
                            Circle()
                                .stroke(isActive ? activeColor.opacity(0.8) : Color.white.opacity(0.3), lineWidth: 1.5)
                        )
                        .shadow(color: isActive ? activeColor.opacity(0.4) : Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
                    
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(isActive ? (activeColor == .white ? .black : .black) : .white)
                }
                
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isActive ? (activeColor == .white ? .white : activeColor) : Color.white.opacity(0.9))
                    .frame(width: 76)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}
