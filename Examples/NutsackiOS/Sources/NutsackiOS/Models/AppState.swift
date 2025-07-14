import Foundation
import SwiftUI

@MainActor
class AppState: ObservableObject {
    private static let conversionUnitKey = "PreferredCurrencyConversionUnit"
    private static let lastRNackHashKey = "LastReleaseNotesAcknoledgedHash"
    private static let firstLaunchFlag = "HasLaunchedBefore"
    
    struct ExchangeRateResponse: Decodable {
        let bitcoin: ExchangeRate
    }
    
    struct ExchangeRate: Decodable, Equatable {
        let usd: Int
        let eur: Int
    }
    
    @Published var preferredConversionUnit: CurrencyUnit {
        didSet {
            UserDefaults.standard.setValue(preferredConversionUnit.rawValue, forKey: AppState.conversionUnitKey)
        }
    }
    
    @Published var exchangeRates: ExchangeRate?
    
    static var showOnboarding: Bool {
        get {
            return !UserDefaults.standard.bool(forKey: firstLaunchFlag)
        } set {
            UserDefaults.standard.set(!newValue, forKey: firstLaunchFlag)
        }
    }
    
    init() {
        if let unit = CurrencyUnit(rawValue: UserDefaults.standard.string(forKey: AppState.conversionUnitKey) ?? "") {
            preferredConversionUnit = unit
        } else {
            preferredConversionUnit = .usd
        }
        
        loadExchangeRates()
    }
    
    func loadExchangeRates() {
        print("Loading exchange rates...")
        
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd,eur") else {
            print("Could not fetch exchange rates from API due to an invalid URL.")
            return
        }
        
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else {
                print("Unable to load conversion data.")
                return
            }
            
            guard let prices = try? JSONDecoder().decode(ExchangeRateResponse.self, from: data).bitcoin else {
                print("Unable to decode exchange rate data from request response.")
                return
            }
            
            await MainActor.run {
                self.exchangeRates = prices
            }
        }
    }
}

enum CurrencyUnit: String, CaseIterable {
    case sat
    case usd
    case eur
    case btc
    
    var symbol: String {
        switch self {
        case .sat: return "sats"
        case .usd: return "$"
        case .eur: return "€"
        case .btc: return "₿"
        }
    }
}