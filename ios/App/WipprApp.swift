import SwiftUI

@main
struct WipprApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            SetupView()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await DictationController.shared.appDidBecomeActive() }
            }
        }
    }
}

private struct SetupView: View {
    @State private var problems: [String]?
    @AppStorage("mic") private var micOn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("wippr").font(.largeTitle.bold())
            Text("""
            1. Add the keyboard: Settings → General → Keyboard → Keyboards → Add New Keyboard → wippr, then turn on Allow Full Access.
            2. Turn the mic on below. It stays on in the background (orange dot) until you turn it off.
            3. In any app, switch to the wippr keyboard, tap the mic, speak, and tap it again. The text is typed for you.
            """)
            Button(problems == nil ? "Set up" : "Check again") {
                Task { problems = await DictationController.shared.setUp() }
            }
            .buttonStyle(.borderedProminent)
            if let problems {
                if problems.isEmpty {
                    Label("Ready.", systemImage: "checkmark.circle")
                }
                ForEach(problems, id: \.self) { Label($0, systemImage: "exclamationmark.triangle") }
            }
            Toggle("Mic on for the wippr keyboard", isOn: $micOn)
                .onChange(of: micOn) { _, on in
                    Task {
                        do { try await DictationController.shared.setMic(on) } catch {
                            micOn = false
                            problems = ["Mic failed: \(error.localizedDescription)"]
                        }
                    }
                }
            Spacer()
        }
        .padding()
    }
}
