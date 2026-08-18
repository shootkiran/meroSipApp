import Foundation
import AudioToolbox
import AVFoundation

/// High-performance native wrapper around Apple's AudioToolbox for Opus (48 kHz) encoding and decoding.
public final class OpusCodec: @unchecked Sendable {
    private var encoderConverter: AudioConverterRef?
    private var decoderConverter: AudioConverterRef?
    
    public static let sampleRate: Double = 48000.0
    public static let framesPerPacket: UInt32 = 960 // 20ms at 48kHz
    private static let endOfInputStatus: OSStatus = 100
    
    private var pcmFormat: AudioStreamBasicDescription
    private var opusFormat: AudioStreamBasicDescription
    
    private struct EncoderInputContext {
        var samples: UnsafePointer<Float>?
        var sampleCount: Int
    }
    
    private struct DecoderInputContext {
        var bytes: UnsafeRawPointer?
        var byteCount: Int
        var packetDesc: AudioStreamPacketDescription
    }
    
    public init?() {
        // Source PCM: 48kHz 32-bit Float Mono
        self.pcmFormat = AudioStreamBasicDescription(
            mSampleRate: OpusCodec.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        
        // Destination Opus: 48kHz Mono
        self.opusFormat = AudioStreamBasicDescription(
            mSampleRate: OpusCodec.sampleRate,
            mFormatID: kAudioFormatOpus,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: OpusCodec.framesPerPacket,
            mBytesPerFrame: 0,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 0,
            mReserved: 0
        )
        
        var enc: AudioConverterRef?
        var dec: AudioConverterRef?
        
        let encStatus = AudioConverterNew(&pcmFormat, &opusFormat, &enc)
        let decStatus = AudioConverterNew(&opusFormat, &pcmFormat, &dec)
        
        guard encStatus == noErr, let validEnc = enc,
              decStatus == noErr, let validDec = dec else {
            if let enc = enc { AudioConverterDispose(enc) }
            if let dec = dec { AudioConverterDispose(dec) }
            return nil
        }
        
        // Set bit rate for voice (32000 bps for wideband voice)
        var bitRate: UInt32 = 32000
        AudioConverterSetProperty(validEnc, kAudioConverterEncodeBitRate, UInt32(MemoryLayout<UInt32>.size), &bitRate)
        
        self.encoderConverter = validEnc
        self.decoderConverter = validDec
    }
    
    deinit {
        if let enc = encoderConverter { AudioConverterDispose(enc) }
        if let dec = decoderConverter { AudioConverterDispose(dec) }
    }
    
    // MARK: - Encode PCM (48kHz Float) -> Opus Packet
    
    public func encode(pcmSamples: [Float]) -> Data? {
        guard let encoder = encoderConverter, pcmSamples.count >= Int(OpusCodec.framesPerPacket) else { return nil }
        
        var outBuffer = [UInt8](repeating: 0, count: 1275) // Max recommended Opus packet size
        var ioOutputDataPacketSize: UInt32 = 1
        var outBufferList = AudioBufferList()
        outBufferList.mNumberBuffers = 1
        outBufferList.mBuffers.mNumberChannels = 1
        outBufferList.mBuffers.mDataByteSize = UInt32(outBuffer.count)
        
        var packetDesc = AudioStreamPacketDescription()
        
        var encodedData: Data?
        pcmSamples.withUnsafeBufferPointer { pcmBuffer in
            guard let pcmAddress = pcmBuffer.baseAddress else { return }
            var context = EncoderInputContext(samples: pcmAddress, sampleCount: pcmSamples.count)
            
            let status: OSStatus = outBuffer.withUnsafeMutableBytes { outRaw in
                outBufferList.mBuffers.mData = outRaw.baseAddress
                
                return AudioConverterFillComplexBuffer(
                    encoder,
                    OpusCodec.encoderInputProc,
                    &context,
                    &ioOutputDataPacketSize,
                    &outBufferList,
                    &packetDesc
                )
            }
            
            if (status == noErr || status == OpusCodec.endOfInputStatus) && ioOutputDataPacketSize > 0 {
                let encodedSize = Int(outBufferList.mBuffers.mDataByteSize)
                if encodedSize > 0 && encodedSize <= outBuffer.count {
                    encodedData = Data(outBuffer.prefix(encodedSize))
                }
            }
        }
        
        return encodedData
    }
    
    // MARK: - Decode Opus Packet -> PCM (48kHz Float)
    
    public func decode(opusData: Data) -> [Float]? {
        guard let decoder = decoderConverter, !opusData.isEmpty else { return nil }
        
        var outSamples = [Float](repeating: 0.0, count: Int(OpusCodec.framesPerPacket))
        var ioOutputDataPacketSize: UInt32 = OpusCodec.framesPerPacket
        var outBufferList = AudioBufferList()
        outBufferList.mNumberBuffers = 1
        outBufferList.mBuffers.mNumberChannels = 1
        outBufferList.mBuffers.mDataByteSize = UInt32(outSamples.count * MemoryLayout<Float>.size)
        
        var decodedSamples: [Float]?
        opusData.withUnsafeBytes { opusRaw in
            guard let opusAddress = opusRaw.baseAddress else { return }
            var context = DecoderInputContext(
                bytes: opusAddress,
                byteCount: opusData.count,
                packetDesc: AudioStreamPacketDescription(
                    mStartOffset: 0,
                    mVariableFramesInPacket: 0,
                    mDataByteSize: UInt32(opusData.count)
                )
            )
            
            let status: OSStatus = outSamples.withUnsafeMutableBytes { outRaw in
                outBufferList.mBuffers.mData = outRaw.baseAddress
                
                return AudioConverterFillComplexBuffer(
                    decoder,
                    OpusCodec.decoderInputProc,
                    &context,
                    &ioOutputDataPacketSize,
                    &outBufferList,
                    nil
                )
            }
            
            if (status == noErr || status == OpusCodec.endOfInputStatus) && ioOutputDataPacketSize > 0 {
                let framesProduced = Int(ioOutputDataPacketSize)
                decodedSamples = Array(outSamples.prefix(framesProduced))
            }
        }
        
        return decodedSamples
    }
    
    // MARK: - AudioConverter Callbacks
    
    private static let encoderInputProc: AudioConverterComplexInputDataProc = { (
        inAudioConverter,
        ioNumberDataPackets,
        ioData,
        outDataPacketDescription,
        inUserData
    ) -> OSStatus in
        guard let userData = inUserData else { return -1 }
        let contextPtr = userData.assumingMemoryBound(to: EncoderInputContext.self)
        
        guard let samples = contextPtr.pointee.samples, contextPtr.pointee.sampleCount > 0 else {
            ioNumberDataPackets.pointee = 0
            return OpusCodec.endOfInputStatus
        }
        
        let framesAvailable = UInt32(contextPtr.pointee.sampleCount)
        let framesToProvide = min(ioNumberDataPackets.pointee, framesAvailable)
        
        if framesToProvide == 0 {
            ioNumberDataPackets.pointee = 0
            return OpusCodec.endOfInputStatus
        }
        
        ioNumberDataPackets.pointee = framesToProvide
        ioData.pointee.mNumberBuffers = 1
        ioData.pointee.mBuffers.mNumberChannels = 1
        ioData.pointee.mBuffers.mDataByteSize = framesToProvide * UInt32(MemoryLayout<Float>.size)
        ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: samples)
        
        contextPtr.pointee.samples = nil
        contextPtr.pointee.sampleCount = 0
        return noErr
    }
    
