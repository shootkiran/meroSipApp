import Foundation
import AVFoundation
import Network

/// Supported RTP Audio Codecs
public enum AudioCodec: UInt8, Sendable {
    case pcmu = 0
    case pcma = 8
    case opus = 111
    
    public var name: String {
        switch self {
        case .opus: return "Opus (48 kHz HD)"
        case .pcmu: return "G.711u (PCMU 8 kHz)"
        case .pcma: return "G.711a (PCMA 8 kHz)"
        }
    }
    
    public var targetSampleRate: Double {
        switch self {
        case .opus: return 48000.0
        case .pcmu, .pcma: return 8000.0
        }
    }
    
    public var framesPerPacket: Int {
        switch self {
        case .opus: return 960 // 20ms at 48kHz
        case .pcmu, .pcma: return 160 // 20ms at 8kHz
        }
    }
}

/// Dedicated nonisolated audio processor running safely on CoreAudio realtime audio threads
final class RealtimeAudioProcessor: @unchecked Sendable {
    var onEncodedRTPPacket: (@Sendable (Data) -> Void)?
    var isMuted: Bool = false
    var isOnHold: Bool = false
    var codec: AudioCodec = .opus
    
    private var sequenceNumber: UInt16 = UInt16.random(in: 1...1000)
    private var timestamp: UInt32 = UInt32.random(in: 1...100000)
    private let ssrc: UInt32 = UInt32.random(in: 100000...999999)
    
    private var sampleBuffer: [Float] = []
    private let lock = os_unfair_lock_t.allocate(capacity: 1)
    
    private var packetCount: Int = 0
    private var recentMaxVolume: Float = 0.0
    private let opusCodec = OpusCodec()
    
    init(codec: AudioCodec = .opus) {
        self.codec = codec
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
        let targetRate = codec.targetSampleRate
        let step = sampleRate / targetRate
        
        var resampled: [Float] = []
        resampled.reserveCapacity(Int(Double(frameCount) / step) + 2)
        
        var pos = 0.0
        var maxAmp: Float = 0.0
        while Int(pos) < frameCount {
            let startIndex = Int(pos)
            let endIndex = min(Int(pos + step), frameCount)
            
            var sum: Float = 0.0
            let count = max(1, endIndex - startIndex)
            for i in startIndex..<endIndex {
                sum += channel[i]
            }
            let sample = sum / Float(count)
            let clamped = max(-1.0, min(1.0, sample))
            let absSample = abs(clamped)
            if absSample > maxAmp { maxAmp = absSample }
            resampled.append(clamped)
            pos += step
        }
        
        os_unfair_lock_lock(lock)
        if maxAmp > recentMaxVolume { recentMaxVolume = maxAmp }
        sampleBuffer.append(contentsOf: resampled)
        
        let targetFrames = codec.framesPerPacket
        while sampleBuffer.count >= targetFrames {
            let chunk = Array(sampleBuffer.prefix(targetFrames))
            sampleBuffer.removeFirst(targetFrames)
            os_unfair_lock_unlock(lock)
            
            encodeAndDispatch(samples: chunk)
            
            os_unfair_lock_lock(lock)
        }
        os_unfair_lock_unlock(lock)
    }
    
