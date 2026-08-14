import Foundation

/// UI-facing snapshot of one file transfer's progress. Not a wire type —
/// built locally on each side from the `fileOffer`/`fileChunk`/
/// `fileComplete` messages it observes.
struct FileTransferProgress: Identifiable, Equatable, Sendable {
    let transferID: UUID
    let filename: String
    let totalBytes: UInt64
    let transferredBytes: UInt64
    let isComplete: Bool
    let failureReason: String?

    var id: UUID { transferID }

    var fractionComplete: Double {
        guard totalBytes > 0 else { return isComplete ? 1 : 0 }
        return min(1, Double(transferredBytes) / Double(totalBytes))
    }
}
