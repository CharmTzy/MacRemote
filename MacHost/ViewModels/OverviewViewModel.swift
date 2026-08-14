import Foundation
import Combine

@MainActor
final class OverviewViewModel: ObservableObject {
    @Published private(set) var computerName = DeviceIdentity.localDeviceName
    @Published private(set) var modelIdentifier = DeviceIdentity.localDeviceModel
    @Published private(set) var ipAddress: String?

    func refresh() {
        ipAddress = LocalNetworkInfo.primaryIPv4Address()
    }
}
