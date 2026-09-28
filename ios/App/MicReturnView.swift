import SwiftUI

/// Shown when the keyboard sends the user here to turn the mic on (`noboard://mic`).
/// The mic is already on by then; this only tells them how to get back to the app they came from.
struct MicReturnView: View {
    @Environment(\.wide) private var wide
    var error: String?
    let done: () -> Void

    /// iPad shows no "‹ App" link when a keyboard opens noboard, so there's nothing to point at.
    private let backLink = UIDevice.current.userInterfaceIdiom == .phone

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Points at the "‹ App" link iOS shows at the top-left after an app opens another.
            if backLink {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.left")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.bounce.up, options: .repeat(.periodic(delay: 1)))
                    Text("Tap ‹ up here").textStyle(.overline(wide), Theme.accent)
                }
                .padding(.top, 8)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                DotLabel(text: error == nil ? "Mic on" : "Mic off", color: error == nil ? Theme.mic : Theme.faint)
                Text(error == nil ? "You're set.\nGo back and talk." : "The mic couldn't start.")
                    .textStyle(.title(wide))
                Text(error ?? (backLink
                    ? "Tap the ‹ at the very top-left to return to the app you were in, then hold the noboard button and speak."
                    : "Switch back to the app you were in, then hold the noboard button and speak."))
                    .textStyle(.body(wide), Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            PrimaryButton("Done", action: done)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }
}
