#if os(macOS)
import Foundation

/// Raw hardware model identifier (e.g. "Mac15,6"), read via `sysctl`. There
/// is no public API for the marketing name ("MacBook Air"), so the UI shows
/// this identifier as-is under the "Model" label.
enum MacModelInfo {
    static func modelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        let result = sysctlbyname("hw.model", &buffer, &size, nil, 0)
        guard result == 0 else { return "Mac" }
        return String(cString: buffer)
    }
}
#endif
