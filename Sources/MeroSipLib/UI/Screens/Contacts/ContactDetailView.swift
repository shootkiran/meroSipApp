import SwiftUI

/// Detailed contact information view with quick SIP and direct call actions.
public struct ContactDetailView: View {
    @ObservedObject var callManager: CallManager
    public let contact: CloudContact
    
    public init(callManager: CallManager, contact: CloudContact) {
        self.callManager = callManager
        self.contact = contact
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Large Avatar
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.blue, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 84, height: 84)
                    
                    Text(contact.initials)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.top, 16)
                
                // Name & Department
                VStack(spacing: 4) {
                    Text(contact.name)
                        .font(.title2.weight(.bold))
                    
                    if let dept = contact.department {
                        Text(dept)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Quick Action Bar
                HStack(spacing: 24) {
                    ContactActionButton(icon: "phone.fill", label: "Extension", color: .green) {
                        callManager.startCall(to: contact.sipExtension, displayName: contact.name)
                    }
                    
                    if let direct = contact.directPhone {
                        ContactActionButton(icon: "phone.arrow.up.right.fill", label: "Direct", color: .blue) {
                            callManager.startCall(to: direct, displayName: contact.name)
                        }
                    }
                }
                
                // Detail List
                VStack(alignment: .leading, spacing: 14) {
                    ContactInfoCard(title: "SIP Extension", value: contact.sipExtension, icon: "number")
                    
                    if let direct = contact.directPhone {
                        ContactInfoCard(title: "Direct Phone", value: direct, icon: "phone")
                    }
                    
                    if let email = contact.email {
                        ContactInfoCard(title: "Email", value: email, icon: "envelope")
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(contact.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct ContactActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(width: 50, height: 50)
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }
                Text(label)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct ContactInfoCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.body)
            }
            Spacer()
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
