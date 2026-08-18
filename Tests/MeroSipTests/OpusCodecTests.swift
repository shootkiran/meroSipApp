import XCTest
@testable import MeroSipLib

final class OpusCodecTests: XCTestCase {
    func testOpusCodecInitialization() {
        let codec = OpusCodec()
        XCTAssertNotNil(codec, "OpusCodec should initialize successfully using AudioToolbox on macOS")
    }
    
    func testOpusEncodeAndDecodeRoundTrip() {
        guard let codec = OpusCodec() else {
            XCTFail("Failed to initialize OpusCodec")
            return
        }
        
        let sampleCount = 960
        var allDecodedCount = 0
        
        // Encode and decode 3 consecutive 20ms frames
        for frameIndex in 0..<3 {
            var pcmSamples = [Float](repeating: 0, count: sampleCount)
            for i in 0..<sampleCount {
                let t = Double(frameIndex * sampleCount + i) / 48000.0
                pcmSamples[i] = Float(sin(2.0 * .pi * 440.0 * t) * 0.5)
            }
            
            guard let opusPacket = codec.encode(pcmSamples: pcmSamples) else {
                XCTFail("Failed to encode 48kHz PCM samples to Opus packet on frame \(frameIndex)")
                return
            }
            
            XCTAssertGreaterThan(opusPacket.count, 0, "Opus packet should not be empty")
            XCTAssertLessThanOrEqual(opusPacket.count, 1275, "Opus packet should be within max standard size")
            
            guard let decoded = codec.decode(opusData: opusPacket) else {
                XCTFail("Failed to decode Opus packet back to PCM on frame \(frameIndex)")
                return
            }
            
            allDecodedCount += decoded.count
            XCTAssertGreaterThan(decoded.count, 0)
        }
        
        XCTAssertGreaterThanOrEqual(allDecodedCount, 2 * sampleCount, "Multiple frames should decode smoothly")
    }
    
    func testAudioCodecEnumProperties() {
        XCTAssertEqual(AudioCodec.opus.rawValue, 111)
        XCTAssertEqual(AudioCodec.pcmu.rawValue, 0)
        XCTAssertEqual(AudioCodec.pcma.rawValue, 8)
        
        XCTAssertEqual(AudioCodec.opus.targetSampleRate, 48000.0)
        XCTAssertEqual(AudioCodec.pcmu.targetSampleRate, 8000.0)
        XCTAssertEqual(AudioCodec.pcma.targetSampleRate, 8000.0)
        
        XCTAssertEqual(AudioCodec.opus.framesPerPacket, 960)
        XCTAssertEqual(AudioCodec.pcmu.framesPerPacket, 160)
    }
}
