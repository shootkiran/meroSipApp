import Foundation
import Combine

/// Central observable manager coordinating telephony, SIP signaling, CallKit, and call logs.
@MainActor
public final class CallManager: ObservableObject {
    public static let shared = CallManager()
    
    // MARK: - Published Properties
    
    @Published public private(set) var activeCall: CallSession?
    @Published public private(set) var registrationState: RegistrationState = .unconfigured
    @Published public private(set) var provisionedAccount: SIPAccount?
    @Published public private(set) var currentUser: AuthUser?
    @Published public var errorMessage: String?
    
    // MARK: - Dependencies
    
    public var sipService: any SIPServiceProtocol
    public let historyRepo: CallHistoryRepository
    public let audioRouteManager: AudioRouteManager
    public let callKitCoordinator: CallKitCoordinator
    
    public init(
        sipService: any SIPServiceProtocol = RealSIPEngine(),
        historyRepo: CallHistoryRepository = .shared,
        audioRouteManager: AudioRouteManager = .shared,
        callKitCoordinator: CallKitCoordinator = .shared
    ) {
        self.sipService = sipService
        self.historyRepo = historyRepo
        self.audioRouteManager = audioRouteManager
        self.callKitCoordinator = callKitCoordinator
        
        self.sipService.delegate = self
        self.callKitCoordinator.actionDelegate = self
    }
    
    // MARK: - Account Registration & Provisioning
    
    public func configure(with response: ProvisioningResponse) async {
        self.currentUser = response.user
        self.provisionedAccount = response.sipAccount
        
        do {
            try await sipService.start(account: response.sipAccount)
            await historyRepo.fetchRemoteHistory()
        } catch {
            self.errorMessage = "SIP registration failed: \(error.localizedDescription)"
        }
    }
    
    public func unregister() async {
        await sipService.stop()
        self.currentUser = nil
        self.provisionedAccount = nil
        self.activeCall = nil
    }
    
    // MARK: - Outgoing & Incoming Call Actions
    
    public func startCall(to destination: String, displayName: String = "") {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        Task {
            do {
                let session = try await sipService.makeCall(destination: trimmed, displayName: displayName)
                self.activeCall = session
                callKitCoordinator.startOutgoingCall(uuid: session.id, handle: trimmed, displayName: session.remoteDisplayName)
            } catch {
                self.errorMessage = "Failed to start call: \(error.localizedDescription)"
            }
        }
    }
    
    public func answerCall() {
        guard let call = activeCall else { return }
        Task {
            do {
                try await sipService.answerCall(callId: call.callId)
                callKitCoordinator.reportCallConnected(uuid: call.id)
            } catch {
                self.errorMessage = "Failed to answer call: \(error.localizedDescription)"
            }
        }
    }
    
    public func endCall() {
        guard let call = activeCall else { return }
        Task {
            await sipService.hangupCall(callId: call.callId)
            callKitCoordinator.endCall(uuid: call.id)
            self.activeCall = nil
        }
    }
    
    public func declineCall() {
        guard let call = activeCall else { return }
        Task {
            await sipService.declineCall(callId: call.callId)
            callKitCoordinator.endCall(uuid: call.id)
            self.activeCall = nil
        }
    }
    
    public func toggleMute() {
        guard var call = activeCall else { return }
        let newMute = !call.isMuted
        call.isMuted = newMute
        self.activeCall = call
        Task {
            await sipService.setMute(newMute, callId: call.callId)
        }
    }
    
    public func toggleHold() {
        guard var call = activeCall else { return }
        let newHold = !call.isOnHold
        call.isOnHold = newHold
        call.state = newHold ? .holding : .connected(duration: call.duration)
        self.activeCall = call
        Task {
            await sipService.setHold(newHold, callId: call.callId)
        }
    }
    
    public func sendDTMF(_ digit: String) {
        guard let call = activeCall else { return }
        Task {
            await sipService.sendDTMF(digit: digit, callId: call.callId)
        }
    }
    
    public func transferCall(to targetUri: String) {
        guard let call = activeCall else { return }
        Task {
            do {
                try await sipService.transferCall(type: .blind(targetUri: targetUri), callId: call.callId)
            } catch {
                self.errorMessage = "Transfer failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - SIPServiceDelegate

extension CallManager: SIPServiceDelegate {
    public func sipService(_ service: any SIPServiceProtocol, didChangeRegistrationState state: RegistrationState) {
        self.registrationState = state
    }
    
    public func sipService(_ service: any SIPServiceProtocol, didReceiveIncomingCall session: CallSession) {
        self.activeCall = session
        callKitCoordinator.reportIncomingCall(uuid: session.id, handle: session.remoteUri, displayName: session.remoteDisplayName) { _ in }
    }
    
    public func sipService(_ service: any SIPServiceProtocol, didUpdateCallSession session: CallSession) {
        self.activeCall = session
    }
    
    public func sipService(_ service: any SIPServiceProtocol, didTerminateCallSession session: CallSession, reason: DisconnectReason) {
        let isMissed = (session.direction == .incoming && session.connectTime == nil)
        historyRepo.addRecord(
            remoteUri: session.remoteUri,
            remoteDisplayName: session.remoteDisplayName,
            direction: session.direction,
            duration: session.duration,
            isMissed: isMissed
        )
        self.activeCall = nil
    }
}

// MARK: - CallKitActionDelegate

extension CallManager: CallKitActionDelegate {
    public func callKitDidAnswerCall(uuid: UUID) {
        answerCall()
    }
    
    public func callKitDidEndCall(uuid: UUID) {
        endCall()
    }
    
    public func callKitDidSetMute(uuid: UUID, muted: Bool) {
        if activeCall?.isMuted != muted {
            toggleMute()
        }
    }
    
    public func callKitDidSetHold(uuid: UUID, onHold: Bool) {
        if activeCall?.isOnHold != onHold {
            toggleHold()
        }
    }
}
