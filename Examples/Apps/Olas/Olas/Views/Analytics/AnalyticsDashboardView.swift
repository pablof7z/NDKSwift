import SwiftUI
import Charts
import NDKSwift

struct AnalyticsDashboardView: View {
    @Environment(NostrManager.self) private var nostrManager
    @StateObject private var analyticsManager = AnalyticsManager()
    @State private var selectedTimeRange = TimeRange.week
    @State private var showingDetailedStats = false
    
    enum TimeRange: String, CaseIterable {
        case day = "24h"
        case week = "7d"
        case month = "30d"
        case all = "All"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: OlasDesign.Spacing.lg) {
                    // Time range selector
                    timeRangeSelector
                        .padding(.horizontal)
                    
                    // Overview cards
                    overviewSection
                    
                    // Engagement chart
                    engagementChart
                    
                    // Top posts
                    topPostsSection
                    
                    // Follower growth
                    followerGrowthChart
                    
                    // Audience insights
                    audienceInsights
                    
                    // Content performance
                    contentPerformance
                }
                .padding(.vertical)
            }
            .background(
                LinearGradient(
                    colors: [
                        OlasDesign.Colors.background,
                        OlasDesign.Colors.background.opacity(0.95)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await analyticsManager.refreshData()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(OlasDesign.Colors.primary)
                    }
                }
            }
            .task {
                if let ndk = nostrManager.ndk {
                    await analyticsManager.loadAnalytics(ndk: ndk, timeRange: selectedTimeRange)
                }
            }
            .onChange(of: selectedTimeRange) { _, newValue in
                Task {
                    if let ndk = nostrManager.ndk {
                        await analyticsManager.loadAnalytics(ndk: ndk, timeRange: newValue)
                    }
                }
            }
        }
    }
    
    private var timeRangeSelector: some View {
        HStack(spacing: 0) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Button(action: {
                    withAnimation(.spring()) {
                        selectedTimeRange = range
                    }
                    OlasDesign.Haptic.selection()
                }) {
                    Text(range.rawValue)
                        .font(OlasDesign.Typography.bodyMedium)
                        .foregroundColor(selectedTimeRange == range ? .white : OlasDesign.Colors.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OlasDesign.Spacing.sm)
                        .background(
                            selectedTimeRange == range ?
                            LinearGradient(
                                colors: OlasDesign.Colors.primaryGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            ) : nil
                        )
                }
            }
        }
        .background(OlasDesign.Colors.surface)
        .cornerRadius(OlasDesign.CornerRadius.md)
    }
    
    private var overviewSection: some View {
        VStack(spacing: OlasDesign.Spacing.md) {
            HStack(spacing: OlasDesign.Spacing.md) {
                AnalyticsCard(
                    title: "Total Views",
                    value: formatNumber(analyticsManager.totalViews),
                    change: analyticsManager.viewsChange,
                    icon: "eye.fill",
                    gradient: [Color(hex: "FF6B6B"), Color(hex: "4ECDC4")]
                )
                
                AnalyticsCard(
                    title: "Engagement",
                    value: formatNumber(analyticsManager.totalEngagement),
                    change: analyticsManager.engagementChange,
                    icon: "heart.fill",
                    gradient: [Color(hex: "667EEA"), Color(hex: "764BA2")]
                )
            }
            
            HStack(spacing: OlasDesign.Spacing.md) {
                AnalyticsCard(
                    title: "Followers",
                    value: formatNumber(analyticsManager.followerCount),
                    change: analyticsManager.followerChange,
                    icon: "person.2.fill",
                    gradient: [Color(hex: "F093FB"), Color(hex: "F5576C")]
                )
                
                AnalyticsCard(
                    title: "Reach",
                    value: formatNumber(analyticsManager.totalReach),
                    change: analyticsManager.reachChange,
                    icon: "network",
                    gradient: [Color(hex: "4FACFE"), Color(hex: "00F2FE")]
                )
            }
        }
        .padding(.horizontal)
    }
    
    private var engagementChart: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
            Text("Engagement Overview")
                .font(OlasDesign.Typography.title3)
                .foregroundColor(OlasDesign.Colors.text)
                .padding(.horizontal)
            
            Chart(analyticsManager.engagementData) { data in
                AreaMark(
                    x: .value("Date", data.date),
                    y: .value("Engagement", data.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            OlasDesign.Colors.primary.opacity(0.6),
                            OlasDesign.Colors.primary.opacity(0.1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
                
                LineMark(
                    x: .value("Date", data.date),
                    y: .value("Engagement", data.value)
                )
                .foregroundStyle(OlasDesign.Colors.primary)
                .lineStyle(StrokeStyle(lineWidth: 3))
                .interpolationMethod(.catmullRom)
            }
            .frame(height: 200)
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(OlasDesign.Colors.surface.opacity(0.5))
        .cornerRadius(OlasDesign.CornerRadius.lg)
        .padding(.horizontal)
    }
    
    private var topPostsSection: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
            HStack {
                Text("Top Posts")
                    .font(OlasDesign.Typography.title3)
                    .foregroundColor(OlasDesign.Colors.text)
                
                Spacer()
                
                Button("See All") {
                    showingDetailedStats = true
                }
                .font(OlasDesign.Typography.caption)
                .foregroundColor(OlasDesign.Colors.primary)
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OlasDesign.Spacing.md) {
                    ForEach(analyticsManager.topPosts) { post in
                        TopPostCard(post: post)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var followerGrowthChart: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
            Text("Follower Growth")
                .font(OlasDesign.Typography.title3)
                .foregroundColor(OlasDesign.Colors.text)
                .padding(.horizontal)
            
            Chart(analyticsManager.followerGrowthData) { data in
                BarMark(
                    x: .value("Day", data.date, unit: .day),
                    y: .value("New Followers", data.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: OlasDesign.Colors.primaryGradient,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(4)
            }
            .frame(height: 150)
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(OlasDesign.Colors.surface.opacity(0.5))
        .cornerRadius(OlasDesign.CornerRadius.lg)
        .padding(.horizontal)
    }
    
    private var audienceInsights: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
            Text("Audience Insights")
                .font(OlasDesign.Typography.title3)
                .foregroundColor(OlasDesign.Colors.text)
                .padding(.horizontal)
            
            // Active times heatmap
            VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
                Text("Most Active Times")
                    .font(OlasDesign.Typography.caption)
                    .foregroundColor(OlasDesign.Colors.textSecondary)
                
                ActiveTimesHeatmap(data: analyticsManager.activeTimesData)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                    .fill(OlasDesign.Colors.surface.opacity(0.7))
            )
            
            // Demographics
            HStack(spacing: OlasDesign.Spacing.md) {
                DemographicChart(
                    title: "Top Locations",
                    data: analyticsManager.topLocations
                )
                
                DemographicChart(
                    title: "Top Interests",
                    data: analyticsManager.topInterests
                )
            }
        }
        .padding(.horizontal)
    }
    
    private var contentPerformance: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
            Text("Content Performance")
                .font(OlasDesign.Typography.title3)
                .foregroundColor(OlasDesign.Colors.text)
                .padding(.horizontal)
            
            // Content type breakdown
            Chart(analyticsManager.contentTypeData) { data in
                SectorMark(
                    angle: .value("Count", data.value),
                    innerRadius: .ratio(0.618),
                    angularInset: 2
                )
                .foregroundStyle(by: .value("Type", data.type))
                .cornerRadius(4)
            }
            .frame(height: 200)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                    .fill(OlasDesign.Colors.surface.opacity(0.7))
            )
            .padding(.horizontal)
        }
    }
    
    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        } else {
            return "\(number)"
        }
    }
}

