import AppIntents

/// The one entry point for every trigger: the Dynamic Island / Lock Screen button,
/// the Control Center / Action Button control, and Siri.
///
/// - `AudioRecordingIntent` is Apple's sanctioned way to start the mic from the background.
/// - `LiveActivityIntent` makes the system run `perform()` in the app's process (not the widget's)
///   and lets it start a Live Activity from the background.
///
/// The widget extension compiles this file only so its buttons can reference the intent.
struct ToggleDictationIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Toggle Dictation"
    static let description = IntentDescription(
        "Starts or stops wippr dictation without opening the app. When it stops, returns the cleaned-up text and copies it."
    )
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String?> {
        #if WIDGET_EXTENSION
        return .result(value: nil)
        #else
        return .result(value: try await DictationController.shared.toggle())
        #endif
    }
}
