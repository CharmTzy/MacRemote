import Foundation
import Network
import OSLog
import Combine

/// Sends one file at a time to a Mac over a dedicated `.file`-purpose
/// connection (opened fresh per transfer, closed when it's done), so a
/// large file never queues in front of a mouse click on the control
/// connection. iPhone → Mac only — see `FileReceiver`'s doc comment on the
/// Mac side for why the other direction isn't wired up.
@MainActor
final class FileTransferViewModel: ObservableObject {
    @Published private(set) var activeTransfer: FileTransferProgress?

    private let chunkSize = 256 * 1024

    func send(fileURL: URL, to endpoint: NWEndpoint) {
        guard activeTransfer == nil else { return }

        let transferID = UUID()
        let filename = fileURL.lastPathComponent

        Task {
            let isAccessingSecurityScope = fileURL.startAccessingSecurityScopedResource()
            defer {
                if isAccessingSecurityScope { fileURL.stopAccessingSecurityScopedResource() }
            }

            guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let fileSize = attributes[.size] as? UInt64,
                  let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
                self.activeTransfer = FileTransferProgress(transferID: transferID, filename: filename, totalBytes: 0, transferredBytes: 0, isComplete: false, failureReason: "Couldn't read the file.")
                return
            }
            defer { try? fileHandle.close() }

            self.activeTransfer = FileTransferProgress(transferID: transferID, filename: filename, totalBytes: fileSize, transferredBytes: 0, isComplete: false, failureReason: nil)

            let connection = RemoteConnection()
            do {
                let result = try await connection.connect(to: endpoint, purpose: .file)
                guard case .authenticated = result else {
                    self.fail(transferID, filename: filename, totalBytes: fileSize, reason: "This Mac needs to be paired again before it can receive files.")
                    await connection.close()
                    return
                }

                try await connection.send(.fileOffer(FileOfferPayload(transferID: transferID, filename: filename, fileSize: fileSize)))

                var offset: UInt64 = 0
                while true {
                    let chunk = fileHandle.readData(ofLength: self.chunkSize)
                    if chunk.isEmpty { break }
                    try await connection.send(.fileChunk(FileChunkPayload(transferID: transferID, offset: offset, data: chunk)))
                    offset += UInt64(chunk.count)
                    self.activeTransfer = FileTransferProgress(transferID: transferID, filename: filename, totalBytes: fileSize, transferredBytes: offset, isComplete: false, failureReason: nil)
                }

                try await connection.send(.fileComplete(FileCompletePayload(transferID: transferID)))
                self.activeTransfer = FileTransferProgress(transferID: transferID, filename: filename, totalBytes: fileSize, transferredBytes: offset, isComplete: true, failureReason: nil)
            } catch {
                Logging.session.error("File send failed: \(String(describing: error), privacy: .public)")
                self.fail(transferID, filename: filename, totalBytes: fileSize, reason: "Couldn't send the file. Make sure the Mac is still connected.")
            }
            await connection.close()
        }
    }

    func dismiss() {
        activeTransfer = nil
    }

    private func fail(_ transferID: UUID, filename: String, totalBytes: UInt64, reason: String) {
        activeTransfer = FileTransferProgress(transferID: transferID, filename: filename, totalBytes: totalBytes, transferredBytes: 0, isComplete: false, failureReason: reason)
    }
}
