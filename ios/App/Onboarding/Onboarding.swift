import AVFoundation
import SwiftUI

/// The onboarding steps, in order. Stored by raw value so a relaunch resumes where the user left off.
enum OnboardingStep: Int, CaseIterable {
    case welcome, howItWorks, tryEmail, tryNotes, keyboard, keyboardDone, mic, realKeyboard

    /// Position in the 6-segment progress bar (Welcome has none).
    var progress: Int {
        switch self {
        case .welcome: 0
        case .howItWorks: 1
        case .tryEmail: 2
        case .tryNotes: 3
        case .keyboard, .keyboardDone: 4
        case .mic: 5
        case .realKeyboard: 6
        }
    }

    var practices: Bool { self == .tryEmail || self == .tryNotes }
}

/// Welcome → How it works → two practice reps → keyboard → mic → the real keyboard → Home.
struct OnboardingView: View {
    @AppStorage("onboardingStep") private var storedStep = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var step = OnboardingStep.welcome
    @State private var forward = true
    /// The 03a pre-prompt, shown over the email rep on the first hold.
    @State private var askingMic = false
    @State private var practice = Practice()
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome {
                StepHeader(progress: step.progress, back: back)
            }
            ZStack {
                page
                    .id(askingMic ? -1 : step.rawValue)
                    .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading),
                                            removal: .move(edge: forward ? .leading : .trailing))
                        .combined(with: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            if step.practices && !askingMic {
                PracticeStrip(practice: practice)
                    .transition(.move(edge: .bottom))
            }
        }
        .background(Theme.background)
        .onAppear {
            // A relaunch mid-way resumes; the done screen only makes sense right after Settings.
            let saved = OnboardingStep(rawValue: storedStep) ?? .welcome
            step = saved == .keyboardDone ? .keyboard : saved
            // Past the keyboard step without Full Access confirmed: the keyboard can't work, so check it first.
            if step.rawValue > OnboardingStep.keyboard.rawValue, !SetupStatus.shared.fullAccess { step = .keyboard }
            practice.target = step
            practice.askPermission = { go { askingMic = true } }
        }
        .onChange(of: step) { old, new in
            storedStep = new.rawValue
            practice.target = new
            if old.practices, !new.practices {
                Task { await DictationController.shared.endInApp() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { SetupStatus.shared.refresh() }
        }
    }

    @ViewBuilder private var page: some View {
        if askingMic {
            MicPermissionStep {
                practice.clearHint()
                go(forward: false) { askingMic = false }
            }
        } else {
            switch step {
            case .welcome: WelcomeStep { advance() }
            case .howItWorks: HowItWorksStep { advance() }
            case .tryEmail: PracticeStep(exercise: .email, practice: practice) { advance() }
            case .tryNotes: PracticeStep(exercise: .notes, practice: practice) { advance() }
            case .keyboard: KeyboardStep(added: { advance() }, skip: { go { step = .mic } })
            case .keyboardDone: KeyboardDoneStep { advance() }
            case .mic: MicStep { advance() }
            case .realKeyboard: RealKeyboardStep(finish: complete)
            }
        }
    }

    private func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return complete() }
        go { step = next }
    }

    private func back() {
        if askingMic { return go(forward: false) { askingMic = false } }
        // The done screen is transient; going back from the mic lands on the keyboard instructions.
        let previous: OnboardingStep = step == .mic ? .keyboard : OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome
        go(forward: false) { step = previous }
    }

    private func go(forward: Bool = true, _ change: () -> Void) {
        self.forward = forward
        withAnimation(.spring(duration: 0.4, bounce: 0)) { change() }
    }

    private func complete() {
        Task { await DictationController.shared.endInApp() }
        storedStep = OnboardingStep.welcome.rawValue
        finish()
    }
}

/// Back chevron, the 6-segment progress bar and "n/6".
struct StepHeader: View {
    @Environment(\.wide) private var wide
    var progress: Int
    var back: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: back) {
                Chevron()
                    .stroke(.white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 12, height: 20)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Back")
            HStack(spacing: 4) {
                ForEach(1...6, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index <= progress ? .white : Theme.hairline)
                        .frame(height: 3)
                }
            }
            .animation(.easeOut(duration: 0.3), value: progress)
            Text("\(progress)/6")
                .textStyle(TextStyle(size: 12, weight: .medium, tracking: 0.04, mono: true), Theme.tertiary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.leading, wide ? 0 : 12)
        .padding(.trailing, wide ? 0 : 16)
        .frame(maxWidth: wide ? 600 : .infinity)
        .frame(height: 44)
        .padding(.top, wide ? 24 : 4)
    }
}

struct Chevron: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX - rect.width / 6, y: rect.minY + rect.height / 10))
        path.addLine(to: CGPoint(x: rect.minX + rect.width / 6, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width / 6, y: rect.maxY - rect.height / 10))
        return path
    }
}

/// A step's page: scrollable content in the 24 pt margins (a centred 560 pt column on iPad),
/// with the footer (the primary button) pinned below. Content gets at least the visible height, so
/// `Spacer`s inside it place things as in the design and small phones scroll instead of clipping.
struct StepPage<Content: View, Footer: View>: View {
    @Environment(\.wide) private var wide
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer
    @State private var height: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .frame(maxWidth: wide ? 560 : .infinity, minHeight: height, alignment: .topLeading)
                    .padding(.horizontal, wide ? 0 : 24)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.never)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            VStack(spacing: 20) { footer }
                .frame(maxWidth: wide ? 560 : .infinity)
                .padding(.horizontal, wide ? 0 : 24)
                .padding(.top, 12)
                .padding(.bottom, wide ? 36 : 8)
        }
    }
}

/// Overline, title and body at the top of a step.
struct StepTitle: View {
    @Environment(\.wide) private var wide
    var overline: String
    var title: String
    var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(overline).textStyle(.overline(wide), Theme.tertiary)
            Text(title).textStyle(.title(wide))
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message).textStyle(.body(wide), Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "iPhone" or "iPad", for copy like "Audio stays on this iPhone".
let deviceName = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
