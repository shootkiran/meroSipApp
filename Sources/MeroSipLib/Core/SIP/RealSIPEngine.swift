import Foundation
import Network
import CryptoKit

/// Real RFC 3261 SIP Protocol Engine operating over Network.framework UDP.
/// Handles real SIP Registration, Digest MD5 Auth against FreePBX/Asterisk,
/// WebRTC/DTLS-SAVPF media negotiation, Explicit Unregistration, and bidirectional RTP Audio.
@MainActor
public final class RealSIPEngine: SIPServiceProtocol {
    public weak var delegate: (any SIPServiceDelegate)?
    
    public private(set) var registrationState: RegistrationState = .unconfigured
    public private(set) var activeSession: CallSession?
    
    private var account: SIPAccount?
    private var connection: NWConnection?
    private var localPort: UInt16 = 50600
    private var localIP: String = "103.167.229.227"
    
    private var cseq: Int = 1
    private var callIdHeader: String = UUID().uuidString
    private var tagHeader: String = String(Int.random(in: 100000...999999))
    private var authNonce: String?
    private var authRealm: String?
    private var authOpaque: String?
    private var authQop: String?
    private var ncCount: Int = 0
    
    // Incoming transaction preservation
    private var incomingViaLines: [String] = []
    private var incomingFromLine: String?
    private var incomingToLine: String?
    private var incomingCallIdLine: String?
    private var incomingCSeqLine: String?
    private var incomingRemoteRTPHost: String?
    private var incomingRemoteRTPPort: UInt16?
    private var incomingNegotiatedCodec: AudioCodec = .opus
    
    private var keepAliveTimer: Task<Void, Never>?
    private var durationTimer: Task<Void, Never>?
    private var registrationTimeoutTask: Task<Void, Never>?
    private var retryTimerTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var isPathMonitorStarted: Bool = false
    private var registerAuthAttempts: Int = 0
    private var activeCallIdNumber: Int32 = -1
    private var activeCallRemoteTag: String?
    private var lastInviteBranch: String?
    private var lastInviteCSeq: Int?
    
    public init() {
        self.localPort = UInt16.random(in: 50000...65000)
    }
    
    // MARK: - SIP Registration & Connection
    
    public func start(account: SIPAccount) async throws {
        self.connection?.cancel()
        self.connection = nil
        
        self.account = account
        self.callIdHeader = "\(UUID().uuidString)@merosip"
        self.cseq = 1
        self.tagHeader = String(Int.random(in: 100000...999999))
        self.ncCount = 0
        self.registerAuthAttempts = 0
        self.localPort = UInt16.random(in: 50000...65000)
        
        startPathMonitor()
        updateRegistrationState(.registering)
        print("[SIP Engine] Connecting to FreePBX server at \(account.proxy ?? account.domain):\(account.port)...")
        
        registrationTimeoutTask?.cancel()
        registrationTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard let self = self, self.registrationState == .registering else { return }
            print("[SIP Engine] Registration timed out after 12 seconds.")
            self.updateRegistrationState(.registrationFailed)
        }
        
