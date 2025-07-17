import Foundation
import NDKSwift

struct Account: Identifiable, Codable {
    let id = UUID()
    let privateKey: String
    let pubkey: String
    var name: String?
    var picture: String?
    var isActive: Bool
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case privateKey, pubkey, name, picture, isActive, createdAt
    }
}

@MainActor
class AccountManager: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var activeAccount: Account?
    
    init() {
        loadAccounts()
    }
    
    func addAccount(privateKey: String, name: String? = nil, picture: String? = nil) async throws -> Account {
        let signer = try NDKPrivateKeySigner(privateKey: privateKey)
        let user = try await signer.user()
        
        let account = Account(
            privateKey: privateKey,
            pubkey: user.pubkey,
            name: name,
            picture: picture,
            isActive: false,
            createdAt: Date()
        )
        
        accounts.append(account)
        
        // If this is the first account, make it active
        if accounts.count == 1 {
            setActiveAccount(account)
        } else {
            saveAccounts()
        }
        
        return account
    }
    
    func setActiveAccount(_ account: Account) {
        // Deactivate all accounts
        for i in accounts.indices {
            accounts[i].isActive = false
        }
        
        // Activate the selected account
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index].isActive = true
            activeAccount = accounts[index]
        }
        
        saveAccounts()
    }
    
    func removeAccount(_ account: Account) {
        accounts.removeAll { $0.id == account.id }
        
        // If we removed the active account, activate another one
        if activeAccount?.id == account.id {
            activeAccount = nil
            if let firstAccount = accounts.first {
                setActiveAccount(firstAccount)
            }
        }
        
        saveAccounts()
    }
    
    func updateAccountProfile(_ account: Account, name: String?, picture: String?) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        
        accounts[index].name = name
        accounts[index].picture = picture
        
        if activeAccount?.id == account.id {
            activeAccount = accounts[index]
        }
        
        saveAccounts()
    }
    
    private func loadAccounts() {
        if let data = UserDefaults.standard.data(forKey: "nostr_accounts"),
           let decoded = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = decoded
            activeAccount = accounts.first { $0.isActive }
        }
        
        // Migrate from old auth system if needed
        if accounts.isEmpty, let privateKey = UserDefaults.standard.string(forKey: "private_key") {
            Task {
                try? await addAccount(privateKey: privateKey)
                UserDefaults.standard.removeObject(forKey: "private_key")
            }
        }
    }
    
    private func saveAccounts() {
        if let encoded = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(encoded, forKey: "nostr_accounts")
        }
    }
}