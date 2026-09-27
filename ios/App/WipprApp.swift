import AppIntents
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

/// "Hey Siri, dictate with wippr" — Siri owns the wake word, so wippr needs none.
struct WipprShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleDictationIntent(),
            phrases: ["Dictate with \(.applicationName)", "Toggle \(.applicationName)"],
            shortTitle: "Dictate",
            systemImageName: "mic.fill"
        )
    }
}

private struct SetupView: View {
    @State private var problems: [String]?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("wippr").font(.largeTitle.bold())
            Text("""
            1. Long-press the Dynamic Island and tap the mic.
            2. Speak.
            3. Long-press again and tap stop.
            4. Tap a text field and paste.

            Also works from Control Center, the Action Button, and "Hey Siri, dictate with wippr".
            """)
            Button(problems == nil ? "Set up" : "Check again") {
                Task { problems = await DictationController.shared.setUp() }
            }
            .buttonStyle(.borderedProminent)
            if let problems {
                if problems.isEmpty {
                    Label("Ready. The mic is in the Dynamic Island.", systemImage: "checkmark.circle")
                }
                ForEach(problems, id: \.self) { Label($0, systemImage: "exclamationmark.triangle") }
            }
            Spacer()
        }
        .padding()
    }
}
