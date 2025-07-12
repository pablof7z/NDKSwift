import SwiftUI
import SwiftData
import NDKSwift
import OSLog

let logger = Logger(subsystem: "Nutsack Wallet", category: "App")

@main
struct NutsackApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var nostrManager = NostrManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(nostrManager)
                .preferredColorScheme(.dark)
        }
        .modelContainer(DatabaseManager.shared.container)
    }
}

// MARK: - Database Manager
class DatabaseManager {
    static let shared = DatabaseManager()
    
    private(set) var container: ModelContainer
    
    private init() {
        let schema = Schema([
            NostrAccount.self,
            CashuWallet.self,
            CashuToken.self,
            Transaction.self,
            Mint.self
        ])
        
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
    
    func newContext() -> ModelContext {
        return ModelContext(container)
    }
}