import SwiftUI
import SwiftData
import NDKSwift

@main
struct NutsackApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var nostrManager = NostrManager()
    @StateObject private var walletManager: WalletManager
    
    // Create a simple in-memory container
    let modelContainer: ModelContainer = {
        let schema = Schema([
            Transaction.self
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    init() {
        let nostrManager = NostrManager()
        let walletManager = WalletManager(
            nostrManager: nostrManager,
            modelContext: modelContainer.mainContext
        )
        
        _nostrManager = StateObject(wrappedValue: nostrManager)
        _walletManager = StateObject(wrappedValue: walletManager)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(nostrManager)
                .environmentObject(walletManager)
                .preferredColorScheme(.dark)
        }
        .modelContainer(modelContainer)
    }
}

// MARK: - Database Manager
class DatabaseManager {
    static let shared = DatabaseManager()
    
    private(set) var container: ModelContainer?
    
    private init() {
        do {
            let schema = Schema([
                Transaction.self
            ])
            
            let modelConfiguration = ModelConfiguration(
                schema: schema, 
                isStoredInMemoryOnly: true,
                allowsSave: true
            )
            
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            print("Created in-memory ModelContainer")
        } catch {
            print("Could not create ModelContainer: \(error)")
            container = nil
        }
    }
    
    func newContext() -> ModelContext {
        guard let container = container else {
            fatalError("ModelContainer not available")
        }
        return ModelContext(container)
    }
}