// MARK: - Analytics Manager

@MainActor
class AnalyticsManager: ObservableObject {
    @Published var totalViews = 0
    @Published var viewsChange: Double = 0
    @Published var totalEngagement = 0
    @Published var engagementChange: Double = 0
    @Published var followerCount = 0
    @Published var followerChange: Double = 0
    @Published var totalReach = 0
    @Published var reachChange: Double = 0
    
    @Published var engagementData: [ChartData] = []
    @Published var followerGrowthData: [ChartData] = []
    @Published var topPosts: [TopPost] = []
    @Published var activeTimesData: [[Double]] = []
    @Published var topLocations: [DemographicData] = []
    @Published var topInterests: [DemographicData] = []
    @Published var contentTypeData: [ContentTypeData] = []
    
    func loadAnalytics(ndk: NDK, timeRange: AnalyticsDashboardView.TimeRange) async {
        // Simulate loading analytics data
        // In a real app, this would query Nostr events and calculate metrics
        
        // Generate mock data
        totalViews = Int.random(in: 10000...50000)
        viewsChange = Double.random(in: -20...50)
        totalEngagement = Int.random(in: 1000...10000)
        engagementChange = Double.random(in: -10...30)
        followerCount = Int.random(in: 500...5000)
        followerChange = Double.random(in: -5...20)
        totalReach = Int.random(in: 20000...100000)
        reachChange = Double.random(in: -15...40)
        
        // Generate chart data
        engagementData = generateChartData(days: 7)
        followerGrowthData = generateChartData(days: 7)
        topPosts = generateTopPosts()
        activeTimesData = generateHeatmapData()
        topLocations = generateDemographicData(type: .location)
        topInterests = generateDemographicData(type: .interest)
        contentTypeData = generateContentTypeData()
    }
    
    func refreshData() async {
        // Refresh analytics data
    }
    
