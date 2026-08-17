import SwiftUI

@main
struct MacRemoteApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if CommandLine.arguments.contains("--demo-remote-control") {
                RemoteControlDemoView()
            } else {
                MacsListView()
            }
            #else
            MacsListView()
            #endif
        }
    }
}
