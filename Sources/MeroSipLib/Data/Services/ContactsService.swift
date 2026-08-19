import Foundation

/// Protocol for fetching and synchronizing cloud directory contacts.
public protocol ContactsServiceProtocol: Sendable {
    func fetchContacts() async throws -> [CloudContact]
    func searchContacts(query: String) async -> [CloudContact]
    func createContact(name: String, extension: String, phone: String?, department: String?) async throws -> CloudContact
}

/// Production cloud directory contacts service connecting to the Laravel REST API.
public final class ContactsService: ContactsServiceProtocol, @unchecked Sendable {
    public static let shared = ContactsService()
    
    private let session: URLSession
    private let baseUrl: URL
    private let keychain: KeychainManager
    private var cachedContacts: [CloudContact] = []
    
    private let tokenKey = "merosip.auth.jwt"
    
    public init(
        baseUrl: URL = AppConfig.defaultBaseURL,
        session: URLSession = .shared,
        keychain: KeychainManager = .shared
    ) {
        self.baseUrl = baseUrl
        self.session = session
        self.keychain = keychain
    }
    
    public func fetchContacts() async throws -> [CloudContact] {
        guard let token = keychain.getString(key: tokenKey) else {
            return cachedContacts
        }
        
        let url = baseUrl.appendingPathComponent("contacts")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                struct ContactsResponse: Decodable {
                    let data: [CloudContact]
                }
                let decoded = try decoder.decode(ContactsResponse.self, from: data)
                self.cachedContacts = decoded.data
                return decoded.data
            }
        } catch {
            print("Failed to fetch remote contacts: \(error)")
        }
        
        return cachedContacts
    }
    
    public func searchContacts(query: String) async -> [CloudContact] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (try? await fetchContacts()) ?? cachedContacts
        }
        
        guard let token = keychain.getString(key: tokenKey),
              var components = URLComponents(url: baseUrl.appendingPathComponent("contacts/search"), resolvingAgainstBaseURL: true) else {
            return cachedContacts.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.sipExtension.contains(trimmed)
            }
        }
        
        components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        guard let url = components.url else { return cachedContacts }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                struct ContactsResponse: Decodable {
                    let data: [CloudContact]
                }
                let decoded = try decoder.decode(ContactsResponse.self, from: data)
                return decoded.data
            }
        } catch {
            print("Failed to search remote contacts: \(error)")
        }
        
        return cachedContacts.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
            $0.sipExtension.contains(trimmed)
        }
    }
    
    public func createContact(name: String, extension: String, phone: String?, department: String?) async throws -> CloudContact {
        guard let token = keychain.getString(key: tokenKey) else {
            throw AuthError.unauthenticated
        }
        
        let url = baseUrl.appendingPathComponent("contacts")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let payload: [String: Any] = [
            "name": name,
            "sip_extension": `extension`,
            "direct_phone": phone ?? "",
            "department": department ?? "",
            "is_favorite": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 201) else {
            throw AuthError.serverError("Failed to save contact (HTTP \(response as? HTTPURLResponse != nil ? String((response as! HTTPURLResponse).statusCode) : "Unknown")).")
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        struct SingleContactResponse: Decodable {
            let data: CloudContact
        }
        let decoded = try decoder.decode(SingleContactResponse.self, from: data)
        self.cachedContacts.append(decoded.data)
        return decoded.data
    }
}
