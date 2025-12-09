import SwiftUI

public enum AppTheme: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.system.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .system
    }

    var body: some View {
        List {
            Section("Theme") {
                ForEach(AppTheme.allCases, id: \.self) { themeOption in
                    Button {
                        selectedTheme = themeOption.rawValue
                    } label: {
                        HStack {
                            Label(themeOption.rawValue, systemImage: icon(for: themeOption))
                            Spacer()
                            if theme == themeOption {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(OlasTheme.Colors.deepTeal)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }

            Section {
                HStack(spacing: 16) {
                    ThemePreviewCard(isDark: false, isSelected: theme == .light)
                    ThemePreviewCard(isDark: true, isSelected: theme == .dark)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            } header: {
                Text("Preview")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func icon(for theme: AppTheme) -> String {
        switch theme {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

struct ThemePreviewCard: View {
    let isDark: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(isDark ? Color.black : Color.white)
                .frame(height: 80)
                .overlay(
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isDark ? Color.gray.opacity(0.3) : Color.gray.opacity(0.2))
                            .frame(width: 40, height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isDark ? Color.gray.opacity(0.3) : Color.gray.opacity(0.2))
                            .frame(width: 60, height: 8)
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? OlasTheme.Colors.deepTeal : .gray.opacity(0.3), lineWidth: 2)
                )
                .shadow(radius: 2)

            Text(isDark ? "Dark" : "Light")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
