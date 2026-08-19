import SwiftUI

/// Transfer sheet dialog for blind and attended call transfers.
public struct TransferSheetView: View {
    @ObservedObject var callManager: CallManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var targetUri = ""
    @State private var searchResults: [CloudContact] = []
    private let contactsService = ContactsService.shared
    
    public init(callManager: CallManager) {
        self.callManager = callManager
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Transfer Call")
                    .font(.headline)
                    .padding(.top)
                
                // Destination Input
                HStack {
                    Image(systemName: "arrow.right.arrow.left")
                        .foregroundColor(.secondary)
                    TextField("Extension or SIP URI (e.g. 1002)", text: $targetUri)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: targetUri) { newValue in
                            Task {
                                searchResults = await contactsService.searchContacts(query: newValue)
                            }
                        }
                }
                .padding(.horizontal)
                
                // Quick Contact List
                List {
                    Section("Quick Transfer to Directory") {
                        ForEach(searchResults) { contact in
                            Button(action: {
                                targetUri = contact.sipExtension
                                performTransfer()
                            }) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(contact.name)
                                            .font(.body.weight(.medium))
                                        Text("Ext: \(contact.sipExtension) • \(contact.department ?? "")")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "phone.arrow.up.right.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.plain)
                
                Button(action: performTransfer) {
                    Text("Transfer Now")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(targetUri.isEmpty)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .task {
                searchResults = (try? await contactsService.fetchContacts()) ?? []
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .frame(minWidth: 320, minHeight: 400)
        }
    }
    
    private func performTransfer() {
        guard !targetUri.isEmpty else { return }
        callManager.transferCall(to: targetUri)
        dismiss()
    }
}
