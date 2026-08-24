import Foundation
import CloudKit
import Combine
import OSLog

/// Reads every paired Mac's published reachability record from iCloud (the
/// user's private database) so the app can offer "connect from anywhere"
/// even when Bonjour can't see the Mac. Refreshed whenever the Macs list
/// appears; cheap — one batched fetch of a handful of records.
///
/// Records are keyed by the Mac's device UUID, which is exactly what the
/// trust store already keys pairs by, so no extra identity machinery is
/// involved. The snapshot only ever contains network addresses.
@MainActor
final class AnywhereDirectory: ObservableObject {
    @Published private(set) var snapshots: [UUID: ReachabilitySnapshot] = [:]
    @Published private(set) var isFetching = false

    private let database: CKDatabase?

    init() {
        // Constructing CKContainer without the iCloud entitlement traps the
        // process (see CloudKitEntitlement) — only touch it when entitled.
        database = CloudKitEntitlement.isAvailable
            ? try? CKContainer(identifier: ServiceConstants.cloudContainerIdentifier).privateCloudDatabase
            : nil
    }

    func snapshot(for deviceID: UUID) -> ReachabilitySnapshot? {
        snapshots[deviceID]
    }

    func refresh(for deviceIDs: [UUID]) async {
        guard !deviceIDs.isEmpty else {
            snapshots = [:]
            return
        }
        guard let database else { return }
        isFetching = true
        defer { isFetching = false }

        let recordIDs = deviceIDs.map { CKRecord.ID(recordName: $0.uuidString) }
        do {
            let results = try await database.records(for: recordIDs)
            var fetched: [UUID: ReachabilitySnapshot] = [:]
            for (id, result) in results {
                guard case .success(let record) = result,
                      let uuid = UUID(uuidString: id.recordName),
                      let snapshot = Self.snapshot(from: record) else { continue }
                fetched[uuid] = snapshot
            }
            snapshots = fetched
        } catch {
            // Not signed in, offline, or account changed — fall back to the
            // endpoints remembered from past direct sessions.
            Logging.session.info("iCloud reachability fetch unavailable: \(String(describing: error), privacy: .public)")
        }
    }

    static func snapshot(from record: CKRecord) -> ReachabilitySnapshot? {
        guard let updatedAt = record["updatedAt"] as? Date else { return nil }
        // Ignore records older than 7 days — a Mac publishing nothing that
        // long has probably moved networks or been retired.
        guard Date().timeIntervalSince(updatedAt) < 60 * 60 * 24 * 7 else { return nil }

        return ReachabilitySnapshot(
            lanIPv4Address: record["lanIPv4"] as? String,
            wanIPv4Address: record["wanIPv4"] as? String,
            externalPort: (record["externalPort"] as? NSNumber).map { UInt16(truncatingIfNeeded: $0.intValue) },
            ipv6Addresses: (record["ipv6Addresses"] as? [String]) ?? []
        )
    }
}
