import SwiftUI

/// The keyboard's Metal orb (`Keyboard/OrbView.swift`) in SwiftUI. `pulse` changes flash it (text arrived),
/// `shake` changes shake it (nothing heard). While recording it follows the mic level the app publishes.
struct Orb: UIViewRepresentable {
    var phase: KeyboardHandoff.Phase
    var pulse = 0
    var shake = 0

    func makeUIView(context: Context) -> OrbView {
        let view = OrbView()
        view.phase = phase
        return view
    }

    func updateUIView(_ view: OrbView, context: Context) {
        view.phase = phase
        if pulse != context.coordinator.pulse { view.flash() }
        if shake != context.coordinator.shake { view.shake() }
        context.coordinator.pulse = pulse
        context.coordinator.shake = shake
    }

    func makeCoordinator() -> Counts { Counts(pulse: pulse, shake: shake) }

    final class Counts {
        var pulse: Int
        var shake: Int
        init(pulse: Int, shake: Int) {
            self.pulse = pulse
            self.shake = shake
        }
    }
}
