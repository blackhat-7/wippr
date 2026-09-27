# wippr iOS

Dictation from a one-row keyboard.

Open wippr once and turn the mic on (it stays on in the background). Then, in any app, switch to the wippr keyboard, tap the mic, speak, and tap again. The text is typed into the field.

## Build (needs a Mac)

```sh
brew install xcodegen
cd ios && xcodegen
open Wippr.xcodeproj
```

The team is set in `project.yml`. Run on a device, then add the keyboard in Settings → General → Keyboard → Keyboards and allow Full Access.

Requirements:
- iOS 26+.
- Cleanup needs an Apple Intelligence iPhone (15 Pro or later). Without one, text is copied uncleaned.

## Files

| File | Role |
|---|---|
| `Keyboard/KeyboardViewController.swift` | One-row keyboard (36 pt): mic button, status, delete, return. Types the dictation into the focused field. |
| `Shared/KeyboardHandoff.swift` | Keyboard ↔ app link: start/stop, status heartbeat, and text, as App Group files that both sides poll. |
| `App/DictationController.swift` | Keeps the mic on in the background. Runs a dictation on the keyboard's command: transcript → cleanup → keyboard + clipboard. |
| `App/Mic.swift` | Always-on `AVAudioEngine` input; audio is dropped unless a dictation is running. |
| `App/Transcriber.swift` | One dictation with Apple `SpeechTranscriber` (on-device). |
| `App/Cleaner.swift` | Apple Foundation Models cleanup prompt. |
| `App/WipprApp.swift` | Setup screen and the mic on/off toggle. |

Design and the reasons behind it: `../learnings/architecture.md`.

## Test on device first

The steps are in `../TODO.md` → Phase 4.