    nonisolated private func encodeAndDispatch(samples: [Float]) {
        let isSilent = isMuted || isOnHold
        var payloadData: Data
        
        switch codec {
        case .opus:
            if isSilent {
                // Inactive / silence DTX frame
                payloadData = Data([0xF8, 0xFF, 0xFE])
            } else if let encoded = opusCodec?.encode(pcmSamples: samples) {
                payloadData = encoded
            } else {
                // Fallback silence
                payloadData = Data([0xF8, 0xFF, 0xFE])
            }
            
        case .pcmu:
            var data = Data(count: samples.count)
            for i in 0..<samples.count {
                data[i] = isSilent ? 0xFF : RealtimeAudioProcessor.linearToMuLaw(samples[i])
            }
            payloadData = data
            
        case .pcma:
            var data = Data(count: samples.count)
            for i in 0..<samples.count {
                data[i] = isSilent ? 0xD5 : RealtimeAudioProcessor.linearToALaw(samples[i])
            }
            payloadData = data
        }
        
        var packet = Data(count: 12 + payloadData.count)
        
        // RFC 3550 RTP Header
        packet[0] = 0x80 // V=2
        packet[1] = codec.rawValue & 0x7F
        
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
        
        packet.replaceSubrange(12..<(12 + payloadData.count), with: payloadData)
        
        packetCount += 1
        if packetCount % 50 == 0 {
            let vol = isSilent ? 0.0 : recentMaxVolume
            recentMaxVolume = 0.0
            let stateStr = isOnHold ? "[HOLD]" : (isMuted ? "[MUTED]" : "")
            print("[RTP Audio] Mic transmitting \(stateStr) [\(codec.name)]: \(packetCount) pkts sent (Peak amp: \(String(format: "%.3f", vol)))")
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
    
    /// Standard ITU-T G.711 linear to A-law encoder
    nonisolated static func linearToALaw(_ sample: Float) -> UInt8 {
        let clamped = max(-1.0, min(1.0, sample))
        var pcm = Int(clamped * 32767.0)
        
        let mask: Int
        if pcm >= 0 {
            mask = 0xD5
        } else {
            mask = 0x55
            pcm = -pcm - 1
        }
        
        var seg = 8
        for i in 0..<8 {
            if pcm <= (0x1F << (i + 4)) {
                seg = i
                break
            }
        }
        
        var aval: Int
        if seg >= 8 {
            aval = 0x7F
        } else {
            aval = seg << 4
            if seg != 0 {
                aval |= (pcm >> (seg + 3)) & 0x0F
            } else {
                aval |= (pcm >> 4) & 0x0F
            }
        }
        return UInt8(aval ^ mask)
    }
}

/// RTP Audio Engine handling real bidirectional Opus (48 kHz HD) and G.711 (PCMU/PCMA) audio streaming.
@MainActor
public final class RTPAudioEngine: ObservableObject {
    public static let shared = RTPAudioEngine()
    
    @Published public private(set) var isAudioRunning: Bool = false
    @Published public private(set) var activeCodec: AudioCodec = .opus
    
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
    private let opusDecoder = OpusCodec()
    
    public init() {
        self.localRTPPort = UInt16.random(in: 40000...50000) & ~1 // Even port for RTP
        
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if granted {
                print("[RTP Audio] Microphone access granted.")
            } else {
                print("[RTP Audio] WARNING: Microphone access denied.")
            }
        }
    }
    
    public func startRTP(remoteHost: String, remotePort: UInt16, codec: AudioCodec = .opus) {
        stopRTP()
        
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.activeCodec = codec
        self.isMuted = false
        self.isOnHold = false
        
        print("[RTP Audio] Starting RTP audio stream to \(remoteHost):\(remotePort) with codec [\(codec.name)] from local port \(localRTPPort)...")
        
        let processor = RealtimeAudioProcessor(codec: codec)
        processor.isMuted = isMuted
        processor.isOnHold = isOnHold
        self.audioProcessor = processor
        
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
                    
                    // Send initial punch packet so Asterisk symmetric RTP latches to our socket
                    var initialPacket = Data(count: 12 + codec.framesPerPacket)
                    initialPacket[0] = 0x80
                    initialPacket[1] = codec.rawValue & 0x7F
                    for i in 12..<initialPacket.count { initialPacket[i] = 0xFF }
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
            playerFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2) ?? playerFormat
        }
        
