import Foundation

/// Delegate protocol for receiving SIP engine lifecycle and call events.
@MainActor
public protocol SIPServiceDelegate: AnyObject {
    func sipService(_ service: any SIPServiceProtocol, didChangeRegistrationState state: RegistrationState)
    func sipService(_ service: any SIPServiceProtocol, didReceiveIncomingCall session: CallSession)
    func sipService(_ service: any SIPServiceProtocol, didUpdateCallSession session: CallSession)
    func sipService(_ service: any SIPServiceProtocol, didTerminateCallSession session: CallSession, reason: DisconnectReason)
}

/// Abstract interface for the underlying SIP stack (PJSIP / Mock / C++ bridge).
@MainActor
public protocol SIPServiceProtocol: AnyObject {
    var delegate: (any SIPServiceDelegate)? { get set }
    var registrationState: RegistrationState { get }
    var activeSession: CallSession? { get }
    
    func start(account: SIPAccount) async throws
    func stop() async
    
    func makeCall(destination: String, displayName: String) async throws -> CallSession
    func answerCall(callId: Int32) async throws
    func hangupCall(callId: Int32) async
    func declineCall(callId: Int32) async
    
    func setMute(_ muted: Bool, callId: Int32) async
    func setHold(_ onHold: Bool, callId: Int32) async
    func sendDTMF(digit: String, callId: Int32) async
    
    func transferCall(type: TransferType, callId: Int32) async throws
}
