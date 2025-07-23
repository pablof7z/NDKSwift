import SwiftUI
import SwiftData
import NDKSwift

// This view is now integrated into SplashView
// Keeping this file for backward compatibility with the project structure
struct CreateAccountView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Text("This view has been integrated into SplashView")
            .padding()
            .onAppear {
                dismiss()
            }
    }
}