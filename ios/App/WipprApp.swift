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
    @AppStorage("mic") private var micOn = false
    /// Set while showing the "go back" screen after the keyboard sent the user here for the mic.
    @State private var micReturn: String?? = nil

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
        .onOpenURL(perform: open)
        .fullScreenCover(isPresented: Binding(get: { micReturn != nil }, set: { if !$0 { micReturn = nil } })) {
            AdaptiveRoot { MicReturnView(error: micReturn ?? nil) { micReturn = nil } }
                .preferredColorScheme(.dark)
        }
    }

    /// Links from the keyboard: `noboard://mic` turns the mic on right away (the app is in the foreground now,
    /// which iOS requires), `noboard://keyboard` goes to the keyboard setup step.
    private func open(_ url: URL) {
        switch url.host {
        case "mic":
            Task {
                do {
                    try await DictationController.shared.setMic(true)
                    micOn = true
                    micReturn = .some(nil)
                } catch {
                    micReturn = .some(error.localizedDescription)
                }
            }
        case "keyboard":
            onboardingStep = OnboardingStep.keyboard.rawValue
            onboarded = false
        default:
            break
        }
    }
}
