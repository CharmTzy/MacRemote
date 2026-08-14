import Foundation
import OSLog

/// Receives one incoming file transfer on a `.file`-purpose connection and
/// writes it to `~/Downloads/Mac Remote/`.
///
/// iPhone → Mac only: this project's connection model always has the
/// iPhone dialing the Mac (see ARCHITECTURE.md), so a Mac-initiated push
/// to the iPhone isn't wired up — see README.md's status note for that
/// scope decision.
actor FileReceiver {
    private let transport: MessageTransport
    private var session: SecureSession

    init(transport: MessageTransport, session: SecureSession) {
        self.transport = transport
        self.session = session
    }

    func receive(
        iterator: inout AsyncStream<TransportEvent>.Iterator,
        onProgress: @escaping (FileTransferProgress) -> Void
    ) async {
        guard let offer = await nextFilePayload(&iterator, as: { if case .fileOffer(let payload) = $0 { return payload } else { return nil } }) else {
            return
        }

        guard let destinationURL = try? Self.prepareDestination(for: offer.filename),
              FileManager.default.createFile(atPath: destinationURL.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: destinationURL) else {
            Logging.session.error("Couldn't prepare a destination for incoming file \(offer.filename, privacy: .public)")
            return
        }
        defer { try? handle.close() }

        var received: UInt64 = 0
        onProgress(FileTransferProgress(transferID: offer.transferID, filename: offer.filename, totalBytes: offer.fileSize, transferredBytes: 0, isComplete: false, failureReason: nil))

        while let event = await iterator.next() {
            switch event {
            case .message(let message):
                guard case .secureEnvelope(let sealed) = message,
                      let plaintext = try? session.open(counter: sealed.counter, combined: sealed.combined),
                      let inner = try? ProtocolMessage.decodeInner(plaintext) else {
                    continue
                }
                switch inner {
                case .fileChunk(let chunk) where chunk.transferID == offer.transferID:
                    handle.write(chunk.data)
                    received += UInt64(chunk.data.count)
                    onProgress(FileTransferProgress(transferID: offer.transferID, filename: offer.filename, totalBytes: offer.fileSize, transferredBytes: received, isComplete: false, failureReason: nil))
                case .fileComplete(let complete) where complete.transferID == offer.transferID:
                    Logging.session.info("Received file \(offer.filename, privacy: .public)")
                    onProgress(FileTransferProgress(transferID: offer.transferID, filename: offer.filename, totalBytes: offer.fileSize, transferredBytes: received, isComplete: true, failureReason: nil))
                    return
                default:
                    continue
                }
            case .failed, .cancelled:
                onProgress(FileTransferProgress(transferID: offer.transferID, filename: offer.filename, totalBytes: offer.fileSize, transferredBytes: received, isComplete: false, failureReason: "The connection closed before the file finished."))
                return
            case .ready:
                continue
            }
        }
    }

    private func nextFilePayload<T>(
        _ iterator: inout AsyncStream<TransportEvent>.Iterator,
        as extract: (ProtocolMessage) -> T?
    ) async -> T? {
        while let event = await iterator.next() {
            switch event {
            case .message(let message):
                guard case .secureEnvelope(let sealed) = message,
                      let plaintext = try? session.open(counter: sealed.counter, combined: sealed.combined),
                      let inner = try? ProtocolMessage.decodeInner(plaintext) else {
                    continue
                }
                if let value = extract(inner) { return value }
            case .failed, .cancelled:
                return nil
            case .ready:
                continue
            }
        }
        return nil
    }

    /// Picks `~/Downloads/Mac Remote/<filename>`, appending " 2", " 3", ...
    /// before the extension if that name is already taken.
    private static func prepareDestination(for filename: String) throws -> URL {
        let downloadsURL = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folderURL = downloadsURL.appendingPathComponent("Mac Remote", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let baseName = (filename as NSString).deletingPathExtension
        let extensionName = (filename as NSString).pathExtension

        var candidate = folderURL.appendingPathComponent(filename)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let candidateName = extensionName.isEmpty ? "\(baseName) \(suffix)" : "\(baseName) \(suffix).\(extensionName)"
            candidate = folderURL.appendingPathComponent(candidateName)
            suffix += 1
        }
        return candidate
    }
}
