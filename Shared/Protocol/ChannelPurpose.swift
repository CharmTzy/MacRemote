import Foundation

/// What a connection is for, declared in its `Hello`. A device opens one
/// `.control` connection per session (input, keyboard, clipboard, etc.) and
/// a separate `.video` connection for the screen stream, so a large video
/// frame can never queue in front of a mouse click — see ARCHITECTURE.md's
/// three-connection design. Both connection kinds run through the exact
/// same discovery/pairing/authentication flow; only post-auth handling
/// differs.
enum ChannelPurpose: UInt8, Sendable {
    case control = 1
    case video = 2
}
