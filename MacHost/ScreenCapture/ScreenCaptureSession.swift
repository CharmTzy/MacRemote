import Foundation
import ScreenCaptureKit
import CoreMedia
import OSLog

/// Captures one display's contents via ScreenCaptureKit and hands raw
/// frames to a callback. Owns only capture — encoding happens in
/// `H264Encoder`, kept separate so either can be tested/replaced on its own.
final class ScreenCaptureSession: NSObject, SCStreamOutput, SCStreamDelegate {
    enum CaptureError: Error {
        case streamCreationFailed
    }

    private var stream: SCStream?
    private let outputQueue = DispatchQueue(label: "com.macremote.capture.output")
    private var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
    private var onStopped: ((Error?) -> Void)?

    func start(
        display: SCDisplay,
        frameRate: Int,
        onFrame: @escaping (CVPixelBuffer, CMTime) -> Void,
        onStopped: @escaping (Error?) -> Void
    ) async throws {
        self.onFrame = onFrame
        self.onStopped = onStopped

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.queueDepth = 5

        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        try await newStream.startCapture()
        stream = newStream

        Logging.capture.info("Started capturing display \(display.displayID) at \(display.width)x\(display.height)")
    }

    func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
        Logging.capture.info("Stopped capture")
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        onFrame?(imageBuffer, timestamp)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Logging.capture.error("Capture stream stopped: \(String(describing: error), privacy: .public)")
        onStopped?(error)
    }
}
