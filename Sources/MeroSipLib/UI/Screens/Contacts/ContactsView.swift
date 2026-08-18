import SwiftUI

/// Cloud contacts directory screen.
public struct ContactsView: View {
    @ObservedObject var callManager: CallManager
    
    @State private var contacts: [CloudContact] = []
    @State private var searchQuery = ""
    @State private var isLoading = false
    private let contactsService = ContactsService.shared
    
    public init(callManager: CallManager) {
        self.callManager = callManager
    }
    
    private var filteredContacts: [CloudContact] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return contacts }
        return contacts.filter {
            $0.name.lowercased().contains(query) ||
            $0.sipExtension.contains(query) ||
            ($0.department?.lowercased().contains(query) ?? false)
        }
    }
    
    private var favoriteContacts: [CloudContact] {
        filteredContacts.filter { $0.isFavorite }
    }
    
    public var body: some View {
        NavigationStack {
            Group {
                if isLoading && contacts.isEmpty {
                    ProgressView("Loading directory...")
                } else {
                    List {
                        if !favoriteContacts.isEmpty && searchQuery.isEmpty {
                            Section("Favorites") {
                                ForEach(favoriteContacts) { contact in
                                    NavigationLink(destination: ContactDetailView(callManager: callManager, contact: contact)) {
                                        ContactRow(contact: contact) {
                                            callManager.startCall(to: contact.sipExtension, displayName: contact.name)
                                        }
                                    }
                                }
                            }
                        }
                        
                        Section(searchQuery.isEmpty ? "All Directory Contacts" : "Search Results") {
                            ForEach(filteredContacts) { contact in
                                NavigationLink(destination: ContactDetailView(callManager: callManager, contact: contact)) {
                                    ContactRow(contact: contact) {
                                        callManager.startCall(to: contact.sipExtension, displayName: contact.name)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .searchable(text: $searchQuery, prompt: "Search names, extensions, departments")
            .navigationTitle("Contacts")
            .task {
                await loadContacts()
            }
            .refreshable {
                await loadContacts()
            }
        }
    }
    
    private func loadContacts() async {
        isLoading = true
        do {
            self.contacts = try await contactsService.fetchContacts()
        } catch {
            print("Failed to load contacts: \(error)")
        }
        isLoading = false
    }
}

struct ContactRow: View {
    let contact: CloudContact
    let onCall: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Text(contact.initials)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.body.weight(.medium))
                Text("Ext: \(contact.sipExtension) • \(contact.department ?? "General")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onCall) {
                Image(systemName: "phone.fill")
                    .font(.subheadline)
                    .foregroundColor(.green)
                    .padding(8)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}
