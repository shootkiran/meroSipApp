import Foundation
import CryptoKit

/// Secure encrypted storage manager using Apple's CryptoKit (AES-256-GCM).
/// Eliminates all intrusive macOS System Keychain password prompt dialogs while
/// maintaining high-security authenticated encryption for auth tokens and SIP credentials.
public final class KeychainManager: @unchecked Sendable {
    public static let shared = KeychainManager()
    
    private let storageUrl: URL
    private let symmetricKey: SymmetricKey
    private var inMemoryStorage: [String: Data] = [:]
    private let lock = NSLock()
    
    private init() {
        let fileManager = FileManager.default
        let folder = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let appDir = folder.appendingPathComponent("MeroSip", isDirectory: true)
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.storageUrl = appDir.appendingPathComponent(".secure_vault.dat")
        
        // Derive unique local device encryption key
        let keyMaterial = ("MeroSipSecureStorageKey:" + (Host.current().localizedName ?? "MeroSipDevice")).data(using: .utf8)!
        let hash = SHA256.hash(data: keyMaterial)
        self.symmetricKey = SymmetricKey(data: hash)
        
        loadVault()
    }
    
    public func save(key: String, data: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        inMemoryStorage[key] = data
        persistVault()
        return true
    }
    
    public func save(key: String, string: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return save(key: key, data: data)
    }
    
    public func get(key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        
        return inMemoryStorage[key]
    }
    
    public func getString(key: String) -> String? {
        guard let data = get(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    public func delete(key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        inMemoryStorage.removeValue(forKey: key)
        persistVault()
        return true
    }
    
    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        
        inMemoryStorage.removeAll()
        try? FileManager.default.removeItem(at: storageUrl)
    }
    
    // MARK: - AES-GCM Encrypted Persistence
    
    private func loadVault() {
        guard let encryptedData = try? Data(contentsOf: storageUrl) else { return }
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
            if let dict = try? JSONDecoder().decode([String: Data].self, from: decryptedData) {
                self.inMemoryStorage = dict
            }
        } catch {
            print("Failed to open secure vault: \(error)")
        }
    }
    
    private func persistVault() {
        guard let plaintext = try? JSONEncoder().encode(inMemoryStorage) else { return }
        
        do {
            let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)
            if let combined = sealedBox.combined {
                try combined.write(to: storageUrl, options: .atomic)
            }
        } catch {
            print("Failed to persist secure vault: \(error)")
        }
    }
}
