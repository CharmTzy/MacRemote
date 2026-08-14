import Foundation
import CoreMedia
import AVFoundation
import OSLog

/// Rebuilds `CMSampleBuffer`s from the raw AVCC frame data received over
/// the wire and feeds them to an `AVSampleBufferDisplayLayer`. No manual
/// `VTDecompressionSession` — `AVSampleBufferDisplayLayer` decodes and
/// displays H.264 directly, which is simpler and is what Apple recommends
/// for this exact use case.
///
/// Alongside `H264Encoder`, this is the other highest-risk file in the
/// project: raw Core Media buffer construction, unverified without a
/// compiler. If video doesn't render, look here and in `H264Encoder` first.
final class VideoDecoder {
    enum DecoderError: Error {
        case invalidParameterSets
        case formatDescriptionCreationFailed(OSStatus)
    }

    private var formatDescription: CMFormatDescription?
    private let timebase: CMTimebase

    weak var displayLayer: AVSampleBufferDisplayLayer? {
        didSet { displayLayer?.controlTimebase = timebase }
    }

    init() {
        var newTimebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &newTimebase)
        guard let newTimebase else {
            fatalError("CMTimebaseCreateWithSourceClock failed — indicates a broken Core Media install, not a normal runtime condition.")
        }
        timebase = newTimebase
        CMTimebaseSetTime(newTimebase, time: .zero)
        CMTimebaseSetRate(newTimebase, rate: 1.0)
    }

    /// Live, low-latency display: rather than trusting the Mac's original
    /// capture timestamps (which have no defined relationship to this
    /// device's clock), every frame is stamped with "now" on our own
    /// timebase, so `AVSampleBufferDisplayLayer` shows it immediately
    /// instead of pacing playback against a foreign clock.
    func applyConfig(_ config: VideoConfigPayload) throws {
        let sps = [UInt8](config.sps)
        let pps = [UInt8](config.pps)
        guard !sps.isEmpty, !pps.isEmpty else { throw DecoderError.invalidParameterSets }

        var newFormatDescription: CMFormatDescription?
        let status = sps.withUnsafeBufferPointer { spsBuffer -> OSStatus in
            pps.withUnsafeBufferPointer { ppsBuffer -> OSStatus in
                guard let spsBase = spsBuffer.baseAddress, let ppsBase = ppsBuffer.baseAddress else {
                    return kCMFormatDescriptionError_InvalidParameter
                }
                let pointers: [UnsafePointer<UInt8>] = [spsBase, ppsBase]
                let sizes: [Int] = [spsBuffer.count, ppsBuffer.count]
                return pointers.withUnsafeBufferPointer { pointerBuffer -> OSStatus in
                    sizes.withUnsafeBufferPointer { sizeBuffer -> OSStatus in
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 2,
                            parameterSetPointers: pointerBuffer.baseAddress!,
                            parameterSetSizes: sizeBuffer.baseAddress!,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &newFormatDescription
                        )
                    }
                }
            }
        }

        guard status == noErr, let newFormatDescription else {
            throw DecoderError.formatDescriptionCreationFailed(status)
        }
        formatDescription = newFormatDescription
    }

    func decode(_ frame: VideoFramePayload) {
        guard let formatDescription else { return }
        guard let sampleBuffer = Self.makeSampleBuffer(
            data: frame.sampleData,
            formatDescription: formatDescription,
            isKeyFrame: frame.isKeyFrame,
            presentationTime: CMTimebaseGetTime(timebase)
        ) else {
            Logging.decoder.error("Couldn't build a sample buffer for an incoming frame")
            return
        }

        if displayLayer?.status == .failed {
            displayLayer?.flush()
        }
        displayLayer?.enqueue(sampleBuffer)
    }

    private static func makeSampleBuffer(data: Data, formatDescription: CMFormatDescription, isKeyFrame: Bool, presentationTime: CMTime) -> CMSampleBuffer? {
        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let blockBuffer else { return nil }

        status = data.withUnsafeBytes { rawBuffer -> OSStatus in
            guard let baseAddress = rawBuffer.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
            return CMBlockBufferReplaceDataBytes(with: baseAddress, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: data.count)
        }
        guard status == noErr else { return nil }

        var timingInfo = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: presentationTime, decodeTimeStamp: .invalid)
        var sampleSize = data.count
        var sampleBuffer: CMSampleBuffer?

        status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else { return nil }

        if !isKeyFrame,
           let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) as? NSArray,
           let attachment = attachments.firstObject as? NSMutableDictionary {
            attachment[kCMSampleAttachmentKey_NotSync] = true
        }

        return sampleBuffer
    }
}
