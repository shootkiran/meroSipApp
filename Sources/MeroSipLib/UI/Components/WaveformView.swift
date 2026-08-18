import SwiftUI

/// Animated audio waveform activity visualizer.
public struct WaveformView: View {
    public let isActive: Bool
    
    @State private var phase: CGFloat = 0
    
    public init(isActive: Bool = true) {
        self.isActive = isActive
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 4, height: barHeight(for: index))
            }
        }
        .frame(height: 36)
        .onAppear {
            if isActive {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    phase = 1.0
                }
            }
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        guard isActive else { return 6 }
        let heights: [CGFloat] = [10, 22, 34, 18, 30, 26, 14]
        let base = heights[index % heights.count]
        return base * (0.6 + 0.4 * (index % 2 == 0 ? phase : (1.0 - phase)))
    }
}
