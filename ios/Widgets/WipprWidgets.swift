import AppIntents
import SwiftUI
import WidgetKit

@main
struct WipprWidgets: WidgetBundle {
    var body: some Widget {
        DictationLiveActivity()
        DictationControl()
    }
}

/// Control Center / Lock Screen / Action Button trigger.
struct DictationControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "cx.immortal.wippr.dictate") {
            ControlWidgetButton(action: ToggleDictationIntent()) {
                Label("Dictate", systemImage: "mic.fill")
            }
        }
        .displayName("wippr Dictate")
        .description("Start or stop dictation. The text is copied for pasting.")
    }
}
