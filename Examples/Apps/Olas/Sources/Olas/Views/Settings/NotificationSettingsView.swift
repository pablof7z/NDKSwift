import SwiftUI

struct NotificationSettingsView: View {
    @State private var pushNotificationsEnabled = true
    @State private var newFollowers = true
    @State private var mentions = true
    @State private var replies = true
    @State private var zaps = true
    @State private var directMessages = true
    @State private var showSoundSettings = false
    @State private var selectedSound = "Default"
    
    private let notificationSounds = ["Default", "Chime", "Pop", "Ding", "None"]
    
    var body: some View {
        ZStack {
            OlasDesign.Colors.background
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: OlasDesign.Spacing.xl) {
                    // Master toggle
                    masterToggleSection
                    
                    if pushNotificationsEnabled {
                        // Notification types
                        notificationTypesSection
                        
                        // Sound settings
                        soundSettingsSection
                        
                        // Quiet hours
                        quietHoursSection
                    }
                }
                .padding(OlasDesign.Spacing.lg)
            }
        }
        .navigationTitle("Notifications")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .sheet(isPresented: $showSoundSettings) {
            soundSelectionSheet
        }
    }
    
    // MARK: - Sections
    
    @ViewBuilder
    private var masterToggleSection: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: OlasDesign.Spacing.xs) {
                    Text("Push Notifications")
                        .font(OlasDesign.Typography.body)
                        .foregroundColor(OlasDesign.Colors.text)
                    
                    Text("Get notified about activity")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $pushNotificationsEnabled)
                    .tint(OlasDesign.Colors.primary)
            }
            .padding(OlasDesign.Spacing.md)
            .background(OlasDesign.Colors.surface)
            .cornerRadius(12)
        }
        .onChange(of: pushNotificationsEnabled) { _, enabled in
            OlasDesign.Haptic.selection()
            if enabled {
                requestNotificationPermission()
            }
        }
    }
    
    @ViewBuilder
    private var notificationTypesSection: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
            Text("Notification Types")
                .font(OlasDesign.Typography.title3)
                .foregroundColor(OlasDesign.Colors.text)
            
            VStack(spacing: 0) {
                notificationToggle(
                    title: "New Followers",
                    subtitle: "When someone follows you",
                    icon: "person.badge.plus",
                    isOn: $newFollowers
                )
                
                Divider()
                    .background(OlasDesign.Colors.border)
                    .padding(.leading, 46)
                
                notificationToggle(
                    title: "Mentions",
                    subtitle: "When you're @mentioned",
                    icon: "at",
                    isOn: $mentions
                )
                
                Divider()
                    .background(OlasDesign.Colors.border)
                    .padding(.leading, 46)
                
                notificationToggle(
                    title: "Replies",
                    subtitle: "Responses to your posts",
                    icon: "bubble.left",
                    isOn: $replies
                )
                
                Divider()
                    .background(OlasDesign.Colors.border)
                    .padding(.leading, 46)
                
                notificationToggle(
                    title: "Zaps",
                    subtitle: "Lightning payments received",
                    icon: "bolt.fill",
                    isOn: $zaps
                )
                
                Divider()
                    .background(OlasDesign.Colors.border)
                    .padding(.leading, 46)
                
                notificationToggle(
                    title: "Direct Messages",
                    subtitle: "Private messages",
                    icon: "envelope",
                    isOn: $directMessages
                )
            }
            .background(OlasDesign.Colors.surface)
            .cornerRadius(12)
        }
    }
    
    @ViewBuilder
    private var soundSettingsSection: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
            Text("Sound")
                .font(OlasDesign.Typography.title3)
                .foregroundColor(OlasDesign.Colors.text)
            
            Button(action: {
                showSoundSettings = true
                OlasDesign.Haptic.selection()
            }) {
                HStack {
                    Image(systemName: "speaker.wave.2")
                        .font(.body)
                        .foregroundColor(OlasDesign.Colors.primary)
                        .frame(width: 30)
                    
                    Text("Notification Sound")
                        .font(OlasDesign.Typography.body)
                        .foregroundColor(OlasDesign.Colors.text)
                    
                    Spacer()
                    
                    Text(selectedSound)
                        .font(OlasDesign.Typography.body)
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(OlasDesign.Colors.textTertiary)
                }
                .padding(OlasDesign.Spacing.md)
                .background(OlasDesign.Colors.surface)
                .cornerRadius(12)
            }
        }
    }
    
    @ViewBuilder
    private var quietHoursSection: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
            Text("Quiet Hours")
                .font(OlasDesign.Typography.title3)
                .foregroundColor(OlasDesign.Colors.text)
            
            VStack(spacing: OlasDesign.Spacing.md) {
                quietHourRow(
                    title: "Do Not Disturb",
                    subtitle: "Silence notifications",
                    icon: "moon.fill"
                )
                
                quietHourRow(
                    title: "Schedule",
                    subtitle: "10:00 PM - 7:00 AM",
                    icon: "clock"
                )
            }
            .padding(OlasDesign.Spacing.md)
            .background(OlasDesign.Colors.surface)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Components
    
    @ViewBuilder
    private func notificationToggle(title: String, subtitle: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(OlasDesign.Colors.primary)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: OlasDesign.Spacing.xs) {
                Text(title)
                    .font(OlasDesign.Typography.body)
                    .foregroundColor(OlasDesign.Colors.text)
                
                Text(subtitle)
                    .font(OlasDesign.Typography.caption)
                    .foregroundColor(OlasDesign.Colors.textSecondary)
            }
            
            Spacer()
            
            Toggle("", isOn: isOn)
                .tint(OlasDesign.Colors.primary)
        }
        .padding(OlasDesign.Spacing.md)
        .onChange(of: isOn.wrappedValue) { _, _ in
            OlasDesign.Haptic.selection()
        }
    }
    
    @ViewBuilder
    private func quietHourRow(title: String, subtitle: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(OlasDesign.Colors.primary)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: OlasDesign.Spacing.xs) {
                Text(title)
                    .font(OlasDesign.Typography.body)
                    .foregroundColor(OlasDesign.Colors.text)
                
                Text(subtitle)
                    .font(OlasDesign.Typography.caption)
                    .foregroundColor(OlasDesign.Colors.textSecondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(OlasDesign.Colors.textTertiary)
        }
    }
    
    // MARK: - Sound Selection Sheet
    
    @ViewBuilder
    private var soundSelectionSheet: some View {
        NavigationStack {
            ZStack {
                OlasDesign.Colors.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button("Cancel") {
                            showSoundSettings = false
                        }
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                        
                        Spacer()
                        
                        Text("Notification Sound")
                            .font(OlasDesign.Typography.title3)
                            .foregroundColor(OlasDesign.Colors.text)
                        
                        Spacer()
                        
                        Button("Done") {
                            showSoundSettings = false
                        }
                        .foregroundColor(OlasDesign.Colors.primary)
                    }
                    .padding(OlasDesign.Spacing.lg)
                    
                    // Sound options
                    VStack(spacing: OlasDesign.Spacing.sm) {
                        ForEach(notificationSounds, id: \.self) { sound in
                            Button(action: {
                                selectedSound = sound
                                playSound(sound)
                                OlasDesign.Haptic.selection()
                            }) {
                                HStack {
                                    Text(sound)
                                        .font(OlasDesign.Typography.body)
                                        .foregroundColor(OlasDesign.Colors.text)
                                    
                                    Spacer()
                                    
                                    if selectedSound == sound {
                                        Image(systemName: "checkmark")
                                            .font(.body)
                                            .foregroundColor(OlasDesign.Colors.primary)
                                    }
                                }
                                .padding(OlasDesign.Spacing.md)
                                .background(OlasDesign.Colors.surface)
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(OlasDesign.Spacing.lg)
                    
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Methods
    
    private func requestNotificationPermission() {
        #if os(iOS)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error)")
            }
        }
        #endif
    }
    
    private func playSound(_ sound: String) {
        // In a real app, you'd play the actual sound here
        print("Playing sound: \(sound)")
    }
}

// MARK: - Preview

struct NotificationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            NotificationSettingsView()
        }
    }
}