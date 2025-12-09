// MainTabView.swift
import SwiftUI
import NDKSwift

public struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var hasNotifications = false

    private let ndk: NDK

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            FeedView(ndk: ndk)
                .tabItem {
                    Label("Home", systemImage: selectedTab == 0 ? "wave.3.up.circle.fill" : "wave.3.up.circle")
                }
                .tag(0)

            // Explore placeholder
            Text("Explore")
                .tabItem {
                    Label("Explore", systemImage: selectedTab == 1 ? "safari.fill" : "safari")
                }
                .tag(1)

            // Create placeholder
            Text("Create")
                .tabItem {
                    Label("", systemImage: "plus.app.fill")
                }
                .tag(2)

            // Notifications - only show if has notifications
            if hasNotifications {
                Text("Notifications")
                    .tabItem {
                        Label("Activity", systemImage: selectedTab == 3 ? "bell.fill" : "bell")
                    }
                    .tag(3)
            }

            // Profile placeholder
            Text("Profile")
                .tabItem {
                    Label("Profile", systemImage: selectedTab == 4 ? "person.fill" : "person")
                }
                .tag(4)
        }
        .tint(OlasTheme.Colors.deepTeal)
    }
}
