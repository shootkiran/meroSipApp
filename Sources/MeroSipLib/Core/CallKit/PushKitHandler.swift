import Foundation
#if canImport(PushKit) && os(iOS)
import PushKit
#endif

/// Handles Apple PushKit VoIP background push registrations and notifications.
@MainActor
public final class PushKitHandler: NSObject, ObservableObject {
    public static let shared = PushKitHandler()
    
    @Published public private(set) var voipToken: String?
    
    #if canImport(PushKit) && os(iOS)
    private var voipRegistry: PKPushRegistry?
    #endif
    
    override private init() {
        super.init()
    }
    
    public func registerForVoIPPush() {
        #if canImport(PushKit) && os(iOS)
        voipRegistry = PKPushRegistry(queue: .main)
        voipRegistry?.delegate = self
        voipRegistry?.desiredPushTypes = [.voIP]
        #endif
    }
}

#if canImport(PushKit) && os(iOS)
extension PushKitHandler: PKPushRegistryDelegate {
    public func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let token = pushCredentials.token.map { String(format: "%02.2hhx", $0) }.joined()
        self.voipToken = token
        print("Received VoIP Push Token: \(token)")
    }
    
    public func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        // Extract caller payload & immediately report to CallKit
        let dictionary = payload.dictionaryPayload
        let callerUri = dictionary["caller_uri"] as? String ?? "Unknown"
        let callerName = dictionary["caller_name"] as? String ?? callerUri
        let uuid = UUID()
        
        CallKitCoordinator.shared.reportIncomingCall(uuid: uuid, handle: callerUri, displayName: callerName) { error in
            completion()
        }
    }
    
    public func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        self.voipToken = nil
    }
}
#endif
