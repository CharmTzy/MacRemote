import Foundation
import CoreGraphics

enum VideoScalingMode: Equatable {
    case aspectFit
    case aspectFill
}

enum VideoHorizontalAlignment: Equatable {
    case center
    case leading
}

/// Maps a touch point in the viewer's on-screen coordinate space to a
/// `NormalizedPoint` on the Mac's display. The mapping uses the same fit or
/// fill rule as the video layer so a visible pixel and its touch target stay
/// aligned even when aspect-fill crops part of the Mac display.
struct VideoContentGeometry: Equatable {
    /// The video's own pixel dimensions (from `VideoConfigPayload`), used
    /// only for its aspect ratio.
    let contentSize: CGSize
    /// The viewer's rendered size.
    let viewSize: CGSize
    let scalingMode: VideoScalingMode
    let horizontalAlignment: VideoHorizontalAlignment

    init(
        contentSize: CGSize,
        viewSize: CGSize,
        scalingMode: VideoScalingMode = .aspectFit,
        horizontalAlignment: VideoHorizontalAlignment = .center
    ) {
        self.contentSize = contentSize
        self.viewSize = viewSize
        self.scalingMode = scalingMode
        self.horizontalAlignment = horizontalAlignment
    }

    /// Where the video is actually drawn within the view.
    var contentRect: CGRect {
        guard contentSize.width > 0, contentSize.height > 0, viewSize.width > 0, viewSize.height > 0 else {
            return CGRect(origin: .zero, size: viewSize)
        }

        let horizontalScale = viewSize.width / contentSize.width
        let verticalScale = viewSize.height / contentSize.height
        let scale = scalingMode == .aspectFill
            ? max(horizontalScale, verticalScale)
            : min(horizontalScale, verticalScale)
        let renderedSize = CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
        return CGRect(
            x: horizontalAlignment == .leading ? 0 : (viewSize.width - renderedSize.width) / 2,
            y: (viewSize.height - renderedSize.height) / 2,
            width: renderedSize.width,
            height: renderedSize.height
        )
    }

    /// `nil` if `point` falls outside the rendered video. In aspect-fill the
    /// rendered rect extends beyond the view, so every on-screen point maps
    /// to the corresponding visible portion of the Mac display.
    func normalizedPoint(for point: CGPoint) -> NormalizedPoint? {
        let rect = contentRect
        // CGRect.contains excludes the maximum X/Y edges, but those edges are
        // valid screen coordinates and should map to the normalized value 1.
        guard rect.width > 0,
              rect.height > 0,
              point.x >= rect.minX,
              point.x <= rect.maxX,
              point.y >= rect.minY,
              point.y <= rect.maxY else { return nil }
        return NormalizedPoint(
            x: Double((point.x - rect.minX) / rect.width),
            y: Double((point.y - rect.minY) / rect.height)
        )
    }
}
