import AVFoundation
import SwiftUI

/// The Microphone card with the big switch, bound to @AppStorage("mic") → `DictationController.setMic`.
/// `large` is the mic step's version (28 pt title, 88×52 switch); Home's is smaller with a detail line.
struct MicCard: View {
    @AppStorage("mic") private var micOn = false
    @State private var error: String?
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: large ? 6 : 4) {
                    DotLabel(text: micOn ? "Mic on" : "Mic off", color: micOn ? Theme.mic : Theme.faint)
                    Text("Microphone").textStyle(TextStyle(size: large ? 28 : 24, weight: .bold, tracking: -0.03, lineHeight: large ? 32 : 28))
                    if !large {
                        Text(micOn ? "On in the background. Music plays on." : "Off. The keyboard can't hear you.")
                            .textStyle(.caption, Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                BigSwitch(isOn: $micOn, width: large ? 88 : 64, height: large ? 52 : 38)
            }
            if let error {
                HStack(spacing: 8) {
                    Text(error).textStyle(.caption, Theme.mic).fixedSize(horizontal: false, vertical: true)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .textStyle(TextStyle(size: 13, weight: .semibold, lineHeight: 18))
                }
            }
        }
        .padding(.leading, large ? 24 : 22)
        .padding(.trailing, large ? 22 : 20)
        .padding(.vertical, large ? 22 : 20)
        .frame(maxHeight: .infinity) // matches its neighbour in Home's iPad grid
        .card(radius: 28)
        .onChange(of: micOn) { _, on in
            Task {
                // Kept when this change is our own revert after a failure.
                if on { error = nil }
                if on, !(await AVAudioApplication.requestRecordPermission()) {
                    error = DictationController.InAppError.micDenied.localizedDescription
                    micOn = false
                    return
                }
                do { try await DictationController.shared.setMic(on) } catch let failure {
                    if micOn == on {
                        error = "Mic failed: \(failure.localizedDescription)"
                        micOn = false
                    }
                }
                SetupStatus.shared.refresh()
            }
        }
    }
}
