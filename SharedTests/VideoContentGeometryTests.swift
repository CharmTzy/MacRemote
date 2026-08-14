import XCTest
import Foundation
import CoreGraphics

final class VideoContentGeometryTests: XCTestCase {
    func testMatchingAspectRatioFillsWholeView() {
        let geometry = VideoContentGeometry(contentSize: CGSize(width: 1920, height: 1080), viewSize: CGSize(width: 960, height: 540))
        XCTAssertEqual(geometry.contentRect, CGRect(x: 0, y: 0, width: 960, height: 540))
    }

    func testWiderContentLetterboxesTopAndBottom() {
        // 16:9 content in a taller-than-wide (portrait phone) view.
        let geometry = VideoContentGeometry(contentSize: CGSize(width: 1920, height: 1080), viewSize: CGSize(width: 800, height: 800))
        let rect = geometry.contentRect
        XCTAssertEqual(rect.width, 800, accuracy: 0.01)
        XCTAssertEqual(rect.height, 450, accuracy: 0.01)
        XCTAssertEqual(rect.origin.x, 0, accuracy: 0.01)
        XCTAssertEqual(rect.origin.y, 175, accuracy: 0.01)
    }

    func testTallerContentPillarboxesLeftAndRight() {
        let geometry = VideoContentGeometry(contentSize: CGSize(width: 1080, height: 1920), viewSize: CGSize(width: 800, height: 800))
        let rect = geometry.contentRect
        XCTAssertEqual(rect.height, 800, accuracy: 0.01)
        XCTAssertEqual(rect.width, 450, accuracy: 0.01)
        XCTAssertEqual(rect.origin.y, 0, accuracy: 0.01)
        XCTAssertEqual(rect.origin.x, 175, accuracy: 0.01)
    }

    func testNormalizedPointAtCenterAndCorners() {
        let geometry = VideoContentGeometry(contentSize: CGSize(width: 1920, height: 1080), viewSize: CGSize(width: 960, height: 540))

        let center = geometry.normalizedPoint(for: CGPoint(x: 480, y: 270))
        XCTAssertEqual(center?.x ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(center?.y ?? -1, 0.5, accuracy: 0.001)

        let topLeft = geometry.normalizedPoint(for: CGPoint(x: 0, y: 0))
        XCTAssertEqual(topLeft?.x ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(topLeft?.y ?? -1, 0, accuracy: 0.001)

        let bottomRight = geometry.normalizedPoint(for: CGPoint(x: 960, y: 540))
        XCTAssertEqual(bottomRight?.x ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(bottomRight?.y ?? -1, 1, accuracy: 0.001)
    }

    func testPointInLetterboxMarginReturnsNil() {
        let geometry = VideoContentGeometry(contentSize: CGSize(width: 1920, height: 1080), viewSize: CGSize(width: 800, height: 800))
        // Content rect is y: 175...625 (see testWiderContentLetterboxesTopAndBottom); y=50 is in the top margin.
        XCTAssertNil(geometry.normalizedPoint(for: CGPoint(x: 400, y: 50)))
    }
}
