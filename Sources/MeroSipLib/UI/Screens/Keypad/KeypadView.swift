import SwiftUI

/// Modern Production Dialpad view supporting both on-screen buttons and physical keyboard input.
public struct KeypadView: View {
    @ObservedObject var callManager: CallManager
    
    @State private var dialedNumber = ""
    @State private var matchedContact: CloudContact?
    @FocusState private var isFieldFocused: Bool
    
    private let contactsService = ContactsService.shared
    
    public init(callManager: CallManager) {
        self.callManager = callManager
    }
    
    private let keypadGrid: [[(String, String)]] = [
        [("1", ""), ("2", "ABC"), ("3", "DEF")],
        [("4", "GHI"), ("5", "JKL"), ("6", "MNO")],
        [("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ")],
        [("*", ""), ("0", "+"), ("#", "")]
    ]
    
    public var body: some View {
        VStack(spacing: 16) {
            // Header with SIP Registration Status
            HStack {
                StatusBadge(state: callManager.registrationState)
                Spacer()
                if let ext = callManager.provisionedAccount?.username {
                    Text("Extension: \(ext)")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            Spacer()
            
            // Matched Contact Preview if number matches a directory contact
            if let contact = matchedContact {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundColor(.blue)
                    Text(contact.name)
                        .font(.subheadline.weight(.medium))
                    if let dept = contact.department, !dept.isEmpty {
                        Text("(\(dept))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.12))
                .clipShape(Capsule())
                .transition(.opacity)
            }
            
            // Dialed Number Display with direct physical keyboard typing support
            HStack {
                Spacer()
                
                TextField("Enter number or extension", text: $dialedNumber)
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .focused($isFieldFocused)
                    .onChange(of: dialedNumber) { _, newValue in
                        // Filter out non-dialpad characters
                        let filtered = newValue.filter { "0123456789*#+ ".contains($0) }
                        if filtered != newValue {
                            dialedNumber = filtered
                        }
                        lookupContact()
                    }
                    .onSubmit {
                        performCall()
                    }
                
                Spacer()
                
                if !dialedNumber.isEmpty {
                    Button(action: {
                        if !dialedNumber.isEmpty {
                            dialedNumber.removeLast()
                            lookupContact()
                        }
                    }) {
                        Image(systemName: "delete.left.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                }
            }
            .frame(height: 52)
            .padding(.horizontal, 24)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(12)
            .padding(.horizontal, 32)
            
            // Dialpad Keypad Grid
            VStack(spacing: 14) {
                ForEach(keypadGrid, id: \.self.description) { row in
                    HStack(spacing: 24) {
                        ForEach(row, id: \.0) { digit, sub in
                            DialpadButton(digit: digit, subtext: sub) {
                                dialedNumber.append(digit)
                                callManager.sendDTMF(digit)
                                lookupContact()
                            }
                        }
                    }
                }
            }
            
            // Primary Call Button
            HStack(spacing: 36) {
                if !dialedNumber.isEmpty {
                    Button(action: {
                        dialedNumber = ""
                        matchedContact = nil
                    }) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .frame(width: 52, height: 52)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Clear number (Esc)")
                } else {
                    Color.clear.frame(width: 52, height: 52)
                }
                
                Button(action: performCall) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.white)
                        .frame(width: 72, height: 72)
                        .background(dialedNumber.isEmpty ? Color.gray.opacity(0.5) : Color.green)
                        .clipShape(Circle())
                        .shadow(color: dialedNumber.isEmpty ? .clear : .green.opacity(0.35), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(dialedNumber.isEmpty)
                
                Color.clear.frame(width: 52, height: 52)
            }
            .padding(.top, 10)
            
            Spacer()
        }
        .frame(minWidth: 320)
        .onAppear {
            isFieldFocused = true
        }
        #if os(macOS)
        .onKeyPress(.escape) {
            dialedNumber = ""
            matchedContact = nil
            return .handled
        }
        #endif
    }
    
    private func performCall() {
        let trimmed = dialedNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let name = matchedContact?.name ?? trimmed
        callManager.startCall(to: trimmed, displayName: name)
    }
    
    private func lookupContact() {
        let trimmed = dialedNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            matchedContact = nil
            return
        }
        Task {
            let results = await contactsService.searchContacts(query: trimmed)
            self.matchedContact = results.first(where: { $0.sipExtension == trimmed || $0.directPhone == trimmed })
        }
    }
}