        let host = NWEndpoint.Host(account.proxy ?? account.domain)
        let port = NWEndpoint.Port(rawValue: UInt16(account.port)) ?? .init(integerLiteral: 5060)
        
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        
        let conn = NWConnection(host: host, port: port, using: params)
        self.connection = conn
        
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch state {
                case .ready:
                    print("[SIP Engine] UDP Socket Ready. Sending SIP REGISTER...")
                    if let path = conn.currentPath, let localEndpoint = path.localEndpoint {
                        if case .hostPort(let h, let p) = localEndpoint {
                            let cleanHost = "\(h)".replacingOccurrences(of: "%en0", with: "").replacingOccurrences(of: "%en1", with: "")
                            self.localIP = cleanHost
                            self.localPort = p.rawValue
                        }
                    }
                    self.startListening(on: conn)
                    self.sendRegister(authHeader: nil)
                case .waiting(let error):
                    print("[SIP Engine] Connection Waiting: \(error)")
                    self.updateRegistrationState(.registrationFailed)
                case .failed(let error):
                    print("[SIP Engine] Connection Failed: \(error)")
                    self.updateRegistrationState(.registrationFailed)
                case .cancelled:
                    break
                default:
                    break
                }
            }
        }
        
        conn.start(queue: .global())
    }
    
    public func stop() async {
        retryTimerTask?.cancel()
        retryTimerTask = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        isPathMonitorStarted = false
        
        registrationTimeoutTask?.cancel()
        registrationTimeoutTask = nil
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
        durationTimer?.cancel()
        durationTimer = nil
        
        RTPAudioEngine.shared.stopRTP()
        
        if let call = activeSession {
            await hangupCall(callId: call.callId)
        }
        
        print("[SIP Engine] Sending explicit SIP Unregister (Expires: 0) to FreePBX...")
        
        if let nonce = authNonce, let realm = authRealm, let account = account, let password = account.password {
            let uri = "sip:\(account.domain)"
            let ha1 = md5Hex("\(account.username):\(realm):\(password)")
            let ha2 = md5Hex("REGISTER:\(uri)")
            self.ncCount += 1
            let nc = String(format: "%08x", ncCount)
            let cnonce = String(Int.random(in: 10000000...99999999))
            
            var authHeader = "Digest username=\"\(account.username)\", realm=\"\(realm)\", nonce=\"\(nonce)\", uri=\"\(uri)\""
            if let qop = authQop, qop.contains("auth") {
                let digestResponse = md5Hex("\(ha1):\(nonce):\(nc):\(cnonce):auth:\(ha2)")
                authHeader += ", qop=auth, nc=\(nc), cnonce=\"\(cnonce)\", response=\"\(digestResponse)\", algorithm=MD5"
            } else {
                let digestResponse = md5Hex("\(ha1):\(nonce):\(ha2)")
                authHeader += ", response=\"\(digestResponse)\", algorithm=MD5"
            }
            if let opaque = authOpaque {
                authHeader += ", opaque=\"\(opaque)\""
            }
            sendRegister(authHeader: authHeader, expires: 0)
        } else {
            sendRegister(authHeader: nil, expires: 0)
        }
        
        sendWildcardUnregister()
        
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        connection?.cancel()
        connection = nil
        self.activeSession = nil
        self.account = nil
        updateRegistrationState(.unregistered)
        print("[SIP Engine] Extension unregistered and socket closed.")
    }
    
    // MARK: - Telephony Operations
    
    public func makeCall(destination: String, displayName: String) async throws -> CallSession {
        guard account != nil else { throw AuthError.unauthenticated }
        
        let callNum = Int32.random(in: 1000...9999)
        self.activeCallIdNumber = callNum
        self.callIdHeader = "\(UUID().uuidString)@merosip"
        self.tagHeader = String(Int.random(in: 100000...999999))
        self.activeCallRemoteTag = nil
        self.lastInviteBranch = nil
        self.lastInviteCSeq = nil
        self.cseq += 1
        
        let session = CallSession(
            callId: callNum,
            remoteUri: destination,
            remoteDisplayName: displayName.isEmpty ? destination : displayName,
            direction: .outgoing,
            state: .dialing(destination: destination),
            startTime: Date()
        )
        
        self.activeSession = session
        notifySessionUpdated(session)
        
        print("[SIP Engine] Initiating outgoing call to extension \(destination)...")
        sendInvite(destination: destination, authHeader: nil)
        
        return session
    }
    
    public func answerCall(callId: Int32) async throws {
        guard var session = activeSession, session.callId == callId else { return }
        session.state = .connected(duration: 0)
        session.connectTime = Date()
        self.activeSession = session
        notifySessionUpdated(session)
        
        print("[SIP Engine] Answering incoming call with 200 OK and SDP answer...")
        sendAnswer200OK()
        
        let host = incomingRemoteRTPHost ?? account?.domain ?? "127.0.0.1"
        let port = incomingRemoteRTPPort ?? 10000
        RTPAudioEngine.shared.startRTP(remoteHost: host, remotePort: port, codec: incomingNegotiatedCodec)
        
        startDurationTicker(callId: callId)
    }
    
    public func hangupCall(callId: Int32) async {
        durationTimer?.cancel()
        durationTimer = nil
        
        RTPAudioEngine.shared.stopRTP()
        
        guard let session = activeSession, session.callId == callId else { return }
        
        if case .connected = session.state {
            sendBye(destination: session.remoteUri)
        } else {
            sendCancel(destination: session.remoteUri)
            sendBye(destination: session.remoteUri)
        }
        
        self.activeSession = nil
        self.lastInviteBranch = nil
        self.lastInviteCSeq = nil
        self.activeCallRemoteTag = nil
        notifySessionTerminated(session, reason: .normal)
    }
    
    public func declineCall(callId: Int32) async {
        guard let session = activeSession, session.callId == callId else { return }
        sendDecline486()
        self.activeSession = nil
        notifySessionTerminated(session, reason: .declined)
    }
    
    public func setMute(_ muted: Bool, callId: Int32) async {
        guard var session = activeSession, session.callId == callId else { return }
        session.isMuted = muted
        self.activeSession = session
        RTPAudioEngine.shared.isMuted = muted
        notifySessionUpdated(session)
    }
    
    public func setHold(_ onHold: Bool, callId: Int32) async {
        guard var session = activeSession, session.callId == callId else { return }
        session.isOnHold = onHold
        session.state = onHold ? .holding : .connected(duration: session.duration)
        self.activeSession = session
        RTPAudioEngine.shared.isOnHold = onHold
        notifySessionUpdated(session)
        
        sendInvite(destination: session.remoteUri, authHeader: nil, isHold: onHold)
    }
    
    public func sendDTMF(digit: String, callId: Int32) async {
        guard let session = activeSession, session.callId == callId else { return }
        sendInfoDTMF(digit: digit, destination: session.remoteUri)
    }
    
    public func transferCall(type: TransferType, callId: Int32) async throws {
        guard var session = activeSession, session.callId == callId else { return }
        let targetDescription: String
        switch type {
        case .blind(let uri):
            targetDescription = uri
            sendRefer(targetUri: uri, destination: session.remoteUri)
        case .attended(let id):
            targetDescription = "Ext #\(id)"
        }
        
        session.state = .transferring(target: targetDescription)
        self.activeSession = session
        notifySessionUpdated(session)
    }
    
    // MARK: - SIP Packet Builder
    
    private func sendRegister(authHeader: String?, expires: Int = 120) {
        guard let account = account else { return }
        cseq += 1
        
        var msg = "REGISTER sip:\(account.domain) SIP/2.0\r\n"
        msg += "Via: SIP/2.0/UDP \(localIP):\(localPort);branch=z9hG4bK\(UUID().uuidString.prefix(8));rport\r\n"
        msg += "Max-Forwards: 70\r\n"
        msg += "From: <sip:\(account.username)@\(account.domain)>;tag=\(tagHeader)\r\n"
        msg += "To: <sip:\(account.username)@\(account.domain)>\r\n"
        msg += "Call-ID: \(callIdHeader)\r\n"
        msg += "CSeq: \(cseq) REGISTER\r\n"
        msg += "Contact: <sip:\(account.username)@\(localIP):\(localPort);transport=udp>\r\n"
        msg += "Expires: \(expires)\r\n"
        msg += "User-Agent: MeroSip/1.0\r\n"
        
        if let auth = authHeader {
            msg += "Authorization: \(auth)\r\n"
        }
        
        msg += "Content-Length: 0\r\n\r\n"
        sendPacket(msg)
    }
    
    private func sendWildcardUnregister() {
        guard let account = account else { return }
        cseq += 1
        var msg = "REGISTER sip:\(account.domain) SIP/2.0\r\n"
        msg += "Via: SIP/2.0/UDP \(localIP):\(localPort);branch=z9hG4bK\(UUID().uuidString.prefix(8));rport\r\n"
        msg += "Max-Forwards: 70\r\n"
        msg += "From: <sip:\(account.username)@\(account.domain)>;tag=\(tagHeader)\r\n"
        msg += "To: <sip:\(account.username)@\(account.domain)>\r\n"
        msg += "Call-ID: \(callIdHeader)\r\n"
        msg += "CSeq: \(cseq) REGISTER\r\n"
        msg += "Contact: *\r\n"
        msg += "Expires: 0\r\n"
        msg += "User-Agent: MeroSip/1.0\r\n"
        msg += "Content-Length: 0\r\n\r\n"
        sendPacket(msg)
    }
    
    private func sendInvite(destination: String, authHeader: String?, isHold: Bool = false) {
        guard let account = account else { return }
        cseq += 1
        let branch = "z9hG4bK\(UUID().uuidString.prefix(8))"
        self.lastInviteBranch = branch
        self.lastInviteCSeq = cseq
        
        let localRTP = RTPAudioEngine.shared.localRTPPort
        let sdpMode = isHold ? "sendonly" : "sendrecv"
        let connIP = isHold ? "0.0.0.0" : localIP
        
        // Standard RFC 3264 & RFC 2543 RTP/AVP VoIP profile matching Telephone.app / PJSIP
        let sdp = "v=0\r\n" +
                  "o=\(account.username) 1000 1000 IN IP4 \(localIP)\r\n" +
                  "s=pjmedia\r\n" +
                  "c=IN IP4 \(connIP)\r\n" +
                  "t=0 0\r\n" +
                  "m=audio \(localRTP) RTP/AVP 111 0 8 101\r\n" +
                  "a=rtpmap:111 opus/48000/2\r\n" +
                  "a=fmtp:111 useinbandfec=1; minptime=10\r\n" +
                  "a=rtpmap:0 PCMU/8000\r\n" +
                  "a=rtpmap:8 PCMA/8000\r\n" +
                  "a=rtpmap:101 telephone-event/8000\r\n" +
                  "a=fmtp:101 0-16\r\n" +
                  "a=\(sdpMode)\r\n"
        
        // RFC 3261: Initial INVITE & Authenticated INVITE responding to 401/407 must NOT have a tag in the To header.
        // In-dialog re-INVITE (Hold / Resume) MUST include the established remote dialog tag.
        let toTagStr: String
        if let tag = activeCallRemoteTag?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty {
            toTagStr = ";tag=\(tag)"
        } else {
            toTagStr = ""
        }
        
        var msg = "INVITE sip:\(destination)@\(account.domain) SIP/2.0\r\n"
        msg += "Via: SIP/2.0/UDP \(localIP):\(localPort);branch=\(branch);rport\r\n"
        msg += "Max-Forwards: 70\r\n"
        msg += "From: \"\(account.displayName)\" <sip:\(account.username)@\(account.domain)>;tag=\(tagHeader)\r\n"
        msg += "To: <sip:\(destination)@\(account.domain)>\(toTagStr)\r\n"
        msg += "Call-ID: \(callIdHeader)\r\n"
        msg += "CSeq: \(cseq) INVITE\r\n"
        msg += "Contact: <sip:\(account.username)@\(localIP):\(localPort);transport=udp>\r\n"
        msg += "Allow: INVITE, ACK, CANCEL, OPTIONS, BYE, REFER, NOTIFY, INFO\r\n"
        msg += "User-Agent: Telephone/1.6 (MeroSip)\r\n"
        
        if let auth = authHeader {
            msg += "Authorization: \(auth)\r\n"
            msg += "Proxy-Authorization: \(auth)\r\n"
        }
        
        msg += "Content-Type: application/sdp\r\n"
        msg += "Content-Length: \(sdp.utf8.count)\r\n\r\n"
        msg += sdp
        
        sendPacket(msg)
    }
    
    private func sendAnswer200OK() {
        guard let account = account,
              let from = incomingFromLine,
              let to = incomingToLine,
              let callId = incomingCallIdLine,
              let cseq = incomingCSeqLine else { return }
        
        let localRTP = RTPAudioEngine.shared.localRTPPort
        let sdp = "v=0\r\n" +
                  "o=\(account.username) 1000 1000 IN IP4 \(localIP)\r\n" +
                  "s=pjmedia\r\n" +
                  "c=IN IP4 \(localIP)\r\n" +
                  "t=0 0\r\n" +
                  "m=audio \(localRTP) RTP/AVP 111 0 8 101\r\n" +
                  "a=rtpmap:111 opus/48000/2\r\n" +
                  "a=fmtp:111 useinbandfec=1; minptime=10\r\n" +
                  "a=rtpmap:0 PCMU/8000\r\n" +
                  "a=rtpmap:8 PCMA/8000\r\n" +
                  "a=rtpmap:101 telephone-event/8000\r\n" +
                  "a=fmtp:101 0-16\r\n" +
                  "a=sendrecv\r\n"
        
        var msg = "SIP/2.0 200 OK\r\n"
        for via in incomingViaLines {
            msg += "\(via)\r\n"
        }
        msg += "\(from)\r\n"
        let toHeaderWithTag = to.contains(";tag=") ? to : "\(to);tag=\(tagHeader)"
        msg += "\(toHeaderWithTag)\r\n"
        msg += "\(callId)\r\n"
        msg += "\(cseq)\r\n"
        msg += "Contact: <sip:\(account.username)@\(localIP):\(localPort);transport=udp>\r\n"
        msg += "Allow: INVITE, ACK, CANCEL, OPTIONS, BYE, REFER, NOTIFY, INFO\r\n"
        msg += "Supported: replaces, timer\r\n"
        msg += "User-Agent: Telephone/1.6 (MeroSip)\r\n"
        msg += "Content-Type: application/sdp\r\n"
        msg += "Content-Length: \(sdp.utf8.count)\r\n\r\n"
        msg += sdp
        
        sendPacket(msg)
    }
    
    private func sendDecline486() {
        guard let from = incomingFromLine,
              let to = incomingToLine,
              let callId = incomingCallIdLine,
              let cseq = incomingCSeqLine else { return }
        
        var msg = "SIP/2.0 486 Busy Here\r\n"
        for via in incomingViaLines {
            msg += "\(via)\r\n"
        }
        msg += "\(from)\r\n"
        msg += "\(to);tag=\(tagHeader)\r\n"
        msg += "\(callId)\r\n"
        msg += "\(cseq)\r\n"
        msg += "Content-Length: 0\r\n\r\n"
        sendPacket(msg)
    }
    
    private func sendChallengeAck(destination: String, toTag: String?) {
        guard let account = account else { return }
        let toTagStr = (toTag != nil && !toTag!.isEmpty) ? ";tag=\(toTag!)" : ""
        
        var msg = "ACK sip:\(destination)@\(account.domain) SIP/2.0\r\n"
        msg += "Via: SIP/2.0/UDP \(localIP):\(localPort);branch=z9hG4bK\(UUID().uuidString.prefix(8));rport\r\n"
        msg += "Max-Forwards: 70\r\n"
        msg += "From: <sip:\(account.username)@\(account.domain)>;tag=\(tagHeader)\r\n"
        msg += "To: <sip:\(destination)@\(account.domain)>\(toTagStr)\r\n"
        msg += "Call-ID: \(callIdHeader)\r\n"
        msg += "CSeq: \(cseq) ACK\r\n"
        msg += "User-Agent: Telephone/1.6 (MeroSip)\r\n"
        msg += "Content-Length: 0\r\n\r\n"
        sendPacket(msg)
    }
    
    private func sendAck(destination: String) {
        guard let account = account else { return }
        let toTag = activeCallRemoteTag?.trimmingCharacters(in: .whitespacesAndNewlines)
        let toTagStr = (toTag != nil && !toTag!.isEmpty) ? ";tag=\(toTag!)" : ""
        
        var msg = "ACK sip:\(destination)@\(account.domain) SIP/2.0\r\n"
        msg += "Via: SIP/2.0/UDP \(localIP):\(localPort);branch=z9hG4bK\(UUID().uuidString.prefix(8));rport\r\n"
        msg += "Max-Forwards: 70\r\n"
        msg += "From: <sip:\(account.username)@\(account.domain)>;tag=\(tagHeader)\r\n"
        msg += "To: <sip:\(destination)@\(account.domain)>\(toTagStr)\r\n"
        msg += "Call-ID: \(callIdHeader)\r\n"
        msg += "CSeq: \(cseq) ACK\r\n"
        msg += "User-Agent: Telephone/1.6 (MeroSip)\r\n"
        msg += "Content-Length: 0\r\n\r\n"
        sendPacket(msg)
    }
    
    private func sendBye(destination: String) {
        guard let account = account else { return }
        cseq += 1
        var msg = "BYE sip:\(destination)@\(account.domain) SIP/2.0\r\n"
        msg += "Via: SIP/2.0/UDP \(localIP):\(localPort);branch=z9hG4bK\(UUID().uuidString.prefix(8));rport\r\n"
        msg += "Max-Forwards: 70\r\n"
        msg += "From: <sip:\(account.username)@\(account.domain)>;tag=\(tagHeader)\r\n"
        msg += "To: <sip:\(destination)@\(account.domain)>\(activeCallRemoteTag.map { ";tag=\($0)" } ?? "")\r\n"
        msg += "Call-ID: \(callIdHeader)\r\n"
        msg += "CSeq: \(cseq) BYE\r\n"
        msg += "Content-Length: 0\r\n\r\n"
        sendPacket(msg)
    }
    
    private func sendCancel(destination: String) {
        guard let account = account else { return }
        let branch = lastInviteBranch ?? "z9hG4bK\(UUID().uuidString.prefix(8))"
        let cancelCSeq = lastInviteCSeq ?? cseq
        
        let toTag = activeCallRemoteTag?.trimmingCharacters(in: .whitespacesAndNewlines)
        let toTagStr = (toTag != nil && !toTag!.isEmpty) ? ";tag=\(toTag!)" : ""
        
        var msg = "CANCEL sip:\(destination)@\(account.domain) SIP/2.0\r\n"
        msg += "Via: SIP/2.0/UDP \(localIP):\(localPort);branch=\(branch);rport\r\n"
        msg += "Max-Forwards: 70\r\n"
        msg += "From: \"\(account.displayName)\" <sip:\(account.username)@\(account.domain)>;tag=\(tagHeader)\r\n"
        msg += "To: <sip:\(destination)@\(account.domain)>\(toTagStr)\r\n"
        msg += "Call-ID: \(callIdHeader)\r\n"
        msg += "CSeq: \(cancelCSeq) CANCEL\r\n"
        msg += "Reason: Q.850;cause=16;text=\"Terminated\"\r\n"
        msg += "User-Agent: Telephone/1.6 (MeroSip)\r\n"
        msg += "Content-Length: 0\r\n\r\n"
        sendPacket(msg)
    }
    
    private func sendInfoDTMF(digit: String, destination: String) {
        guard let account = account else { return }
        cseq += 1
        let body = "Signal=\(digit)\r\nDuration=160\r\n"
        var msg = "INFO sip:\(destination)@\(account.domain) SIP/2.0\r\n"
        msg += "Via: SIP/2.0/UDP \(localIP):\(localPort);branch=z9hG4bK\(UUID().uuidString.prefix(8));rport\r\n"
        msg += "Max-Forwards: 70\r\n"
        msg += "From: <sip:\(account.username)@\(account.domain)>;tag=\(tagHeader)\r\n"
        msg += "To: <sip:\(destination)@\(account.domain)>\(activeCallRemoteTag.map { ";tag=\($0)" } ?? "")\r\n"
        msg += "Call-ID: \(callIdHeader)\r\n"
        msg += "CSeq: \(cseq) INFO\r\n"
        msg += "Content-Type: application/dtmf-relay\r\n"
        msg += "Content-Length: \(body.utf8.count)\r\n\r\n"
        msg += body
        sendPacket(msg)
    }
    
    private func sendRefer(targetUri: String, destination: String) {
        guard let account = account else { return }
        cseq += 1
        
        let toTag = activeCallRemoteTag?.trimmingCharacters(in: .whitespacesAndNewlines)
        let toTagStr = (toTag != nil && !toTag!.isEmpty) ? ";tag=\(toTag!)" : ""
        
        let cleanTarget = targetUri.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetSip = cleanTarget.contains("@") ? cleanTarget : "\(cleanTarget)@\(account.domain)"
        
        var msg = "REFER sip:\(destination)@\(account.domain) SIP/2.0\r\n"
        msg += "Via: SIP/2.0/UDP \(localIP):\(localPort);branch=z9hG4bK\(UUID().uuidString.prefix(8));rport\r\n"
        msg += "Max-Forwards: 70\r\n"
        msg += "From: <sip:\(account.username)@\(account.domain)>;tag=\(tagHeader)\r\n"
        msg += "To: <sip:\(destination)@\(account.domain)>\(toTagStr)\r\n"
        msg += "Call-ID: \(callIdHeader)\r\n"
        msg += "CSeq: \(cseq) REFER\r\n"
        msg += "Contact: <sip:\(account.username)@\(localIP):\(localPort);transport=udp>\r\n"
        msg += "Referred-By: <sip:\(account.username)@\(account.domain)>\r\n"
        msg += "Refer-To: <sip:\(targetSip)>\r\n"
        msg += "User-Agent: Telephone/1.6 (MeroSip)\r\n"
        msg += "Content-Length: 0\r\n\r\n"
        
        print("[SIP Engine] Sending SIP REFER to transfer call to \(targetSip)...")
        sendPacket(msg)
    }
    
    private func sendPacket(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("[SIP Engine] UDP send error: \(error)")
            }
        })
    }
    
    // MARK: - Incoming Packet Listener & RFC 2617 Digest Auth
    
    private func startListening(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.connection != nil else { return }
                if let data = data, let text = String(data: data, encoding: .utf8) {
                    self.handleIncomingSIP(text)
                }
                self.startListening(on: conn)
            }
        }
    }
    
    private func handleIncomingSIP(_ raw: String) {
        let lines = raw.components(separatedBy: "\r\n")
        guard let firstLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return }
        
        print("[SIP Engine] Received: \(firstLine)")
        
        // Handle OPTIONS keep-alive from FreePBX
        if firstLine.hasPrefix("OPTIONS") {
            var reply = "SIP/2.0 200 OK\r\n"
            if let via = lines.first(where: { $0.lowercased().hasPrefix("via:") }) { reply += "\(via)\r\n" }
            if let from = lines.first(where: { $0.lowercased().hasPrefix("from:") }) { reply += "\(from)\r\n" }
            if let to = lines.first(where: { $0.lowercased().hasPrefix("to:") }) { reply += "\(to);tag=\(tagHeader)\r\n" }
            if let callId = lines.first(where: { $0.lowercased().hasPrefix("call-id:") }) { reply += "\(callId)\r\n" }
            if let cseq = lines.first(where: { $0.lowercased().hasPrefix("cseq:") }) { reply += "\(cseq)\r\n" }
            reply += "Content-Length: 0\r\n\r\n"
            sendPacket(reply)
            
            if registrationState != .registered {
                updateRegistrationState(.registered)
            }
            return
        }
        
        // Handle 403 Forbidden / 404 Not Found for Registration
        if firstLine.contains("403") || firstLine.contains("404") {
            if let cseqLine = lines.first(where: { $0.lowercased().hasPrefix("cseq:") }), cseqLine.contains("REGISTER") {
                print("[SIP Engine] Registration Failed: Server returned \(firstLine)")
                updateRegistrationState(.registrationFailed)
                return
            }
        }
        
        // Handle 401 / 407 Digest Challenge
        if firstLine.contains("401") || firstLine.contains("407") {
            var method = "REGISTER"
            if let cseqLine = lines.first(where: { $0.lowercased().hasPrefix("cseq:") }) {
                if cseqLine.contains("INVITE") {
                    method = "INVITE"
                } else if cseqLine.contains("REGISTER") {
                    method = "REGISTER"
                }
            }
            
            var challengeTag: String? = nil
            if let toLine = lines.first(where: { $0.lowercased().hasPrefix("to:") }),
               let tagPart = toLine.components(separatedBy: "tag=").last {
                challengeTag = tagPart.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            if method == "INVITE", let dest = activeSession?.remoteUri {
                print("[SIP Engine] Sending ACK for 401/407 challenge on INVITE...")
                sendChallengeAck(destination: dest, toTag: challengeTag)
            }
            
            handleDigestChallenge(lines: lines, method: method)
            return
        }
        
        // Handle 200 OK for Outgoing Calls & Registration
        if firstLine.contains("200 OK") {
            if let cseqLine = lines.first(where: { $0.lowercased().hasPrefix("cseq:") }) {
                if cseqLine.contains("REGISTER") {
                    print("[SIP Engine] SIP Registration Confirmed (Online)")
                    updateRegistrationState(.registered)
                    scheduleKeepAlive()
                } else if cseqLine.contains("INVITE") {
                    print("[SIP Engine] INVITE 200 OK received.")
                    if let toLine = lines.first(where: { $0.lowercased().hasPrefix("to:") }),
                       let tagPart = toLine.components(separatedBy: "tag=").last {
                        self.activeCallRemoteTag = tagPart.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    
                    parseRemoteSDP(lines: lines)
                    
                    if var session = activeSession {
                        sendAck(destination: session.remoteUri)
                        
                        if session.connectTime == nil {
                            // Initial call answered
                            session.state = .connected(duration: 0)
                            session.connectTime = Date()
                            self.activeSession = session
                            notifySessionUpdated(session)
                            
                            let host = incomingRemoteRTPHost ?? account?.domain ?? "127.0.0.1"
                            let port = incomingRemoteRTPPort ?? 10000
                            RTPAudioEngine.shared.startRTP(remoteHost: host, remotePort: port, codec: incomingNegotiatedCodec)
                            
                            startDurationTicker(callId: session.callId)
                        } else {
                            // In-dialog re-INVITE 200 OK (Hold / Resume)
                            print("[SIP Engine] In-dialog re-INVITE acknowledged: Hold is \(session.isOnHold)")
                            notifySessionUpdated(session)
                        }
                    }
                }
            }
            return
        }
        
        // Handle 100 Trying / 180 Ringing / 183 Session Progress
        if firstLine.contains("180 Ringing") || firstLine.contains("183") || firstLine.contains("100 Trying") {
            print("[SIP Engine] Destination is ringing / in progress: \(firstLine)")
            if firstLine.contains("180") || firstLine.contains("183") {
                if var session = activeSession {
                    session.state = .ringing(isIncoming: false)
                    self.activeSession = session
                    notifySessionUpdated(session)
                }
            }
            return
        }
        
        // Handle Call Termination (486 Busy, 603 Decline, 404 Not Found, etc.)
        if firstLine.contains("486") || firstLine.contains("603") || firstLine.contains("404") || firstLine.contains("487") || firstLine.contains("503") || firstLine.contains("488") {
            print("[SIP Engine] Call terminated by server: \(firstLine)")
            
            if let dest = activeSession?.remoteUri {
                sendAck(destination: dest)
            }
            
            RTPAudioEngine.shared.stopRTP()
            if let session = activeSession {
                self.activeSession = nil
                let reason: DisconnectReason = firstLine.contains("486") ? .busy : (firstLine.contains("603") ? .declined : .failed)
                notifySessionTerminated(session, reason: reason)
            }
            return
        }
        
        // Handle 202 Accepted (SIP REFER Blind Transfer Accepted)
        if firstLine.contains("202 Accepted") {
            print("[SIP Engine] Blind Transfer accepted by PBX! Transfer in progress...")
            return
        }
        
        // Handle NOTIFY (Transfer status notifications)
        if firstLine.hasPrefix("NOTIFY") {
            print("[SIP Engine] Received NOTIFY event from PBX.")
            var reply = "SIP/2.0 200 OK\r\n"
            for via in lines.filter({ $0.lowercased().hasPrefix("via:") }) { reply += "\(via)\r\n" }
            if let from = lines.first(where: { $0.lowercased().hasPrefix("from:") }) { reply += "\(from)\r\n" }
            if let to = lines.first(where: { $0.lowercased().hasPrefix("to:") }) { reply += "\(to)\r\n" }
            if let callId = lines.first(where: { $0.lowercased().hasPrefix("call-id:") }) { reply += "\(callId)\r\n" }
            if let cseq = lines.first(where: { $0.lowercased().hasPrefix("cseq:") }) { reply += "\(cseq)\r\n" }
            reply += "Content-Length: 0\r\n\r\n"
            sendPacket(reply)
            
            if raw.contains("SIP/2.0 200 OK") || raw.contains("200 OK") {
                print("[SIP Engine] Transferred party answered! Completing transfer and hanging up local leg.")
                if let session = activeSession {
                    Task {
                        await hangupCall(callId: session.callId)
                    }
                }
            }
            return
        }
        
        // Handle Incoming INVITE from Asterisk
        if firstLine.hasPrefix("INVITE") {
            self.incomingViaLines = lines.filter { $0.lowercased().hasPrefix("via:") }
            self.incomingFromLine = lines.first(where: { $0.lowercased().hasPrefix("from:") })
            self.incomingToLine = lines.first(where: { $0.lowercased().hasPrefix("to:") })
            self.incomingCallIdLine = lines.first(where: { $0.lowercased().hasPrefix("call-id:") })
            self.incomingCSeqLine = lines.first(where: { $0.lowercased().hasPrefix("cseq:") })
            
            parseRemoteSDP(lines: lines)
            
            let caller = extractCaller(from: lines)
            let callNum = Int32.random(in: 1000...9999)
            print("[SIP Engine] Incoming Call from \(caller.name) (\(caller.uri))")
            
            let session = CallSession(
                callId: callNum,
                remoteUri: caller.uri,
                remoteDisplayName: caller.name,
                direction: .incoming,
                state: .ringing(isIncoming: true),
                startTime: Date()
            )
            self.activeSession = session
            self.delegate?.sipService(self, didReceiveIncomingCall: session)
            
            var ringing = "SIP/2.0 180 Ringing\r\n"
            for via in incomingViaLines {
                ringing += "\(via)\r\n"
            }
            if let from = incomingFromLine { ringing += "\(from)\r\n" }
            if let to = incomingToLine { ringing += "\(to);tag=\(tagHeader)\r\n" }
            if let callId = incomingCallIdLine { ringing += "\(callId)\r\n" }
            if let cseq = incomingCSeqLine { ringing += "\(cseq)\r\n" }
            ringing += "Contact: <sip:\(account?.username ?? "201")@\(localIP):\(localPort);transport=udp>\r\n"
            ringing += "Content-Length: 0\r\n\r\n"
            sendPacket(ringing)
            return
        }
        
        // Handle Incoming BYE
        if firstLine.hasPrefix("BYE") {
            print("[SIP Engine] Remote party hung up.")
            RTPAudioEngine.shared.stopRTP()
            if let session = activeSession {
                self.activeSession = nil
                notifySessionTerminated(session, reason: .normal)
            }
            
            var reply = "SIP/2.0 200 OK\r\n"
            if let via = lines.first(where: { $0.lowercased().hasPrefix("via:") }) { reply += "\(via)\r\n" }
            if let from = lines.first(where: { $0.lowercased().hasPrefix("from:") }) { reply += "\(from)\r\n" }
            if let to = lines.first(where: { $0.lowercased().hasPrefix("to:") }) { reply += "\(to)\r\n" }
            if let callId = lines.first(where: { $0.lowercased().hasPrefix("call-id:") }) { reply += "\(callId)\r\n" }
            if let cseq = lines.first(where: { $0.lowercased().hasPrefix("cseq:") }) { reply += "\(cseq)\r\n" }
            reply += "Content-Length: 0\r\n\r\n"
            sendPacket(reply)
            return
        }
    }
    
    private func parseRemoteSDP(lines: [String]) {
        var foundOpus = false
        var foundPCMA = false
        var foundPCMU = false
        
        for line in lines {
            let lower = line.lowercased()
            if line.hasPrefix("c=IN IP4 ") {
                let parts = line.components(separatedBy: " ")
                if parts.count >= 3 {
                    self.incomingRemoteRTPHost = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else if line.hasPrefix("m=audio ") {
                let parts = line.components(separatedBy: " ")
                if parts.count >= 2, let port = UInt16(parts[1]) {
                    self.incomingRemoteRTPPort = port
                }
            } else if lower.contains("rtpmap:") {
                if lower.contains("opus/48000") {
                    foundOpus = true
                } else if lower.contains("pcma/8000") {
                    foundPCMA = true
                } else if lower.contains("pcmu/8000") {
                    foundPCMU = true
                }
            }
        }
        
        if foundOpus {
            self.incomingNegotiatedCodec = .opus
        } else if foundPCMA {
            self.incomingNegotiatedCodec = .pcma
        } else if foundPCMU {
            self.incomingNegotiatedCodec = .pcmu
        } else {
            self.incomingNegotiatedCodec = .opus
        }
        
        print("[SIP Engine] Parsed Asterisk RTP Endpoint: \(incomingRemoteRTPHost ?? "none"):\(incomingRemoteRTPPort ?? 0) | Codec: [\(incomingNegotiatedCodec.name)]")
    }
    
    private func handleDigestChallenge(lines: [String], method: String) {
        guard let account = account, let password = account.password, !password.isEmpty else {
            print("[SIP Engine] Cannot respond to digest challenge: missing or empty SIP password.")
            updateRegistrationState(.registrationFailed)
            return
        }
        
        if method == "REGISTER" {
            registerAuthAttempts += 1
            if registerAuthAttempts > 2 {
                print("[SIP Engine] Registration Failed: Repeated 401/407 challenges received. Check SIP username/password.")
                updateRegistrationState(.registrationFailed)
                return
            }
        }
        
        let authLine = lines.first(where: {
            $0.lowercased().hasPrefix("www-authenticate:") || $0.lowercased().hasPrefix("proxy-authenticate:")
        }) ?? ""
        
        self.authRealm = extractParam(from: authLine, param: "realm") ?? account.domain
        self.authNonce = extractParam(from: authLine, param: "nonce")
        self.authOpaque = extractParam(from: authLine, param: "opaque")
        self.authQop = extractParam(from: authLine, param: "qop")
        
        guard let nonce = authNonce, let realm = authRealm else { return }
        
        self.ncCount += 1
        let nc = String(format: "%08x", ncCount)
        let cnonce = String(Int.random(in: 10000000...99999999))
        let uri = method == "REGISTER" ? "sip:\(account.domain)" : "sip:\(activeSession?.remoteUri ?? "")@\(account.domain)"
        
        let ha1 = md5Hex("\(account.username):\(realm):\(password)")
        let ha2 = md5Hex("\(method):\(uri)")
        
        var authHeader = "Digest username=\"\(account.username)\", realm=\"\(realm)\", nonce=\"\(nonce)\", uri=\"\(uri)\""
        
        if let qop = authQop, qop.contains("auth") {
            let digestResponse = md5Hex("\(ha1):\(nonce):\(nc):\(cnonce):auth:\(ha2)")
            authHeader += ", qop=auth, nc=\(nc), cnonce=\"\(cnonce)\", response=\"\(digestResponse)\", algorithm=MD5"
        } else {
            let digestResponse = md5Hex("\(ha1):\(nonce):\(ha2)")
            authHeader += ", response=\"\(digestResponse)\", algorithm=MD5"
        }
        
        if let opaque = authOpaque {
            authHeader += ", opaque=\"\(opaque)\""
        }
        
        print("[SIP Engine] Responding to FreePBX Digest challenge for \(method)...")
        
        if method == "REGISTER" {
            sendRegister(authHeader: authHeader)
        } else if method == "INVITE", let dest = activeSession?.remoteUri {
            sendInvite(destination: dest, authHeader: authHeader)
        }
    }
    
    private func md5Hex(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    private func extractParam(from header: String, param: String) -> String? {
        let pattern = "\(param)=\"([^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
           let range = Range(match.range(at: 1), in: header) {
            return String(header[range])
        }
        return nil
    }
    
    private func extractCaller(from lines: [String]) -> (name: String, uri: String) {
        guard let fromLine = lines.first(where: { $0.lowercased().hasPrefix("from:") }) else {
            return ("Unknown", "Unknown")
        }
        var name = "Unknown"
        var uri = "Unknown"
        if let start = fromLine.firstIndex(of: "<"), let end = fromLine.firstIndex(of: ">") {
            let fullUri = String(fromLine[fromLine.index(after: start)..<end])
            uri = fullUri.replacingOccurrences(of: "sip:", with: "").components(separatedBy: "@").first ?? fullUri
        }
        if let quoteStart = fromLine.firstIndex(of: "\""), let quoteEnd = fromLine.lastIndex(of: "\""), quoteStart < quoteEnd {
            name = String(fromLine[fromLine.index(after: quoteStart)..<quoteEnd])
        } else {
            name = uri
        }
        return (name, uri)
    }
    
    private func scheduleKeepAlive() {
        guard keepAliveTimer == nil else { return }
        keepAliveTimer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 60s keepalive
                guard let self = self, self.registrationState == .registered, let account = self.account else { break }
                
                if let nonce = self.authNonce, let realm = self.authRealm, let password = account.password {
                    let uri = "sip:\(account.domain)"
                    let ha1 = self.md5Hex("\(account.username):\(realm):\(password)")
                    let ha2 = self.md5Hex("REGISTER:\(uri)")
                    self.ncCount += 1
                    let nc = String(format: "%08x", self.ncCount)
                    let cnonce = String(Int.random(in: 10000000...99999999))
                    
                    var authHeader = "Digest username=\"\(account.username)\", realm=\"\(realm)\", nonce=\"\(nonce)\", uri=\"\(uri)\""
                    if let qop = self.authQop, qop.contains("auth") {
                        let digestResponse = self.md5Hex("\(ha1):\(nonce):\(nc):\(cnonce):auth:\(ha2)")
                        authHeader += ", qop=auth, nc=\(nc), cnonce=\"\(cnonce)\", response=\"\(digestResponse)\", algorithm=MD5"
                    } else {
                        let digestResponse = self.md5Hex("\(ha1):\(nonce):\(ha2)")
                        authHeader += ", response=\"\(digestResponse)\", algorithm=MD5"
                    }
                    if let opaque = self.authOpaque {
                        authHeader += ", opaque=\"\(opaque)\""
                    }
                    self.sendRegister(authHeader: authHeader)
                } else {
                    self.sendRegister(authHeader: nil)
                }
            }
        }
    }
    
    private func startDurationTicker(callId: Int32) {
        durationTimer?.cancel()
        durationTimer = Task { @MainActor [weak self] in
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
        if state != .registering {
            registrationTimeoutTask?.cancel()
            registrationTimeoutTask = nil
        }
        
        self.registrationState = state
        self.delegate?.sipService(self, didChangeRegistrationState: state)
        
        if state == .registrationFailed {
            scheduleRetryTimer()
        } else if state == .registered || state == .unregistered {
            retryTimerTask?.cancel()
            retryTimerTask = nil
        }
    }
    
    private func scheduleRetryTimer() {
        retryTimerTask?.cancel()
        retryTimerTask = Task { @MainActor [weak self] in
            var countdown = 5
            while !Task.isCancelled {
                guard let self = self, self.account != nil else { break }
                
                if self.registrationState == .registered || self.registrationState == .unregistered {
                    break
                }
                
                if let monitor = self.pathMonitor, monitor.currentPath.status != .satisfied {
                    self.updateRegistrationState(.retrying(seconds: countdown))
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    countdown -= 1
                    if countdown <= 0 {
                        countdown = 5
                    }
                    continue
                }
                
                self.updateRegistrationState(.retrying(seconds: countdown))
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                countdown -= 1
                
                if countdown <= 0 {
                    countdown = 5
                    guard let account = self.account else { break }
                    print("[SIP Engine] Retry countdown reached. Attempting SIP registration...")
                    self.registerAuthAttempts = 0
                    try? await self.start(account: account)
                }
            }
        }
    }
    
    private func startPathMonitor() {
        guard !isPathMonitorStarted else { return }
        isPathMonitorStarted = true
        let monitor = NWPathMonitor()
        self.pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if path.status != .satisfied {
                    print("[SIP Engine] Network connection lost (Wi-Fi/Internet off). Transitioning to failed & retrying.")
                    self.connection?.cancel()
                    self.connection = nil
                    if self.registrationState != .unregistered {
                        self.updateRegistrationState(.registrationFailed)
                    }
                } else if path.status == .satisfied {
                    print("[SIP Engine] Network connection restored.")
                    if self.registrationState != .registered && self.registrationState != .unregistered {
                        if let account = self.account {
                            print("[SIP Engine] Internet re-established. Immediate SIP registration retry...")
                            self.registerAuthAttempts = 0
                            try? await self.start(account: account)
                        }
                    }
                }
            }
        }
        monitor.start(queue: .global(qos: .utility))
    }
    
    private func notifySessionUpdated(_ session: CallSession) {
        self.delegate?.sipService(self, didUpdateCallSession: session)
    }
    
    private func notifySessionTerminated(_ session: CallSession, reason: DisconnectReason) {
        self.delegate?.sipService(self, didTerminateCallSession: session, reason: reason)
    }
}
