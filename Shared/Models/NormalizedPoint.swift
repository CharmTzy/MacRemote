import Foundation
import CoreGraphics

/// A position expressed as a fraction of the Mac's display, independent of
/// either device's actual resolution: `(0, 0)` is the top-left corner,
/// `(1, 1)` the bottom-right. The iPhone converts a touch to this before
/// sending it; the Mac converts it back to real pixels before posting a
/// `CGEvent`. Encoded as two `Float32`s on the wire — input messages are
/// high-frequency, and screen-position precision doesn't need `Double`.
struct NormalizedPoint: Sendable, Equatable {
    let x: Double
    let y: Double

    func encode(into writer: inout ByteWriter) {
        writer.writeFloat(Float(x))
        writer.writeFloat(Float(y))
    }

    static func decode(from reader: inout ByteReader) throws -> NormalizedPoint {
        NormalizedPoint(x: Double(try reader.readFloat()), y: Double(try reader.readFloat()))
    }

    /// Maps this point onto a real pixel rect, e.g. a display's bounds.
    func pixelPoint(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.origin.x + x * rect.width, y: rect.origin.y + y * rect.height)
    }
}
