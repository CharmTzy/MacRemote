import SwiftUI

struct MacsListView: View {
    @StateObject private var discovery = DiscoveryViewModel()
    @State private var showingAddByIP = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                BrandTheme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        hero

                        HStack {
                            Text("YOUR MACS")
                                .font(.caption.weight(.bold))
                                .tracking(1.2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if discovery.isSearching {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.mini).tint(BrandTheme.cyan)
                                    Text("Searching")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }

                        if discovery.discoveredMacs.isEmpty {
                            emptyState
                        } else {
                            ForEach(discovery.discoveredMacs) { mac in
                                NavigationLink(value: mac) {
                                    MacCard(mac: mac)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button {
                            showingAddByIP = true
                        } label: {
                            Label("Connect by IP Address", systemImage: "plus.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .brandCard(cornerRadius: 18)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Mac Remote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: DiscoveredMac.self) { mac in
                MacDetailView(mac: mac)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingAddByIP) { AddByIPView() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .onAppear { discovery.start() }
            .onDisappear { discovery.stop() }
        }
        .tint(BrandTheme.cyan)
    }

    private var hero: some View {
        HStack(spacing: 15) {
            Image(systemName: "rectangle.connected.to.line.below")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 58, height: 58)
                .background(BrandTheme.accentGradient, in: RoundedRectangle(cornerRadius: 17, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Your Mac, anywhere")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Text("Private, encrypted control — same Wi-Fi or over the internet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 30))
                .foregroundStyle(BrandTheme.cyan)
            Text(discovery.isSearching ? "Looking for your Mac…" : "No Macs found")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Keep both devices on the same Wi-Fi network for the first pairing — after that, your paired Mac can be reached from anywhere.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .brandCard()
    }
}

private struct MacCard: View {
    let mac: DiscoveredMac

    private var isOnline: Bool { mac.state == .available }

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "macbook")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                Circle()
                    .fill(isOnline ? Color.green : Color.orange)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(BrandTheme.graphite, lineWidth: 2))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(mac.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(mac.model ?? "Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(availabilityLabel)
                    .font(.caption2.weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(availabilityColor)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .brandCard()
        .accessibilityElement(children: .combine)
    }

    private var availabilityLabel: String {
        if isOnline { return "READY" }
        return mac.internetCandidates.isEmpty ? "OFFLINE" : "VIA INTERNET"
    }

    private var availabilityColor: Color {
        if isOnline { return BrandTheme.cyan }
        return mac.internetCandidates.isEmpty ? Color.orange : Color.green
    }
}

#Preview { MacsListView() }