    private func generateChartData(days: Int) -> [ChartData] {
        (0..<days).map { day in
            ChartData(
                date: Date().addingTimeInterval(-Double(day) * 86400),
                value: Int.random(in: 100...1000)
            )
        }.reversed()
    }
    
    private func generateTopPosts() -> [TopPost] {
        (1...5).map { index in
            TopPost(
                id: "\(index)",
                imageURL: "https://picsum.photos/200/300?random=\(index)",
                engagement: Int.random(in: 100...1000),
                views: Int.random(in: 1000...10000),
                timestamp: Date().addingTimeInterval(-Double.random(in: 0...604800))
            )
        }
    }
    
    private func generateHeatmapData() -> [[Double]] {
        (0..<7).map { _ in
            (0..<24).map { _ in Double.random(in: 0...1) }
        }
    }
    
    private func generateDemographicData(type: DemographicType) -> [DemographicData] {
        let items = type == .location ?
            ["USA", "Japan", "Brazil", "Germany", "UK"] :
            ["Bitcoin", "Photography", "Art", "Tech", "Music"]
        
        return items.enumerated().map { index, name in
            DemographicData(
                name: name,
                value: Double(100 - index * 15),
                percentage: Double(30 - index * 5)
            )
        }
    }
    
    private func generateContentTypeData() -> [ContentTypeData] {
        [
            ContentTypeData(type: "Photos", value: 60),
            ContentTypeData(type: "Videos", value: 25),
            ContentTypeData(type: "Stories", value: 10),
            ContentTypeData(type: "Text", value: 5)
        ]
    }
}

// MARK: - Supporting Views

struct AnalyticsCard: View {
    let title: String
    let value: String
    let change: Double
    let icon: String
    let gradient: [Color]
    
    var body: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Spacer()
                
                if change != 0 {
                    HStack(spacing: 2) {
                        Image(systemName: change > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption)
                        Text("\(abs(Int(change)))%")
                            .font(.caption)
                    }
                    .foregroundColor(change > 0 ? .green : .red)
                }
            }
            
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(OlasDesign.Colors.text)
            
            Text(title)
                .font(OlasDesign.Typography.caption)
                .foregroundColor(OlasDesign.Colors.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                .fill(OlasDesign.Colors.surface.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                        .stroke(
                            LinearGradient(
                                colors: gradient.map { $0.opacity(0.3) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
}

struct TopPostCard: View {
    let post: TopPost
    
    var body: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
            AsyncImage(url: URL(string: post.imageURL)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 120, height: 150)
            .clipped()
            .cornerRadius(OlasDesign.CornerRadius.md)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                    Text("\(post.engagement)")
                        .font(.caption)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "eye.fill")
                        .font(.caption2)
                    Text("\(post.views)")
                        .font(.caption)
                }
            }
            .foregroundColor(OlasDesign.Colors.textSecondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                .fill(OlasDesign.Colors.surface.opacity(0.7))
        )
    }
}

struct ActiveTimesHeatmap: View {
    let data: [[Double]]
    let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    
    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<7) { day in
                HStack(spacing: 2) {
                    Text(days[day])
                        .font(.caption2)
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                        .frame(width: 30)
                    
                    ForEach(0..<24) { hour in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                Color.green.opacity(
                                    data.indices.contains(day) && data[day].indices.contains(hour) ?
                                    data[day][hour] : 0
                                )
                            )
                            .frame(width: 10, height: 10)
                    }
                }
            }
        }
    }
}

struct DemographicChart: View {
    let title: String
    let data: [DemographicData]
    
    var body: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
            Text(title)
                .font(OlasDesign.Typography.caption)
                .foregroundColor(OlasDesign.Colors.textSecondary)
            
            VStack(spacing: OlasDesign.Spacing.xs) {
                ForEach(data) { item in
                    HStack {
                        Text(item.name)
                            .font(.caption)
                            .foregroundColor(OlasDesign.Colors.text)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text("\(Int(item.percentage))%")
                            .font(.caption)
                            .foregroundColor(OlasDesign.Colors.textSecondary)
                    }
                    
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(OlasDesign.Colors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(
                                        LinearGradient(
                                            colors: OlasDesign.Colors.primaryGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geometry.size.width * item.value / 100),
                                alignment: .leading
                            )
                    }
                    .frame(height: 4)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                .fill(OlasDesign.Colors.surface.opacity(0.7))
        )
    }
}

// MARK: - Data Models

struct ChartData: Identifiable {
    let id = UUID()
    let date: Date
    let value: Int
}

struct TopPost: Identifiable {
    let id: String
    let imageURL: String
    let engagement: Int
    let views: Int
    let timestamp: Date
}

struct DemographicData: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let percentage: Double
}

struct ContentTypeData: Identifiable {
    let id = UUID()
    let type: String
    let value: Int
}

enum DemographicType {
    case location
    case interest
}