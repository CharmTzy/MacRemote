import SwiftUI
import UIKit
import AVFoundation

/// A `UIView` whose backing `CALayer` is directly an
/// `AVSampleBufferDisplayLayer`, per Apple's standard pattern for
/// layer-backed custom views.
final class SampleBufferHostView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    var displayLayer: AVSampleBufferDisplayLayer {
        // Safe by construction: `layerClass` above guarantees `layer` is
        // exactly this type.
        layer as! AVSampleBufferDisplayLayer
    }
}

/// Bridges `SampleBufferHostView` into SwiftUI and hands its display layer
/// to the decoder that will enqueue frames into it.
struct SampleBufferDisplayView: UIViewRepresentable {
    let decoder: VideoDecoder

    func makeUIView(context: Context) -> SampleBufferHostView {
        let view = SampleBufferHostView()
        view.displayLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        decoder.displayLayer = view.displayLayer
        return view
    }

    func updateUIView(_ uiView: SampleBufferHostView, context: Context) {}
}
