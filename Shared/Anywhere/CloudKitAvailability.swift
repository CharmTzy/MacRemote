import Foundation

/// Whether this build may legally talk to CloudKit. Free Personal Teams
/// can't sign apps with the iCloud capability, and constructing a
/// `CKContainer` anyway traps instantly (EXC_BREAKPOINT inside CloudKit) —
/// learned the hard way. So before any CloudKit call, we check whether the
/// provisioning profile that signed this build actually contains the
/// iCloud entitlement and treat CloudKit as unavailable when it doesn't.
///
/// Development/sideloaded builds (everything this project produces) embed
/// their provisioning profile as `embedded.mobileprovision`; the profile is
/// a CMS blob wrapping XML, so a byte-level key search is sufficient and
/// needs no CMS parsing.
enum CloudKitEntitlement {
    static let isAvailable: Bool = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else {
            return false
        }
        for key in [
            "com.apple.developer.icloud-services",
            "com.apple.developer.icloud-container-identifiers"
        ] {
            if data.range(of: Data(key.utf8)) != nil {
                return true
            }
        }
        return false
    }()
}
