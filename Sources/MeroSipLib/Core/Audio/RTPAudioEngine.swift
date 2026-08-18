import Foundation
import AVFoundation
import Network

/// Dedicated nonisolated audio processor that runs safely on CoreAudio realtime audio threads
/// without triggering Swift Concurrency MainActor isolation assertion traps.
final class RealtimeAudioProcessor: @unchecked Sendable {
    var onEncodedRTPPacket: (@Sendable (Data) -> Void)?
    var isMuted: Bool = false
    var isOnHold: Bool = false
    
    private var sequenceNumber: UInt16 = UInt16.random(in: 1...1000)
    private var timestamp: UInt32 = UInt32.random(in: 1...100000)
    private let ssrc: UInt32 = UInt32.random(in: 100000...999999)
    
    private var sampleBuffer: [Float] = []
    private let lock = os_unfair_lock_t.allocate(capacity: 1)
    
    private var packetCount: Int = 0
    private var recentMaxVolume: Float = 0.0
    
    init() {
        lock.initialize(to: os_unfair_lock())
    }
    
    deinit {
        lock.deallocate()
    }
    
    nonisolated func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let floatChannelData = buffer.floatChannelData else { return }
        
        let frameCount = Int(buffer.frameLength)
        let sampleRate = buffer.format.sampleRate
        guard sampleRate > 0, frameCount > 0 else { return }
        
        let channel = floatChannelData[0]
        let step = sampleRate / 8000.0
        
        var resampled: [Float] = []
        resampled.reserveCapacity(Int(Double(frameCount) / step) + 2)
        
        var pos = 0.0
        var maxAmp: Float = 0.0
        while Int(pos) < frameCount {
            // Apply gentle voice pre-gain and sample
            let rawSample = channel[Int(pos)]
            let boosted = max(-1.0, min(1.0, rawSample * 1.4))
            let absSample = abs(boosted)
            if absSample > maxAmp { maxAmp = absSample }
            resampled.append(boosted)
            pos += step
        }
        
        os_unfair_lock_lock(lock)
        if maxAmp > recentMaxVolume { recentMaxVolume = maxAmp }
        sampleBuffer.append(contentsOf: resampled)
        
        while sampleBuffer.count >= 160 {
            let chunk = Array(sampleBuffer.prefix(160))
            sampleBuffer.removeFirst(160)
            os_unfair_lock_unlock(lock)
            
            encodeAndDispatch(samples: chunk)
            
            os_unfair_lock_lock(lock)
        }
        os_unfair_lock_unlock(lock)
    }
    
    nonisolated private func encodeAndDispatch(samples: [Float]) {
        var packet = Data(count: 12 + samples.count)
        
        // RFC 3550 RTP Header
        packet[0] = 0x80 // V=2
        packet[1] = 0x00 // Payload Type = 0 (PCMU)
        
        packet[2] = UInt8((sequenceNumber >> 8) & 0xFF)
        packet[3] = UInt8(sequenceNumber & 0xFF)
        sequenceNumber = sequenceNumber &+ 1
        
        packet[4] = UInt8((timestamp >> 24) & 0xFF)
        packet[5] = UInt8((timestamp >> 16) & 0xFF)
        packet[6] = UInt8((timestamp >> 8) & 0xFF)
        packet[7] = UInt8(timestamp & 0xFF)
        timestamp = timestamp &+ UInt32(samples.count)
        
        packet[8] = UInt8((ssrc >> 24) & 0xFF)
        packet[9] = UInt8((ssrc >> 16) & 0xFF)
        packet[10] = UInt8((ssrc >> 8) & 0xFF)
        packet[11] = UInt8(ssrc & 0xFF)
        
        // Encode samples to standard ITU-T G.711u (or silence 0xFF when muted or on hold)
        let isSilent = isMuted || isOnHold
        for i in 0..<samples.count {
            packet[12 + i] = isSilent ? 0xFF : RealtimeAudioProcessor.linearToMuLaw(samples[i])
        }
        
        packetCount += 1
        if packetCount % 50 == 0 {
            let vol = isSilent ? 0.0 : recentMaxVolume
            recentMaxVolume = 0.0
            let stateStr = isOnHold ? "[HOLD]" : (isMuted ? "[MUTED]" : "")
            print("[RTP Audio] Mic transmitting \(stateStr): \(packetCount) pkts sent (Mic peak amp: \(String(format: "%.3f", vol)))")
        }
        
        onEncodedRTPPacket?(packet)
    }
    
    /// Standard ITU-T G.711 linear to mu-law encoder
    nonisolated static func linearToMuLaw(_ sample: Float) -> UInt8 {
        let clamped = max(-1.0, min(1.0, sample))
        var pcm = Int(clamped * 32767.0)
        
        let mask: Int
        if pcm < 0 {
            pcm = -pcm
            mask = 0x7F
        } else {
            mask = 0xFF
        }
        
        if pcm > 32635 { pcm = 32635 }
        pcm += 0x84
        
        var exponent = 7
        for exp in 0..<8 {
            if pcm <= (0x84 + (0xFF << exp)) {
                exponent = exp
                break
            }
        }
        
        let mantissa = (pcm >> (exponent + 3)) & 0x0F
        let ulaw = (exponent << 4) | mantissa
        return UInt8(ulaw ^ mask)
    }
}

