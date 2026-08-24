import Foundation
import OSLog

/// Central place for every `Logger` the app uses, one per subsystem area, so
/// log output can be filtered by category in Console.app. Log messages
/// describe state transitions and failures — never per-frame or
/// per-mouse-move detail, and never credentials, keys, or pairing codes.
enum Logging {
    private static let subsystem = "com.macremote"

    static let network = Logger(subsystem: subsystem, category: "Network")
    static let discovery = Logger(subsystem: subsystem, category: "Discovery")
    static let pairing = Logger(subsystem: subsystem, category: "Pairing")
    static let security = Logger(subsystem: subsystem, category: "Security")
    static let capture = Logger(subsystem: subsystem, category: "Capture")
    static let encoder = Logger(subsystem: subsystem, category: "Encoder")
    static let decoder = Logger(subsystem: subsystem, category: "Decoder")
    static let input = Logger(subsystem: subsystem, category: "Input")
    static let session = Logger(subsystem: subsystem, category: "Session")
    static let anywhere = Logger(subsystem: subsystem, category: "Anywhere")
    static let power = Logger(subsystem: subsystem, category: "Power")
}
