import Foundation
import VideoToolbox
import CoreMedia
import OSLog

/// Wraps `VTCompressionSession` for real-time H.264 encoding. One encoder
/// per capture session — resolution changes need a new instance rather than
/// reconfiguring this one.
///
/// This file is the single riskiest piece of Core Media/VideoToolbox glue
/// in the project: the C-callback bridging and raw buffer extraction here
/// are exactly the kind of code that's easy to get subtly wrong without a
/// compiler to check it against. If the build has trouble anywhere, look
/// here first.
final class H264Encoder {
    struct EncodedFrame {
        let isKeyFrame: Bool
        let sampleData: Data
    }

    enum EncoderError: Error {
        case creationFailed(OSStatus)
    }

    private var session: VTCompressionSession?
    private let width: Int32
    private let height: Int32
    private var onParameterSets: ((_ sps: Data, _ pps: Data) -> Void)?
    private var onEncodedFrame: ((EncodedFrame) -> Void)?
    private var sentParameterSets = false

    init(width: Int32, height: Int32) {
        self.width = width
        self.height = height
    }

    func start(
        averageBitRate: Int = 6_000_000,
        expectedFrameRate: Int = 30,
        onParameterSets: @escaping (_ sps: Data, _ pps: Data) -> Void,
        onEncodedFrame: @escaping (EncodedFrame) -> Void
    ) throws {
        self.onParameterSets = onParameterSets
        self.onEncodedFrame = onEncodedFrame
        sentParameterSets = false

        var newSession: VTCompressionSession?
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: Self.outputCallback,
            refcon: selfPointer,
            compressionSessionOut: &newSession
        )
        guard status == noErr, let compressionSession = newSession else {
            throw EncoderError.creationFailed(status)
        }

        VTSessionSetProperty(compressionSession, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(compressionSession, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
        VTSessionSetProperty(compressionSession, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(compressionSession, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: expectedFrameRate * 3))
        VTSessionSetProperty(compressionSession, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: averageBitRate))
        VTSessionSetProperty(compressionSession, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: expectedFrameRate))
        VTCompressionSessionPrepareToEncodeFrames(compressionSession)

        session = compressionSession
        Logging.encoder.info("H.264 encoder started at \(self.width)x\(self.height), \(averageBitRate) bps target")
    }

    func encode(_ pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime) {
        guard let session else { return }
        var flags = VTEncodeInfoFlags()
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: .invalid,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: &flags
        )
        if status != noErr {
            Logging.encoder.error("Encode frame failed: \(status)")
        }
    }

    func stop() {
        guard let session else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(session)
        self.session = nil
        Logging.encoder.info("H.264 encoder stopped")
    }

    // MARK: - Output callback

    private static let outputCallback: VTCompressionOutputCallback = { refcon, _, status, _, sampleBuffer in
        guard status == noErr, let sampleBuffer, let refcon else { return }
        let encoder = Unmanaged<H264Encoder>.fromOpaque(refcon).takeUnretainedValue()
        encoder.handleEncodedSampleBuffer(sampleBuffer)
    }

    private func handleEncodedSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid, let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        if !sentParameterSets, let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
           let parameterSets = Self.extractParameterSets(from: formatDescription) {
            sentParameterSets = true
            onParameterSets?(parameterSets.sps, parameterSets.pps)
        }

        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        guard status == noErr, let dataPointer else { return }

        let sampleData = Data(bytes: dataPointer, count: totalLength)
        onEncodedFrame?(EncodedFrame(isKeyFrame: Self.isKeyFrame(sampleBuffer), sampleData: sampleData))
    }

    private static func isKeyFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? NSArray,
              let attachment = attachments.firstObject as? NSDictionary else {
            return true
        }
        let notSync = (attachment[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false
        return !notSync
    }

    /// AVCC parameter sets (no start codes) — matches the framing
    /// `VTCompressionSession` already uses for the sample data itself, so
    /// nothing here needs Annex-B conversion. See PROTOCOL.md.
    private static func extractParameterSets(from formatDescription: CMFormatDescription) -> (sps: Data, pps: Data)? {
        var spsPointer: UnsafePointer<UInt8>?
        var spsSize = 0
        var status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescription,
            parameterSetIndex: 0,
            parameterSetPointerOut: &spsPointer,
            parameterSetSizeOut: &spsSize,
            parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: nil
        )
        guard status == noErr, let spsPointer else { return nil }

        var ppsPointer: UnsafePointer<UInt8>?
        var ppsSize = 0
        status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescription,
            parameterSetIndex: 1,
            parameterSetPointerOut: &ppsPointer,
            parameterSetSizeOut: &ppsSize,
            parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: nil
        )
        guard status == noErr, let ppsPointer else { return nil }

        return (Data(bytes: spsPointer, count: spsSize), Data(bytes: ppsPointer, count: ppsSize))
    }
}
