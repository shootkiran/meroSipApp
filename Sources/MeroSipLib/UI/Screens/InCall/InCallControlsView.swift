import SwiftUI

/// Control action buttons during an active call (Mute, Keypad, Audio Route, Hold, Transfer, Volume Controls).
public struct InCallControlsView: View {
    @ObservedObject var callManager: CallManager
    @ObservedObject private var rtpAudio = RTPAudioEngine.shared
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
            // Speaker & Microphone Volume Sliders with Live VU Meters
            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    HStack(spacing: 10) {
                        Image(systemName: rtpAudio.speakerVolume == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 20)
                        
                        Slider(value: $rtpAudio.speakerVolume, in: 0.0...1.0)
                            .accentColor(.blue)
                        
                        Text("\(Int(rtpAudio.speakerVolume * 100))%")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray)
                            .frame(width: 36, alignment: .trailing)
                    }
                    
                    HStack(spacing: 10) {
                        Spacer().frame(width: 20)
                        VUMeterView(level: rtpAudio.speakerLevel)
                        Spacer().frame(width: 36)
                    }
                }
                
                VStack(spacing: 4) {
                    HStack(spacing: 10) {
                        Image(systemName: rtpAudio.micVolume == 0 ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 20)
                        
                        Slider(value: $rtpAudio.micVolume, in: 0.0...1.0)
                            .accentColor(.green)
                        
                        Text("\(Int(rtpAudio.micVolume * 100))%")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray)
                            .frame(width: 36, alignment: .trailing)
                    }
                    
                    HStack(spacing: 10) {
                        Spacer().frame(width: 20)
                        VUMeterView(level: rtpAudio.micLevel)
                        Spacer().frame(width: 36)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.08))
            .cornerRadius(12)
            .frame(maxWidth: 320)
            
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

/// Dynamic VU Level Meter Bar (Green = Good, Yellow = Loud, Red = Clipping/Too Loud)
struct VUMeterView: View {
    let level: Float
    
    private var meterColor: Color {
        if level >= 0.85 { return .red }
        if level >= 0.65 { return .yellow }
        return .green
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                
                Capsule()
                    .fill(meterColor)
                    .frame(width: max(2, min(geo.size.width, geo.size.width * CGFloat(level))))
            }
        }
        .frame(height: 6)
    }
}
