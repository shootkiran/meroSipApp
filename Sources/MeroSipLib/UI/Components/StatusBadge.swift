import SwiftUI

/// Pill-style registration status indicator.
public struct StatusBadge: View {
    public let state: RegistrationState
    
    public init(state: RegistrationState) {
        self.state = state
    }
    
    private var color: Color {
        switch state {
        case .registered:
            return .green
        case .registering:
            return .orange
        case .registrationFailed:
            return .red
        case .unconfigured, .unregistered:
            return .gray
        }
    }
    
    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(color.opacity(0.4), lineWidth: state == .registering ? 4 : 0)
                        .scaleEffect(state == .registering ? 1.5 : 1.0)
                        .opacity(state == .registering ? 0 : 1)
                        .animation(state == .registering ? .easeInOut(duration: 1).repeatForever(autoreverses: false) : .default, value: state)
                )
            
            Text(state.rawValue)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.primary.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}