/// RTP Audio Engine handling real bidirectional G.711 u-law (PCMU) audio streaming with FreePBX/Asterisk.
@MainActor
public final class RTPAudioEngine: ObservableObject {
    public static let shared = RTPAudioEngine()
    
    @Published public private(set) var isAudioRunning: Bool = false
    @Published public var isMuted: Bool = false {
        didSet { audioProcessor?.isMuted = isMuted }
    }
    @Published public var isOnHold: Bool = false {
        didSet { audioProcessor?.isOnHold = isOnHold }
    }
    
    private var rtpConnection: NWConnection?
    public private(set) var localRTPPort: UInt16 = 40000
    
    private var remoteHost: String?
    private var remotePort: UInt16?
    
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioProcessor: RealtimeAudioProcessor?
    
    public init() {
        self.localRTPPort = UInt16.random(in: 40000...50000) & ~1 // Even port for RTP
        
        // Request microphone access early
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if granted {
                print("[RTP Audio] Microphone access granted.")
            } else {
                print("[RTP Audio] WARNING: Microphone access denied by user or macOS permissions.")
            }
        }
    }
    
    public func startRTP(remoteHost: String, remotePort: UInt16) {
        stopRTP()
        
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.isMuted = false
        self.isOnHold = false
        
        print("[RTP Audio] Starting RTP audio stream to \(remoteHost):\(remotePort) from local port \(localRTPPort)...")
        
        let processor = RealtimeAudioProcessor()
        processor.isMuted = isMuted
        processor.isOnHold = isOnHold
        self.audioProcessor = processor
        
        // Setup UDP Connection to Asterisk RTP port bound to localRTPPort for Symmetric NAT
        let host = NWEndpoint.Host(remoteHost)
        let port = NWEndpoint.Port(rawValue: remotePort) ?? .init(integerLiteral: 10000)
        
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        if let localEndpointPort = NWEndpoint.Port(rawValue: localRTPPort) {
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.any), port: localEndpointPort)
        }
        
        let conn = NWConnection(host: host, port: port, using: params)
        self.rtpConnection = conn
        
        processor.onEncodedRTPPacket = { [weak conn] packetData in
            conn?.send(content: packetData, completion: .contentProcessed { error in
                if let error = error {
                    print("[RTP Audio] RTP send error: \(error)")
                }
            })
        }
        
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if case .ready = state {
                    print("[RTP Audio] RTP UDP Socket Connected. Starting audio capture and playback...")
                    self.isAudioRunning = true
                    
                    // Send initial punch packet so Asterisk symmetric RTP immediately latches to our microphone port
                    var initialPacket = Data(count: 12 + 160)
                    initialPacket[0] = 0x80
                    initialPacket[1] = 0x00
                    for i in 12..<(12 + 160) { initialPacket[i] = 0xFF }
                    conn.send(content: initialPacket, completion: .contentProcessed { _ in })
                    
                    self.startRTPReceiver(on: conn)
                    self.startAudioEngine()
                }
            }
        }
        
        conn.start(queue: .global(qos: .userInteractive))
    }
    
    public func stopRTP() {
        guard isAudioRunning || audioEngine != nil || rtpConnection != nil else { return }
        print("[RTP Audio] Stopping RTP audio stream...")
        isAudioRunning = false
        
        stopAudioEngine()
        
        rtpConnection?.cancel()
        rtpConnection = nil
        audioProcessor = nil
    }
    
    // MARK: - Audio Engine (Mic Capture & Speaker Playback)
    
    private func startAudioEngine() {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        
        engine.attach(player)
        
        let mixer = engine.mainMixerNode
        var playerFormat = mixer.outputFormat(forBus: 0)
        if playerFormat.sampleRate == 0 {
            playerFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2) ?? playerFormat
        }
        
        if playerFormat.sampleRate > 0 {
            engine.connect(player, to: mixer, format: playerFormat)
        } else {
            engine.connect(player, to: mixer, format: nil)
        }
        
        // Microphone Input Configuration
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        if let processor = audioProcessor {
            inputNode.removeTap(onBus: 0)
            let tapFormat = (inputFormat.sampleRate > 0 && inputFormat.channelCount > 0) ? inputFormat : nil
            RTPAudioEngine.installMicTap(on: inputNode, format: tapFormat, processor: processor)
            print("[RTP Audio] Mic tap installed on input bus 0 with format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")
        }
        
        engine.prepare()
        
        do {
            try engine.start()
            player.play()
            self.audioEngine = engine
            self.playerNode = player
            print("[RTP Audio] AVAudioEngine started successfully (Microphone active & Player running).")
        } catch {
            print("[RTP Audio] Failed to start AVAudioEngine: \(error)")
        }
    }
    
    nonisolated private static func installMicTap(on inputNode: AVAudioNode, format: AVAudioFormat?, processor: RealtimeAudioProcessor) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            processor.handleInputBuffer(buffer)
        }
    }
    
    private func stopAudioEngine() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            playerNode?.stop()
            engine.stop()
        }
        self.audioEngine = nil
        self.playerNode = nil
    }
    
    // MARK: - RTP Receive & Speaker Playback
    
    private func startRTPReceiver(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isAudioRunning, self.rtpConnection != nil else { return }
                if let data = data, data.count > 12 {
                    let payload = data.subdata(in: 12..<data.count)
                    self.playAudioPayload(payload)
                }
                self.startRTPReceiver(on: conn)
            }
        }
    }
    
    private func playAudioPayload(_ payload: Data) {
        guard let engine = audioEngine, let player = playerNode, engine.isRunning else { return }
        
        let mixer = engine.mainMixerNode
        let mixerFormat = mixer.outputFormat(forBus: 0)
        let sampleRate = mixerFormat.sampleRate
        guard sampleRate > 0 else { return }
        
        let inSampleCount = payload.count // 8kHz samples
        let outSampleCount = Int(Double(inSampleCount) * (sampleRate / 8000.0))
        guard outSampleCount > 0 else { return }
        
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: mixerFormat, frameCapacity: AVAudioFrameCount(outSampleCount)) else { return }
        pcmBuffer.frameLength = AVAudioFrameCount(outSampleCount)
        
        guard let floatData = pcmBuffer.floatChannelData else { return }
        
        // Decode G.711u samples to float
        var decodedSamples = [Float](repeating: 0, count: inSampleCount)
        payload.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for i in 0..<inSampleCount {
                decodedSamples[i] = decodeMuLaw(bytes[i])
            }
        }
        
        // Upsample to mixer sample rate (e.g. 44.1kHz or 48kHz)
        let ratio = 8000.0 / sampleRate
        for frame in 0..<outSampleCount {
            let inIndex = min(Int(Double(frame) * ratio), inSampleCount - 1)
            let sample = decodedSamples[inIndex]
            for ch in 0..<Int(mixerFormat.channelCount) {
                floatData[ch][frame] = sample
            }
        }
        
        player.scheduleBuffer(pcmBuffer, completionHandler: nil)
        if !player.isPlaying {
            player.play()
        }
    }
    
    /// Standard ITU-T G.711 mu-law to linear float decoder
    private func decodeMuLaw(_ uLawByte: UInt8) -> Float {
        let ulaw = ~Int(uLawByte)
        let sign = (ulaw & 0x80) != 0 ? -1 : 1
        let exponent = (ulaw >> 4) & 0x07
        let mantissa = ulaw & 0x0F
        let sample = sign * (((mantissa << 3) + 0x84) << exponent - 0x84)
        return Float(sample) / 32768.0
    }
}
