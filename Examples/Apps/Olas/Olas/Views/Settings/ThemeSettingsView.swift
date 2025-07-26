import SwiftUI

struct ThemeSettingsView: View {
    @State private var selectedTheme = "Auto"
    @State private var accentColor = "Purple"
    @State private var appIcon = "Default"
    
    private let themes = ["Auto", "Light", "Dark"]
    private let accentColors = [
        ("Purple", Color.purple),
        ("Blue", Color.blue),
        ("Pink", Color.pink),
        ("Orange", Color.orange),
        ("Green", Color.green),
        ("Red", Color.red)
    ]
    private let appIcons = ["Default", "Dark", "Gradient", "Minimal"]
    
    var body: some View {
        ZStack {
            OlasDesign.Colors.background
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: OlasDesign.Spacing.xl) {
                    // Theme selection
                    themeSection
                    
                    // Accent color
                    accentColorSection
                    
                    // App icon
                    appIconSection
                    
                    // Preview
                    previewSection
                }
                .padding(OlasDesign.Spacing.lg)
            }
        }
        .navigationTitle("Theme")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
    
    // MARK: - Sections
    
    @ViewBuilder
    private var themeSection: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
            Text("Appearance")
                .font(OlasDesign.Typography.title3)
                .foregroundColor(OlasDesign.Colors.text)
            
            HStack(spacing: OlasDesign.Spacing.md) {
                ForEach(themes, id: \.self) { theme in
                    themeOption(theme)
                }
            }
        }
    }
    
    @ViewBuilder
    private func themeOption(_ theme: String) -> some View {
        Button(action: {
            selectedTheme = theme
            OlasDesign.Haptic.selection()
        }) {
            VStack(spacing: OlasDesign.Spacing.sm) {
                // Preview
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(theme == "Dark" ? Color.black : theme == "Light" ? Color.white : Color.gray)
                        .frame(height: 100)
                    
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(theme == "Dark" ? Color.gray : Color.black.opacity(0.8))
                            .frame(width: 40, height: 4)
                        
                        HStack(spacing: 4) {
                            ForEach(0..<3) { _ in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(theme == "Dark" ? Color.gray.opacity(0.5) : Color.gray.opacity(0.3))
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(selectedTheme == theme ? OlasDesign.Colors.primary : OlasDesign.Colors.border, lineWidth: 2)
                )
                
                Text(theme)
                    .font(OlasDesign.Typography.caption)
                    .foregroundColor(selectedTheme == theme ? OlasDesign.Colors.primary : OlasDesign.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    private var accentColorSection: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
            Text("Accent Color")
                .font(OlasDesign.Typography.title3)
                .foregroundColor(OlasDesign.Colors.text)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: OlasDesign.Spacing.md), count: 3), spacing: OlasDesign.Spacing.md) {
                ForEach(accentColors, id: \.0) { name, color in
                    Button(action: {
                        accentColor = name
                        OlasDesign.Haptic.selection()
                    }) {
                        VStack(spacing: OlasDesign.Spacing.sm) {
                            Circle()
                                .fill(color)
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Circle()
                                        .stroke(accentColor == name ? Color.white : Color.clear, lineWidth: 3)
                                        .padding(3)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(accentColor == name ? color : OlasDesign.Colors.border, lineWidth: 2)
                                )
                            
                            Text(name)
                                .font(OlasDesign.Typography.caption)
                                .foregroundColor(accentColor == name ? color : OlasDesign.Colors.textSecondary)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var appIconSection: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
            Text("App Icon")
                .font(OlasDesign.Typography.title3)
                .foregroundColor(OlasDesign.Colors.text)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: OlasDesign.Spacing.md), count: 4), spacing: OlasDesign.Spacing.md) {
                ForEach(appIcons, id: \.self) { icon in
                    Button(action: {
                        appIcon = icon
                        changeAppIcon(to: icon)
                        OlasDesign.Haptic.selection()
                    }) {
                        VStack(spacing: OlasDesign.Spacing.sm) {
                            // Icon preview
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    icon == "Default" ? LinearGradient(
                                        colors: [.purple, .pink],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ) : icon == "Dark" ? LinearGradient(
                                        colors: [.black, .gray],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ) : icon == "Gradient" ? LinearGradient(
                                        colors: [.blue, .green],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ) : LinearGradient(
                                        colors: [.white, .gray],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Text("O")
                                        .font(.system(size: 30, weight: .bold, design: .rounded))
                                        .foregroundColor(icon == "Minimal" ? .black : .white)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(appIcon == icon ? OlasDesign.Colors.primary : OlasDesign.Colors.border, lineWidth: 2)
                                )
                            
                            Text(icon)
                                .font(.system(size: 10))
                                .foregroundColor(appIcon == icon ? OlasDesign.Colors.primary : OlasDesign.Colors.textSecondary)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
            Text("Preview")
                .font(OlasDesign.Typography.title3)
                .foregroundColor(OlasDesign.Colors.text)
            
            // Mock feed item
            VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
                // Header
                HStack(spacing: OlasDesign.Spacing.sm) {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 40, height: 40)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Preview User")
                            .font(OlasDesign.Typography.bodyBold)
                            .foregroundColor(OlasDesign.Colors.text)
                        
                        Text("2 minutes ago")
                            .font(OlasDesign.Typography.caption)
                            .foregroundColor(OlasDesign.Colors.textSecondary)
                    }
                    
                    Spacer()
                }
                
                // Image
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: getAccentGradient(),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.white.opacity(0.5))
                    )
                
                // Actions
                HStack(spacing: OlasDesign.Spacing.lg) {
                    Button(action: {}) {
                        Image(systemName: "heart")
                            .font(.title3)
                            .foregroundColor(getAccentColor())
                    }
                    
                    Button(action: {}) {
                        Image(systemName: "bubble.left")
                            .font(.title3)
                            .foregroundColor(OlasDesign.Colors.textSecondary)
                    }
                    
                    Button(action: {}) {
                        Image(systemName: "bolt")
                            .font(.title3)
                            .foregroundColor(OlasDesign.Colors.textSecondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {}) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                            .foregroundColor(OlasDesign.Colors.textSecondary)
                    }
                }
            }
            .padding(OlasDesign.Spacing.md)
            .background(OlasDesign.Colors.surface)
            .cornerRadius(16)
        }
    }
    
    // MARK: - Methods
    
    private func getAccentColor() -> Color {
        switch accentColor {
        case "Purple": return .purple
        case "Blue": return .blue
        case "Pink": return .pink
        case "Orange": return .orange
        case "Green": return .green
        case "Red": return .red
        default: return .purple
        }
    }
    
    private func getAccentGradient() -> [Color] {
        let base = getAccentColor()
        switch accentColor {
        case "Purple": return [.purple, .pink]
        case "Blue": return [.blue, .cyan]
        case "Pink": return [.pink, .red]
        case "Orange": return [.orange, .yellow]
        case "Green": return [.green, .mint]
        case "Red": return [.red, .orange]
        default: return [.purple, .pink]
        }
    }
    
    private func changeAppIcon(to iconName: String) {
        #if os(iOS)
        guard UIApplication.shared.supportsAlternateIcons else { return }
        
        let alternateIconName: String? = iconName == "Default" ? nil : iconName
        
        UIApplication.shared.setAlternateIconName(alternateIconName) { error in
            if let error = error {
                print("Error changing app icon: \(error.localizedDescription)")
            }
        }
        #endif
    }
}

// MARK: - Preview

struct ThemeSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ThemeSettingsView()
        }
    }
}