import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private typealias State = DictationAttributes.ContentState

/// Compact and minimal island views are not interactive (a tap opens the app).
/// The mic button lives in the expanded view (long-press) and on the Lock Screen.
struct DictationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictationAttributes.self) { context in
            HStack(spacing: 12) {
                StatusText(state: context.state)
                Spacer()
                ToggleButton(phase: context.state.phase)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PhaseIcon(phase: context.state.phase).font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ToggleButton(phase: context.state.phase)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    StatusText(state: context.state)
                }
            } compactLeading: {
                PhaseIcon(phase: context.state.phase)
            } compactTrailing: {
                if context.state.phase == .ready, !context.state.copied {
                    Image(systemName: "doc.on.clipboard").foregroundStyle(.orange)
                }
            } minimal: {
                PhaseIcon(phase: context.state.phase)
            }
        }
    }
}

private struct PhaseIcon: View {
    let phase: State.Phase

    var body: some View {
        switch phase {
        case .ready: Image(systemName: "mic").foregroundStyle(.secondary)
        case .recording: Image(systemName: "waveform").foregroundStyle(.red)
        case .processing: Image(systemName: "sparkles").foregroundStyle(.yellow)
        case .listening: Image(systemName: "ear").foregroundStyle(.green)
        }
    }
}

private struct ToggleButton: View {
    let phase: State.Phase

    var body: some View {
        Button(intent: ToggleDictationIntent()) {
            Image(systemName: phase == .recording ? "stop.fill" : phase == .listening ? "ear.slash" : "mic.fill")
                .font(.title2)
                .frame(width: 44, height: 44)
        }
        .tint(phase == .recording ? .red : .accentColor)
        .disabled(phase == .processing)
    }
}

private struct StatusText: View {
    let state: State

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if !state.text.isEmpty {
                Text(state.text).font(.callout).lineLimit(2).truncationMode(.head)
            }
        }
    }

    private var title: String {
        switch state.phase {
        case .recording: "Listening…"
        case .processing: "Cleaning up…"
        case .ready where state.text.isEmpty: "Tap the mic to dictate"
        case .ready: state.copied ? "Copied — paste anywhere" : "Tap to open wippr and copy"
        case .listening: "Say “wipper” then speak"
        }
    }
}
