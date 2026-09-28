# wippr iOS

Dictation from a one-row keyboard.

Open wippr once and turn the mic on (it stays on in the background). Then, in any app, switch to the wippr keyboard, hold the button, speak, and let go. The text is typed into the field.

Edit mode: while holding, slide up out of the keyboard (the button turns purple) and say an instruction — "make it more formal", "turn this into bullets", or in an empty field "git command to undo the last commit". It rewrites the selection, or the text before the cursor. Tap the button within 5 s to undo.

## Build (needs a Mac)

```sh
brew install xcodegen
cd ios && xcodegen
open Wippr.xcodeproj
```

The team and bundle ID are set in `Config/Signing.xcconfig`. To build under your own Apple account, create `Config/Local.xcconfig` (gitignored) with your values:

```
DEVELOPMENT_TEAM = YOURTEAMID
APP_BUNDLE_ID = com.yourname.noboard
```

The keyboard's ID and the App Group follow from `APP_BUNDLE_ID`. Run on a device, then add the keyboard in Settings → General → Keyboard → Keyboards and allow Full Access.

Requirements:
- iOS 26+.
- Cleanup needs an Apple Intelligence iPhone (15 Pro or later). Without one, text is copied uncleaned.

## Files

| File | Role |
|---|---|
| `Keyboard/KeyboardViewController.swift` | One-row keyboard (36 pt). Hold anywhere to talk (haptics), release to write; globe, delete, return on the right. Types the dictation into the focused field. |
| `Keyboard/OrbView.swift` | Blue watercolour orb (Core Animation port of ask-ndtv-ui's shader orb): calm idle, energetic while listening, swirl while writing. |
| `Shared/KeyboardHandoff.swift` | Keyboard ↔ app link: start/stop, status heartbeat, and text, as App Group files that both sides poll. |
| `App/DictationController.swift` | Keeps the mic on in the background. Runs a dictation on the keyboard's command: transcript → cleanup → keyboard + clipboard. |
| `App/Mic.swift` | Always-on `AVAudioEngine` input. Keeps a 3 s pre-roll so a dictation starts from the moment the key went down. |
| `App/Transcriber.swift` | One dictation with Apple `SpeechTranscriber` (on-device). |
| `App/Cleaner.swift` | Apple Foundation Models cleanup prompt. |
| `App/Editor.swift` | Edit mode: applies a spoken instruction to the selection / text before the cursor, or writes what it asks for (e.g. a terminal command). On-device only. |
| `App/WipprApp.swift` | Setup screen and the mic on/off toggle. |

Design and the reasons behind it: `../learnings/architecture.md`.

## Test on device first

The steps are in `../TODO.md` → Phase 4.
