import SwiftUI

/// A beautiful, premium Welcome View (splash screen) for the Lemon app.
/// Features a layered, glowing logo badge with scale-bounce and floating animations,
/// premium Raleway-Thin brand typography, and smooth, idiomatic loading dots.
struct WelcomeView: View {
    @State private var logoScale: CGFloat = 0.3
    @State private var logoOffset: CGFloat = 4
    @State private var contentOpacity: Double = 0.0
    
    var onSkip: () -> Void
    
    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
                .paperBackground()
                .contentShape(Rectangle())
            
            VStack(spacing: 36) {
                Spacer()
                
                // Animated Logo Badge
                ZStack {
                    // Soft outer glow/plate
                    Circle()
                        .fill(Theme.highlight.opacity(0.24))
                        .frame(width: 148, height: 148)
                        .blur(radius: 6)
                    
                    // Card stroke border circle
                    Circle()
                        .fill(Theme.paper)
                        .frame(width: 140, height: 140)
                        .cardStroke(cornerRadius: 70, inkOpacity: 0.16)
                    
                    // Outer dotted deckle edge
                    Circle()
                        .stroke(Theme.inkFaded.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        .frame(width: 130, height: 130)
                    
                    // App logo image
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 90, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .scaleEffect(logoScale)
                        .offset(y: logoOffset)
                        .shadow(color: Theme.ink.opacity(0.12), radius: 8, x: 0, y: 4)
                }
                
                // Brand Text Elements
                VStack(spacing: 14) {
                    Text("LEMON")
                        .font(Theme.title(48, weight: .thin))
                        .tracking(12)
                        .foregroundStyle(Theme.ink)
                        .opacity(contentOpacity)
                    
                    // Custom thin horizontal embellishment line
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(Theme.inkFaded)
                            .frame(width: 24, height: 1)
                        Circle()
                            .fill(Theme.inkFaded)
                            .frame(width: 3, height: 3)
                        Rectangle()
                            .fill(Theme.inkFaded)
                            .frame(width: 24, height: 1)
                    }
                    .opacity(contentOpacity * 0.7)
                    
                    Text("My Personal Cafe")
                        .font(.system(size: 14, weight: .regular, design: .default).italic())
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .opacity(contentOpacity)
                }
                
                Spacer()
                
                // Idiomatic Animated Loading Dots
                HStack(spacing: 8) {
                    LoadingDot(delay: 0.0)
                    LoadingDot(delay: 0.2)
                    LoadingDot(delay: 0.4)
                }
                .opacity(contentOpacity * 0.8)
                .padding(.bottom, 36)
            }
        }
        .onAppear {
            // Playful scale bounce on load
            withAnimation(.spring(response: 0.65, dampingFraction: 0.58, blendDuration: 0)) {
                logoScale = 1.0
            }
            
            // Seamless breathing/floating logo animation
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                logoOffset = -8
            }
            
            // Smooth text element fade-in
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                contentOpacity = 1.0
            }
        }
    }
}

/// An elegant, self-animating loading dot using repeat-forever transitions.
private struct LoadingDot: View {
    let delay: Double
    @State private var opacity: Double = 0.2
    
    var body: some View {
        Circle()
            .fill(Theme.inkFaded)
            .frame(width: 6, height: 6)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(delay)) {
                    opacity = 1.0
                }
            }
    }
}

#Preview {
    WelcomeView(onSkip: {})
}
