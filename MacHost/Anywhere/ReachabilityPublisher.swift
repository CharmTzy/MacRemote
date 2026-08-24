import Foundation
import CloudKit
import OSLog

/// Publishes this Mac's current reachability to the signed-in Apple ID's
/// *private* iCloud database — the rendezvous point that lets an iPhone on
/// a different network find it. Nothing here is shared with anyone else,
/// nothing is secret (addresses only), and knowing them authenticates
/// nothing: sessions still require proving possession of the paired
/// Ed25519 private key.
struct ReachabilityPublisher {
    static let recordType = "MacReachability"

    private let database: CKDatabase?

    /// Thrown when iCloud/CloudKit can't be reached at all (not signed in,
    /// container unavailable) — surfaced as status text, not a crash.
    struct UnavailableError: LocalizedError {
        var errorDescription: String? { "iCloud isn't available for this Mac (are you signed in?)." }
    }

    init() {
        // Constructing CKContainer without the iCloud entitlement traps the
        // process (see CloudKitEntitlement) — only touch it when entitled.
        database = CloudKitEntitlement.isAvailable
            ? try? CKContainer(identifier: ServiceConstants.cloudContainerIdentifier).privateCloudDatabase
            : nil
    }

    var isAvailable: Bool { database != nil }

    func publish(deviceID: UUID, name: String, model: String, snapshot: ReachabilitySnapshot) async throws {
        guard let database else {
            throw UnavailableError()
        }
        let recordID = CKRecord.ID(recordName: deviceID.uuidString)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["name"] = name as NSString
        record["model"] = model as NSString
        record["protocolVersion"] = Int(ProtocolVersion.current) as NSNumber
        record["lanIPv4"] = snapshot.lanIPv4Address.map { $0 as NSString }
        record["wanIPv4"] = snapshot.wanIPv4Address.map { $0 as NSString }
        record["externalPort"] = snapshot.externalPort.map { Int($0) as NSNumber }
        record["ipv6Addresses"] = snapshot.ipv6Addresses as NSArray
        record["updatedAt"] = Date() as NSDate

        _ = try await database.save(record)
        Logging.anywhere.info("Published reachability record to iCloud")
    }

    func remove(deviceID: UUID) async {
        guard let database else { return }
        try? await database.deleteRecord(withID: CKRecord.ID(recordName: deviceID.uuidString))
    }
}
