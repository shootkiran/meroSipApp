import Foundation
import Combine

/// Global Dependency Injection Container for MeroSip.
@MainActor
public final class AppEnvironment: ObservableObject {
    public static let shared = AppEnvironment()
    
    public let callManager: CallManager
    public let authService: AuthService
    public let contactsService: ContactsService
    public let historyRepo: CallHistoryRepository
    
    public init(
        callManager: CallManager = .shared,
        authService: AuthService = .shared,
        contactsService: ContactsService = .shared,
        historyRepo: CallHistoryRepository = .shared
    ) {
        self.callManager = callManager
        self.authService = authService
        self.contactsService = contactsService
        self.historyRepo = historyRepo
    }
    
    public func bootstrap() async {
        // Attempt to restore prior user session
        if let session = await authService.restoreSession() {
            await callManager.configure(with: session)
        }
    }
}
