import Foundation

/// Repository for persisting real call history logs and synchronizing with backend CDR.
@MainActor
public final class CallHistoryRepository: ObservableObject {
    public static let shared = CallHistoryRepository()
    
    @Published public private(set) var callRecords: [CallRecord] = []
    
    private let storageUrl: URL
    private let session = URLSession.shared
    private let baseUrl = URL(string: "http://merosipbackend.test/api/v1")!
    private let keychain = KeychainManager.shared
    private let tokenKey = "merosip.auth.jwt"
    
    public init() {
        let fileManager = FileManager.default
        let folder = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let appDir = folder.appendingPathComponent("MeroSip", isDirectory: true)
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.storageUrl = appDir.appendingPathComponent("call_history.json")
        loadRecords()
    }
    
    public func addRecord(
        remoteUri: String,
        remoteDisplayName: String = "",
        direction: CallDirection,
        duration: TimeInterval,
        isMissed: Bool
    ) {
        let record = CallRecord(
            remoteUri: remoteUri,
            remoteDisplayName: remoteDisplayName,
            direction: direction,
            date: Date(),
            duration: duration,
            isMissed: isMissed
        )
        callRecords.insert(record, at: 0)
        saveRecords()
        
        // Sync record to backend CDR API asynchronously
        Task {
            await syncRecordToBackend(record)
        }
    }
    
    public func deleteRecord(id: UUID) {
        callRecords.removeAll { $0.id == id }
        saveRecords()
    }
    
    public func clearHistory() {
        callRecords.removeAll()
        saveRecords()
    }
    
    public func fetchRemoteHistory() async {
        guard let token = keychain.getString(key: tokenKey) else { return }
        let url = baseUrl.appendingPathComponent("calls")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                struct RemoteCallResponse: Decodable {
                    let data: [RemoteCallRecord]
                }
                struct RemoteCallRecord: Decodable {
                    let remoteUri: String
                    let remoteDisplayName: String?
                    let direction: String
                    let duration: Int
                    let isMissed: Bool
                }
                let decoded = try decoder.decode(RemoteCallResponse.self, from: data)
                let records = decoded.data.map {
                    CallRecord(
                        remoteUri: $0.remoteUri,
                        remoteDisplayName: $0.remoteDisplayName ?? $0.remoteUri,
                        direction: $0.direction == "incoming" ? .incoming : .outgoing,
                        date: Date(),
                        duration: TimeInterval($0.duration),
                        isMissed: $0.isMissed
                    )
                }
                if !records.isEmpty {
                    self.callRecords = records
                    saveRecords()
                }
            }
        } catch {
            print("Failed to sync remote call history: \(error)")
        }
    }
    
    private func syncRecordToBackend(_ record: CallRecord) async {
        guard let token = keychain.getString(key: tokenKey) else { return }
        let url = baseUrl.appendingPathComponent("calls/log")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let payload: [String: Any] = [
            "remote_uri": record.remoteUri,
            "remote_display_name": record.remoteDisplayName,
            "direction": record.direction.rawValue,
            "duration": Int(record.duration),
            "is_missed": record.isMissed,
            "status": record.isMissed ? "missed" : "completed"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        _ = try? await session.data(for: request)
    }
    
    private func loadRecords() {
        guard let data = try? Data(contentsOf: storageUrl) else { return }
        if let decoded = try? JSONDecoder().decode([CallRecord].self, from: data) {
            self.callRecords = decoded
        }
    }
    
    private func saveRecords() {
        guard let data = try? JSONEncoder().encode(callRecords) else { return }
        try? data.write(to: storageUrl, options: .atomic)
    }
}
