# wippr iOS

Dictation from the Dynamic Island. No keyboard.

Long-press the island → tap the mic → speak → long-press → tap stop → paste. On iOS 27, the keyboard's "Paste from wippr" suggestion makes the paste one tap.

The same toggle also runs from Control Center, the Action Button, and "Hey Siri, dictate with wippr".

## Build (needs a Mac)

```sh
brew install xcodegen
cd ios && xcodegen
open Wippr.xcodeproj
```

Set your team under Signing for both targets, then run on a device. The simulator has no Dynamic Island mic path.

Requirements:
- iOS 26+.
- Cleanup needs an Apple Intelligence iPhone (15 Pro or later). Without one, text is copied uncleaned.

## Files

| File | Role |
|---|---|
| `Shared/ToggleDictationIntent.swift` | The one intent every trigger runs. `AudioRecordingIntent` + `LiveActivityIntent`, background mode. |
| `Shared/DictationAttributes.swift` | Live Activity state: ready / recording / processing. |
| `App/DictationController.swift` | Island → mic → transcript → cleanup → clipboard + keyboard. Always-on "wipper" listening. |
| `App/Transcriber.swift` | Mic → Apple `SpeechTranscriber` (on-device). |
| `App/Cleaner.swift` | Apple Foundation Models cleanup prompt. |
| `App/WipprApp.swift` | Setup screen + Siri phrase. |
| `Keyboard/` | One-row keyboard (36 pt) that types the latest dictation into the focused field. |
| `Shared/KeyboardHandoff.swift` | App → keyboard text handoff: App Group file + Darwin notification. |
| `Widgets/` | Dynamic Island / Lock Screen UI and the Control Center control. |

Design and the reasons behind it: `../learnings/architecture.md`.

## Test on device first

The steps are in `../TODO.md` → Phase 4.
