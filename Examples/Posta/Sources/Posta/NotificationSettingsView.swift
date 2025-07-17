import SwiftUI

struct NotificationSettingsView: View {
    @AppStorage("notifications_enabled") private var notificationsEnabled = true
    @AppStorage("notify_mentions") private var notifyMentions = true
    @AppStorage("notify_replies") private var notifyReplies = true
    @AppStorage("notify_reposts") private var notifyReposts = true
    @AppStorage("notify_likes") private var notifyLikes = true
    @AppStorage("notify_follows") private var notifyFollows = true
    @AppStorage("notify_dms") private var notifyDMs = true
    @AppStorage("notification_sound") private var notificationSound = true
    @AppStorage("notification_vibrate") private var notificationVibrate = true
    
    var body: some View {
        List {
            // Master Toggle
            Section {
                Toggle(isOn: $notificationsEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Notifications")
                        Text("Receive push notifications")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Notification Types
            Section {
                Toggle(isOn: $notifyMentions) {
                    Label("Mentions", systemImage: "at")
                }
                .disabled(!notificationsEnabled)
                
                Toggle(isOn: $notifyReplies) {
                    Label("Replies", systemImage: "bubble.left")
                }
                .disabled(!notificationsEnabled)
                
                Toggle(isOn: $notifyReposts) {
                    Label("Reposts", systemImage: "arrow.2.squarepath")
                }
                .disabled(!notificationsEnabled)
                
                Toggle(isOn: $notifyLikes) {
                    Label("Likes", systemImage: "heart")
                }
                .disabled(!notificationsEnabled)
                
                Toggle(isOn: $notifyFollows) {
                    Label("New Followers", systemImage: "person.badge.plus")
                }
                .disabled(!notificationsEnabled)
                
                Toggle(isOn: $notifyDMs) {
                    Label("Direct Messages", systemImage: "envelope")
                }
                .disabled(!notificationsEnabled)
            } header: {
                Text("Notification Types")
            }
            
            // Notification Behavior
            Section {
                Toggle(isOn: $notificationSound) {
                    Label("Sound", systemImage: "speaker.wave.2")
                }
                .disabled(!notificationsEnabled)
                
                Toggle(isOn: $notificationVibrate) {
                    Label("Vibration", systemImage: "iphone.radiowaves.left.and.right")
                }
                .disabled(!notificationsEnabled)
                
                HStack {
                    Label("Quiet Hours", systemImage: "moon")
                    Spacer()
                    Text("Off")
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .opacity(notificationsEnabled ? 1.0 : 0.6)
            } header: {
                Text("Behavior")
            }
            
            // Advanced
            Section {
                Button(action: openNotificationSettings) {
                    HStack {
                        Text("System Notification Settings")
                        Spacer()
                        Image(systemName: "arrow.up.forward.square")
                            .font(.caption)
                    }
                }
                .foregroundColor(.primary)
            } footer: {
                Text("Manage system-level notification permissions and settings")
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
    }
    
    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}