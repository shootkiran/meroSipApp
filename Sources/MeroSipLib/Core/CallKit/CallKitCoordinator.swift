import Foundation
#if canImport(CallKit) && os(iOS)
import CallKit
#endif

/// Protocol for notifying call manager of actions triggered from CallKit / Lock screen.
@MainActor
public protocol CallKitActionDelegate: AnyObject {
    func callKitDidAnswerCall(uuid: UUID)
    func callKitDidEndCall(uuid: UUID)
    func callKitDidSetMute(uuid: UUID, muted: Bool)
    func callKitDidSetHold(uuid: UUID, onHold: Bool)
}

/// Coordinates system CallKit integration on iOS with safe fallback on macOS.
@MainActor
public final class CallKitCoordinator: NSObject, ObservableObject {
    public static let shared = CallKitCoordinator()
    
    public weak var actionDelegate: (any CallKitActionDelegate)?
    
    #if canImport(CallKit) && os(iOS)
    private var provider: CXProvider?
    private let callController = CXCallController()
    #endif
    
    override private init() {
        super.init()
        #if canImport(CallKit) && os(iOS)
        setupCallKitProvider()
        #endif
    }
    
    #if canImport(CallKit) && os(iOS)
    private func setupCallKitProvider() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = false
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic, .phoneNumber]
        configuration.iconTemplateImageData = nil
        
        let provider = CXProvider(configuration: configuration)
        provider.setDelegate(self, queue: nil)
        self.provider = provider
    }
    #endif
    
    public func reportIncomingCall(uuid: UUID, handle: String, displayName: String, completion: @escaping (Error?) -> Void) {
        #if canImport(CallKit) && os(iOS)
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: handle)
        update.localizedCallerName = displayName.isEmpty ? handle : displayName
        update.hasVideo = false
        update.supportsHolding = true
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = true
        
        provider?.reportNewIncomingCall(with: uuid, update: update, completion: completion)
        #else
        completion(nil)
        #endif
    }
    
    public func startOutgoingCall(uuid: UUID, handle: String, displayName: String) {
        #if canImport(CallKit) && os(iOS)
        let cxHandle = CXHandle(type: .generic, value: handle)
        let action = CXStartCallAction(call: uuid, handle: cxHandle)
        action.isVideo = false
        let transaction = CXTransaction(action: action)
        callController.request(transaction) { error in
            if let error = error {
                print("CallKit Start Call error: \(error)")
            }
        }
        #endif
    }
    
    public func reportCallConnected(uuid: UUID) {
        #if canImport(CallKit) && os(iOS)
        provider?.reportOutgoingCall(with: uuid, connectedAt: Date())
        #endif
    }
    
    public func endCall(uuid: UUID) {
        #if canImport(CallKit) && os(iOS)
        let action = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: action)
        callController.request(transaction) { _ in }
        #endif
    }
}

#if canImport(CallKit) && os(iOS)
extension CallKitCoordinator: CXProviderDelegate {
    public func providerDidReset(_ provider: CXProvider) {}
    
    public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        actionDelegate?.callKitDidAnswerCall(uuid: action.callUUID)
        action.fulfill()
    }
    
    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        actionDelegate?.callKitDidEndCall(uuid: action.callUUID)
        action.fulfill()
    }
    
    public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        actionDelegate?.callKitDidSetMute(uuid: action.callUUID, muted: action.isMuted)
        action.fulfill()
    }
    
    public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        actionDelegate?.callKitDidSetHold(uuid: action.callUUID, onHold: action.isOnHold)
        action.fulfill()
    }
}
#endif
