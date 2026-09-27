# wippr architecture (v0.1)

**TL;DR (2026-09-26)**
- One App Intent (`ToggleDictationIntent`: `AudioRecordingIntent` + `LiveActivityIntent`, `supportedModes = .background`) is the trigger for everything: the expanded Dynamic Island button, the Lock Screen button, the Control Center / Action Button control, and a Siri phrase.
- A "ready" Live Activity stays in the island between dictations. iOS lets the app update an existing activity from the background at any time, even where starting a new one might fail.
- ASR is Apple `SpeechTranscriber` and cleanup is Apple Foundation Models. Both are system-managed and run out of process: no model weights to ship, and no clash with the GPU ban for background apps.
- Delivery is the clipboard. There is no keyboard extension, by design. If iOS refuses a clipboard write from the background, the island says so and the next app open copies the text.
- No wake word. "Hey Siri, dictate with wippr" covers hands-free use without an always-on mic (see `ios-platform-constraints.md` §4).

## Flow

```
tap mic (island expanded / control / Siri)
  → ToggleDictationIntent.perform()  [app process, app stays in background]
  → DictationController.start: update Live Activity → AVAudioSession(.record) → Transcriber.start
      (Cleaner() created here to prewarm the model while the user speaks)
  … live transcript streams into the island (throttled to 2 updates/s, last 300 chars)
tap stop
  → DictationController.finish: Transcriber.stop (finalize) → Cleaner.clean → UIPasteboard
  → island shows "Copied — paste anywhere" → intent returns the text (usable in Shortcuts)
```

## Decisions

| Decision | Why | Rejected |
|---|---|---|
| No keyboard | The project's whole point. iOS 27's "Paste from <App>" suggestion makes clipboard delivery nearly one tap. | Thin keyboard strip: it is still a keyboard, and needs Full Access plus App Group IPC. Revisit only if device testing shows paste is too slow. |
| Apple SpeechTranscriber | Runs on device, streams, ships no weights, and is managed by the system. | Parakeet/WhisperKit in-process: accuracy compared in `bench-asr.md`; needs the iOS 27 background ANE entitlement plus model loading (3.4 s cold). |
| Apple Foundation Models | Runs out of process, so GPU background rules don't apply. Needs no download. | llama.cpp / MLX small model: Metal is blocked in the background, and CPU-only is slower. See `bench-cleanup-llm.md` for the non-Apple-Intelligence fallback. |
| One toggle intent | Every trigger behaves the same way, with one code path. | Separate start/stop/cancel intents. |
| Siri phrase instead of a wake word | Apple bears the battery and indicator cost, with no App Review 2.5.4 risk. | Porcupine / openWakeWord with an always-on mic. |

## Known gaps (verify on device)

See TODO.md Phase 4. The biggest risks are:
1. Background mic start from the island button with the app suspended, killed, or the phone locked.
2. A clipboard write from the background.
3. `SpeechTranscriber` behaviour in the background on iOS 27.
