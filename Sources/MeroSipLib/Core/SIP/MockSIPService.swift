import Foundation

/// High-fidelity simulated SIP service for testing, UI previews, and standalone operation.
@MainActor
public final class MockSIPService: SIPServiceProtocol {
    public weak var delegate: (any SIPServiceDelegate)?
    
    public private(set) var registrationState: RegistrationState = .unconfigured
    public private(set) var activeSession: CallSession?
    
    private var account: SIPAccount?
    private var timerTask: Task<Void, Never>?
    private var currentCallCounter: Int32 = 100
    
    public init() {}
    
    public func start(account: SIPAccount) async throws {
        self.account = account
        updateRegistrationState(.registering)
        
        try? await Task.sleep(nanoseconds: 300_000_000)
        updateRegistrationState(.registered)
    }
    
    public func stop() async {
        timerTask?.cancel()
        timerTask = nil
        self.activeSession = nil
        updateRegistrationState(.unregistered)
    }
    
    public func makeCall(destination: String, displayName: String) async throws -> CallSession {
        currentCallCounter += 1
        let callId = currentCallCounter
        
        let session = CallSession(
            callId: callId,
            remoteUri: destination,
            remoteDisplayName: displayName.isEmpty ? destination : displayName,
            direction: .outgoing,
            state: .dialing(destination: destination),
            startTime: Date()
        )
        
        self.activeSession = session
        notifySessionUpdated(session)
        
        // Simulate call lifecycle: dialing -> ringing -> connected
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard var current = self.activeSession, current.callId == callId else { return }
            
            current.state = .ringing(isIncoming: false)
            self.activeSession = current
            self.notifySessionUpdated(current)
            
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard var liveSession = self.activeSession, liveSession.callId == callId else { return }
            
            liveSession.state = .connected(duration: 0)
            liveSession.connectTime = Date()
            self.activeSession = liveSession
            self.notifySessionUpdated(liveSession)
            self.startDurationTicker(callId: callId)
        }
        
        return session
    }
    
    public func answerCall(callId: Int32) async throws {
        guard var session = activeSession, session.callId == callId else { return }
        session.state = .connected(duration: 0)
        session.connectTime = Date()
        self.activeSession = session
        notifySessionUpdated(session)
        startDurationTicker(callId: callId)
    }
    
    public func hangupCall(callId: Int32) async {
        timerTask?.cancel()
        timerTask = nil
        guard let session = activeSession, session.callId == callId else { return }
        self.activeSession = nil
        notifySessionTerminated(session, reason: .normal)
    }
    
    public func declineCall(callId: Int32) async {
        guard let session = activeSession, session.callId == callId else { return }
        self.activeSession = nil
        notifySessionTerminated(session, reason: .declined)
    }
    
    public func setMute(_ muted: Bool, callId: Int32) async {
        guard var session = activeSession, session.callId == callId else { return }
        session.isMuted = muted
        self.activeSession = session
        notifySessionUpdated(session)
    }
    
    public func setHold(_ onHold: Bool, callId: Int32) async {
        guard var session = activeSession, session.callId == callId else { return }
        session.isOnHold = onHold
        session.state = onHold ? .holding : .connected(duration: session.duration)
        self.activeSession = session
        notifySessionUpdated(session)
    }
    
    public func sendDTMF(digit: String, callId: Int32) async {
        // Mock tone playback / SIP INFO RFC 2833
    }
    
    public func transferCall(type: TransferType, callId: Int32) async throws {
        guard var session = activeSession, session.callId == callId else { return }
        let targetDescription: String
        switch type {
        case .blind(let uri):
            targetDescription = uri
        case .attended(let id):
            targetDescription = "Call #\(id)"
        }
        
        session.state = .transferring(target: targetDescription)
        self.activeSession = session
        notifySessionUpdated(session)
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await self.hangupCall(callId: callId)
        }
    }
    
    /// Trigger an incoming call simulation for testing UI and CallKit.
    public func simulateIncomingCall(from uri: String = "1001", displayName: String = "Alice Johnson") {
        currentCallCounter += 1
        let callId = currentCallCounter
        let session = CallSession(
            callId: callId,
            remoteUri: uri,
            remoteDisplayName: displayName,
            direction: .incoming,
            state: .ringing(isIncoming: true),
            startTime: Date()
        )
        self.activeSession = session
        self.delegate?.sipService(self, didReceiveIncomingCall: session)
    }
    
    // MARK: - Private Helpers
    
    private func startDurationTicker(callId: Int32) {
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self = self, var session = self.activeSession, session.callId == callId, !session.isOnHold else {
                    break
                }
                session.state = .connected(duration: session.duration)
                self.activeSession = session
                self.notifySessionUpdated(session)
            }
        }
    }
    
    private func updateRegistrationState(_ state: RegistrationState) {
        self.registrationState = state
        self.delegate?.sipService(self, didChangeRegistrationState: state)
    }
    
    private func notifySessionUpdated(_ session: CallSession) {
        self.delegate?.sipService(self, didUpdateCallSession: session)
    }
    
    private func notifySessionTerminated(_ session: CallSession, reason: DisconnectReason) {
        self.delegate?.sipService(self, didTerminateCallSession: session, reason: reason)
    }
}
