import SwiftUI

struct EmptyHighlightsView: View {
    @State private var animationPhase = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Animated icon
            ZStack {
                // Outer ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                DesignSystem.Colors.primary.opacity(0.3),
                                DesignSystem.Colors.secondary.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 140, height: 140)
                    .scaleEffect(animationPhase ? 1.1 : 1.0)
                    .opacity(animationPhase ? 0.5 : 1.0)
                
                // Inner content
                VStack(spacing: 0) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    DesignSystem.Colors.primary,
                                    DesignSystem.Colors.secondary
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .offset(y: animationPhase ? -5 : 0)
                    
                    Image(systemName: "quote.closing")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    DesignSystem.Colors.secondary,
                                    DesignSystem.Colors.primary
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .offset(y: animationPhase ? 5 : 0)
                }
            }
            
            VStack(spacing: 16) {
                Text("No Highlights Yet")
                    .font(DesignSystem.Typography.title)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.text)
                
                Text("Be the first to share a highlight from your reading")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            
            // CTA Button
            Button(action: {}) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Create Highlight")
                }
                .font(DesignSystem.Typography.callout)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [
                            DesignSystem.Colors.primary,
                            DesignSystem.Colors.secondary
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(25)
                .shadow(
                    color: DesignSystem.Colors.primary.opacity(0.3),
                    radius: 8,
                    x: 0,
                    y: 4
                )
            }
            .scaleEffect(animationPhase ? 1.05 : 1.0)
            
            Spacer()
            
            // Bottom hint
            VStack(spacing: 8) {
                Image(systemName: "arrow.up")
                    .font(.title3)
                    .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.5))
                    .offset(y: animationPhase ? -5 : 0)
                
                Text("Pull to refresh")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.5))
            }
            .padding(.bottom, 40)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                animationPhase = true
            }
        }
    }
}