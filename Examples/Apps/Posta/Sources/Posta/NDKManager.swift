import Foundation
import NDKSwift

@MainActor
class NDKManager: ObservableObject {
    @Published var ndk: NDK?
    
    static let shared = NDKManager()
    
    private init() {}
    
    func setNDK(_ ndk: NDK) {
        self.ndk = ndk
    }
}