    private static let decoderInputProc: AudioConverterComplexInputDataProc = { (
        inAudioConverter,
        ioNumberDataPackets,
        ioData,
        outDataPacketDescription,
        inUserData
    ) -> OSStatus in
        guard let userData = inUserData else { return -1 }
        let contextPtr = userData.assumingMemoryBound(to: DecoderInputContext.self)
        
        guard let bytes = contextPtr.pointee.bytes, contextPtr.pointee.byteCount > 0 else {
            ioNumberDataPackets.pointee = 0
            return OpusCodec.endOfInputStatus
        }
        
        let byteCount = UInt32(contextPtr.pointee.byteCount)
        ioNumberDataPackets.pointee = 1
        ioData.pointee.mNumberBuffers = 1
        ioData.pointee.mBuffers.mNumberChannels = 1
        ioData.pointee.mBuffers.mDataByteSize = byteCount
        ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: bytes)
        
        contextPtr.pointee.packetDesc.mStartOffset = 0
        contextPtr.pointee.packetDesc.mVariableFramesInPacket = 0
        contextPtr.pointee.packetDesc.mDataByteSize = byteCount
        
        if let descPtr = outDataPacketDescription {
            descPtr.pointee = withUnsafeMutablePointer(to: &contextPtr.pointee.packetDesc) { $0 }
        }
        
        contextPtr.pointee.bytes = nil
        contextPtr.pointee.byteCount = 0
        return noErr
    }
}