        if playerFormat.sampleRate > 0 {
            engine.connect(player, to: mixer, format: playerFormat)
        } else {
            engine.connect(player, to: mixer, format: nil)
        }
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        if let processor = audioProcessor {
            inputNode.removeTap(onBus: 0)
            let tapFormat = (inputFormat.sampleRate > 0 && inputFormat.channelCount > 0) ? inputFormat : nil
            RTPAudioEngine.installMicTap(on: inputNode, format: tapFormat, processor: processor)
            print("[RTP Audio] Mic tap installed with format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")
        }
        
        engine.prepare()
        
        do {
            try engine.start()
            player.play()
            self.audioEngine = engine
            self.playerNode = player
            print("[RTP Audio] AVAudioEngine running with [\(activeCodec.name)].")
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
                    let payloadType = data[1] & 0x7F
                    let payload = data.subdata(in: 12..<data.count)
                    self.playAudioPayload(payload, payloadType: payloadType)
                }
                self.startRTPReceiver(on: conn)
            }
        }
    }
    
    private func playAudioPayload(_ payload: Data, payloadType: UInt8) {
        guard let engine = audioEngine, let player = playerNode, engine.isRunning else { return }
        
        let mixer = engine.mainMixerNode
        let mixerFormat = mixer.outputFormat(forBus: 0)
        let sampleRate = mixerFormat.sampleRate
        guard sampleRate > 0 else { return }
        
        var decodedSamples: [Float] = []
        let sourceSampleRate: Double
        
        if payloadType == AudioCodec.opus.rawValue || (payloadType != 0 && payloadType != 8 && payload.count > 0) {
            // Decode Opus (48 kHz)
            if let samples = opusDecoder?.decode(opusData: payload) {
                decodedSamples = samples
                sourceSampleRate = 48000.0
            } else {
                return
            }
        } else if payloadType == AudioCodec.pcma.rawValue {
            // Decode G.711 A-law (8 kHz)
            sourceSampleRate = 8000.0
            decodedSamples = [Float](repeating: 0, count: payload.count)
            payload.withUnsafeBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                for i in 0..<payload.count {
                    decodedSamples[i] = decodeALaw(bytes[i])
                }
            }
        } else {
            // Decode G.711 u-law (8 kHz)
            sourceSampleRate = 8000.0
            decodedSamples = [Float](repeating: 0, count: payload.count)
            payload.withUnsafeBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                for i in 0..<payload.count {
                    decodedSamples[i] = decodeMuLaw(bytes[i])
                }
            }
        }
        
        let inSampleCount = decodedSamples.count
        guard inSampleCount > 0 else { return }
        
        let outSampleCount = Int(Double(inSampleCount) * (sampleRate / sourceSampleRate))
        guard outSampleCount > 0 else { return }
        
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: mixerFormat, frameCapacity: AVAudioFrameCount(outSampleCount)) else { return }
        pcmBuffer.frameLength = AVAudioFrameCount(outSampleCount)
        
        guard let floatData = pcmBuffer.floatChannelData else { return }
        
        let ratio = sourceSampleRate / sampleRate
        for frame in 0..<outSampleCount {
            let exactPos = Double(frame) * ratio
            let i0 = min(Int(exactPos), inSampleCount - 1)
            let i1 = min(i0 + 1, inSampleCount - 1)
            let frac = Float(exactPos - Double(i0))
            let sample = (1.0 - frac) * decodedSamples[i0] + frac * decodedSamples[i1]
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
    
    /// Standard ITU-T G.711 A-law to linear float decoder
    private func decodeALaw(_ aLawByte: UInt8) -> Float {
        let aval = Int(aLawByte ^ 0xD5)
        let sign = (aval & 0x80) != 0 ? 1 : -1
        let exponent = (aval >> 4) & 0x07
        let mantissa = aval & 0x0F
        
        let sample: Int
        if exponent == 0 {
            sample = (mantissa << 4) + 8
        } else {
            sample = ((mantissa << 4) + 0x108) << (exponent - 1)
        }
        return Float(sign * sample) / 32768.0
    }
}
