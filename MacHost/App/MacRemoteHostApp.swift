import SwiftUI

@main
struct MacRemoteHostApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 720, height: 480)
    }
}
