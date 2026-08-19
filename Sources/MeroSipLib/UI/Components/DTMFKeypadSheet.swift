import SwiftUI

/// Floating DTMF Keypad sheet used to send in-call dial tones.
public struct DTMFKeypadSheet: View {
    @ObservedObject var callManager: CallManager
    @Environment(\.dismiss) private var dismiss
    
    public init(callManager: CallManager) {
        self.callManager = callManager
    }
    
    private let keys: [[(String, String)]] = [
        [("1", ""), ("2", "ABC"), ("3", "DEF")],
        [("4", "GHI"), ("5", "JKL"), ("6", "MNO")],
        [("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ")],
        [("*", ""), ("0", "+"), ("#", "")]
    ]
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("In-Call DTMF Dialpad")
                    .font(.headline)
                    .padding(.top)
                
                VStack(spacing: 12) {
                    ForEach(keys, id: \.self.description) { row in
                        HStack(spacing: 16) {
                            ForEach(row, id: \.0) { key, sub in
                                Button(action: {
                                    callManager.sendDTMF(key)
                                }) {
                                    VStack(spacing: 2) {
                                        Text(key)
                                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                                        if !sub.isEmpty {
                                            Text(sub)
                                                .font(.system(size: 9, weight: .bold))
                                                .opacity(0.6)
                                        }
                                    }
                                    .frame(width: 70, height: 60)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .frame(minWidth: 280, minHeight: 360)
        }
    }
}
