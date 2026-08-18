import Foundation

/// Represents a contact synced from the cloud backend.
public struct CloudContact: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let sipExtension: String
    public let directPhone: String?
    public let email: String?
    public let department: String?
    public let isFavorite: Bool
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        sipExtension: String,
        directPhone: String? = nil,
        email: String? = nil,
        department: String? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.sipExtension = sipExtension
        self.directPhone = directPhone
        self.email = email
        self.department = department
        self.isFavorite = isFavorite
    }
    
    public var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2, let first = parts.first?.first, let second = parts.last?.first {
            return "\(first)\(second)".uppercased()
        } else if let first = parts.first?.first {
            return "\(first)".uppercased()
        }
        return "?"
    }
}
