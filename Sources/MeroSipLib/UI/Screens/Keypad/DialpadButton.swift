import SwiftUI

/// Reusable round dialpad button with primary digit and secondary subtext letters.
public struct DialpadButton: View {
    public let digit: String
    public let subtext: String
    public let action: () -> Void
    
    public init(digit: String, subtext: String = "", action: @escaping () -> Void) {
        self.digit = digit
        self.subtext = subtext
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(digit)
                    .font(.system(size: 28, weight: .regular, design: .rounded))
                    .foregroundColor(.primary)
                
                if !subtext.isEmpty {
                    Text(subtext)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .kerning(1.5)
                }
            }
            .frame(width: 72, height: 72)
            #if os(macOS)
            .background(Color(nsColor: .controlBackgroundColor))
            #else
            .background(Color(uiColor: .secondarySystemBackground))
            #endif
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}
