import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case devices = "Devices"
    case display = "Display"
    case permissions = "Permissions"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .overview: return "macbook"
        case .devices: return "iphone"
        case .display: return "display"
        case .permissions: return "lock.shield"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @StateObject private var sessionManager = HostSessionManager()
    @State private var selection: SidebarSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "rectangle.connected.to.line.below")
                        .font(.title2)
                        .foregroundStyle(BrandTheme.blue)
                    Text("MAC REMOTE")
                        .font(.caption.weight(.bold))
                        .tracking(1)
                    Text("Private local control")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)

                ForEach(SidebarSection.allCases) { section in
                    Label(section.rawValue, systemImage: section.systemImage)
                        .tag(section)
                }
            }
            .navigationTitle("Mac Remote")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selection {
            case .overview, .none:
                OverviewView().environmentObject(sessionManager)
            case .devices:
                DevicesView().environmentObject(sessionManager)
            case .display:
                DisplayView()
            case .permissions:
                PermissionsView()
            case .settings:
                SettingsView().environmentObject(sessionManager)
            }
        }
        .tint(BrandTheme.blue)
        .onAppear { sessionManager.start() }
    }
}

#Preview {
    ContentView()
}
