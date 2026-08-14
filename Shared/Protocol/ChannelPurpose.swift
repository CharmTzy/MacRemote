import Foundation

/// What a connection is for, declared in its `Hello`. A device opens one
/// `.control` connection per session (input, keyboard, clipboard, etc.), a
/// separate `.video` connection for the screen stream, and a `.file`
/// connection per file transfer — so a large video frame or file chunk can
/// never queue in front of a mouse click. See ARCHITECTURE.md's
/// three-connection design. All three kinds run through the exact same
/// discovery/pairing/authentication flow; only post-auth handling differs.
enum ChannelPurpose: UInt8, Sendable {
    case control = 1
    case video = 2
    case file = 3
}
