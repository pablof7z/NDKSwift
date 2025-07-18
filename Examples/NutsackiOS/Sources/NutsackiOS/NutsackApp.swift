import SwiftUI
import SwiftData
import NDKSwift

@main
struct NutsackApp: App {
    @StateObject private var appState = AppState()
    @State private var nostrManager: NostrManager
    @State private var walletManager: WalletManager
    @State private var showSplash = true
    
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
        let nm = NostrManager(from: "App")
        let wm = WalletManager(
            nostrManager: nm,
            modelContext: modelContainer.mainContext
        )
        
        _nostrManager = State(initialValue: nm)
        _walletManager = State(initialValue: wm)
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(appState)
                    .environment(nostrManager)
                    .environment(walletManager)
                    .opacity(showSplash ? 0 : 1)
                    .animation(.easeInOut(duration: 0.5), value: showSplash)
                
                if showSplash {
                    SplashView {
                        showSplash = false
                    }
                    .transition(.opacity.combined(with: .scale(scale: 1.1)))
                }
            }
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