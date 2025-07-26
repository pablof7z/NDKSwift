import SwiftUI

// MARK: - Stat Card
struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: OlasDesign.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
            
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(OlasDesign.Colors.text)
            
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(OlasDesign.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OlasDesign.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.sm)
                .fill(OlasDesign.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.sm)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Action Button
struct ActionButton: View {
    let icon: String
    let title: String
    let gradient: [Color]
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            OlasDesign.Haptic.selection()
            action()
        }) {
            VStack(spacing: OlasDesign.Spacing.xs) {
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .blur(radius: isPressed ? 15 : 10)
                        .opacity(0.5)
                    
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundStyle(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .scaleEffect(isPressed ? 0.95 : 1)
                
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(OlasDesign.Colors.text)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, OlasDesign.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                    .fill(OlasDesign.Colors.surface)
                    .shadow(
                        color: gradient.first?.opacity(0.2) ?? Color.clear,
                        radius: isPressed ? 2 : 5,
                        x: 0,
                        y: isPressed ? 1 : 3
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.98 : 1)
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Empty Activity View
struct EmptyActivityView: View {
    @State private var animateGradient = false
    
    var body: some View {
        VStack(spacing: OlasDesign.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.orange.opacity(0.1),
                                Color.yellow.opacity(0.1)
                            ],
                            startPoint: animateGradient ? .topLeading : .bottomTrailing,
                            endPoint: animateGradient ? .bottomTrailing : .topLeading
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "bolt.slash.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.gray)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                    animateGradient.toggle()
                }
            }
            
            VStack(spacing: OlasDesign.Spacing.xs) {
                Text("No activity yet")
                    .font(OlasDesign.Typography.bodyMedium)
                    .foregroundColor(OlasDesign.Colors.text)
                
                Text("Your transactions will appear here")
                    .font(OlasDesign.Typography.caption)
                    .foregroundColor(OlasDesign.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OlasDesign.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                .fill(OlasDesign.Colors.surface.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.gray.opacity(0.1),
                                    Color.gray.opacity(0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
}

// MARK: - Transaction History View
struct TransactionHistoryView: View {
    @ObservedObject var walletManager: OlasWalletManager
    @State private var searchText = ""
    @State private var selectedFilter: TransactionFilter = .all
    
    enum TransactionFilter: String, CaseIterable {
        case all = "All"
        case sent = "Sent"
        case received = "Received"
        
        var icon: String {
            switch self {
            case .all: return "arrow.up.arrow.down"
            case .sent: return "arrow.up.circle"
            case .received: return "arrow.down.circle"
            }
        }
    }
    
    var filteredTransactions: [OlasWalletManager.WalletTransaction] {
        walletManager.recentTransactions.filter { transaction in
            let matchesFilter = selectedFilter == .all || 
                (selectedFilter == .sent && transaction.type == .sent) ||
                (selectedFilter == .received && transaction.type == .received)
            
            let matchesSearch = searchText.isEmpty || 
                transaction.description.localizedCaseInsensitiveContains(searchText)
            
            return matchesFilter && matchesSearch
        }
    }
    
    var body: some View {
        ZStack {
            OlasDesign.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Search and filters
                VStack(spacing: OlasDesign.Spacing.md) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(OlasDesign.Colors.textTertiary)
                        
                        TextField("Search transactions", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                    }
                    .padding(OlasDesign.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.sm)
                            .fill(OlasDesign.Colors.surface)
                    )
                    
                    // Filter pills
                    HStack(spacing: OlasDesign.Spacing.sm) {
                        ForEach(TransactionFilter.allCases, id: \.self) { filter in
                            FilterPill(
                                title: filter.rawValue,
                                icon: filter.icon,
                                isSelected: selectedFilter == filter
                            ) {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedFilter = filter
                                }
                            }
                        }
                        
                        Spacer()
                    }
                }
                .padding(OlasDesign.Spacing.md)
                
                // Transaction list
                if filteredTransactions.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No transactions found",
                        subtitle: selectedFilter == .all ? 
                            "Try adjusting your search" : 
                            "No \(selectedFilter.rawValue.lowercased()) transactions"
                    )
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredTransactions) { transaction in
                                VStack(spacing: 0) {
                                    TransactionRow(transaction: transaction, walletManager: walletManager)
                                        .padding(.horizontal, OlasDesign.Spacing.md)
                                    
                                    if transaction.id != filteredTransactions.last?.id {
                                        Divider()
                                            .padding(.leading, 60)
                                    }
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                                .fill(OlasDesign.Colors.surface)
                        )
                        .padding(.horizontal, OlasDesign.Spacing.md)
                    }
                }
            }
        }
        .navigationTitle("Transaction History")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Filter Pill
struct FilterPill: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : OlasDesign.Colors.text)
            .padding(.horizontal, OlasDesign.Spacing.md)
            .padding(.vertical, OlasDesign.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.sm)
                    .fill(isSelected ? OlasDesign.Colors.primary : OlasDesign.Colors.surface)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: OlasDesign.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(OlasDesign.Colors.textTertiary)
            
            VStack(spacing: OlasDesign.Spacing.xs) {
                Text(title)
                    .font(OlasDesign.Typography.bodyMedium)
                    .foregroundColor(OlasDesign.Colors.text)
                
                Text(subtitle)
                    .font(OlasDesign.Typography.caption)
                    .foregroundColor(OlasDesign.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(OlasDesign.Spacing.xl)
    }
}