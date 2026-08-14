import Foundation
import CoreGraphics

/// Maps a touch point in the viewer's on-screen coordinate space to a
/// `NormalizedPoint` on the Mac's display, accounting for letterboxing —
/// the video is drawn with `.resizeAspect`, so it rarely fills the whole
/// view edge to edge, and a touch outside the actual video content isn't a
/// point on the Mac's screen at all.
struct VideoContentGeometry: Equatable {
    /// The video's own pixel dimensions (from `VideoConfigPayload`), used
    /// only for its aspect ratio.
    let contentSize: CGSize
    /// The viewer's rendered size.
    let viewSize: CGSize

    /// Where the video is actually drawn within the view.
    var contentRect: CGRect {
        guard contentSize.width > 0, contentSize.height > 0, viewSize.width > 0, viewSize.height > 0 else {
            return CGRect(origin: .zero, size: viewSize)
        }

        let contentAspect = contentSize.width / contentSize.height
        let viewAspect = viewSize.width / viewSize.height

        if contentAspect > viewAspect {
            let height = viewSize.width / contentAspect
            return CGRect(x: 0, y: (viewSize.height - height) / 2, width: viewSize.width, height: height)
        } else {
            let width = viewSize.height * contentAspect
            return CGRect(x: (viewSize.width - width) / 2, y: 0, width: width, height: viewSize.height)
        }
    }

    /// `nil` if `point` falls in the letterboxed margin rather than on the
    /// video itself.
    func normalizedPoint(for point: CGPoint) -> NormalizedPoint? {
        let rect = contentRect
        guard rect.width > 0, rect.height > 0, rect.contains(point) else { return nil }
        return NormalizedPoint(
            x: Double((point.x - rect.minX) / rect.width),
            y: Double((point.y - rect.minY) / rect.height)
        )
    }
}
