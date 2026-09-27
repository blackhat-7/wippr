import SwiftUI

@main
struct WipprApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await DictationController.shared.appDidBecomeActive() }
            }
        }
    }
}

/// Onboarding until it's finished once, then Home. Home's "Re-check setup" can send the user back
/// to the keyboard step.
private struct RootView: View {
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("onboardingStep") private var onboardingStep = 0

    var body: some View {
        AdaptiveRoot {
            ZStack {
                if onboarded {
                    HomeView {
                        onboardingStep = OnboardingStep.keyboard.rawValue
                        withAnimation { onboarded = false }
                    }
                    .transition(.opacity)
                } else {
                    OnboardingView { withAnimation { onboarded = true } }
                        .transition(.opacity)
                }
            }
        }
        .preferredColorScheme(.dark)
        .background(Theme.background.ignoresSafeArea())
    }
}
