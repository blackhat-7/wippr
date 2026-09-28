# iOS platform constraints for wippr

Researched 2026-09-26. iOS 27 shipped 2026-09-14 ([MacRumors](https://www.macrumors.com/2026/09/09/apple-announces-ios-27-release-date/)). Apple docs were read as DocC JSON (`developer.apple.com/tutorials/data/documentation/<path>.json`). Every Swift symbol below comes from a doc page I fetched. The link is given next to it.

Labels: **[Doc]** = Apple documentation or an Apple engineer on the forums. **[Reported]** = a developer says it works (repo, forum, or shipping app). **[Unverified]** = my inference, or claims that conflict.

## TL;DR

- **A button in the expanded Dynamic Island (or the Lock Screen Live Activity) can run an App Intent in the app's process without opening the app. [Doc]** The compact and minimal views are **not** interactive. Tapping them opens the app. [Doc] You reach the expanded view with a long-press. [Doc]
- **Starting the mic from the background is the hard part.** Apple's general rule: "An app must be in the foreground to start recording" [Doc]. The one sanctioned exception is an intent that conforms to **`AudioRecordingIntent`** (iOS 18+) and keeps a Live Activity running [Doc]. Add **`LiveActivityIntent`** so it may *start* that Live Activity from the background [Doc], plus `supportedModes = .background` (iOS 26+). KeyVox ships exactly this and says it records with no app bounce [Reported]. Apps that left out `LiveActivityIntent` hit "Target is not foreground" [Reported]. **Verify on a device first.**
- **Safe fallback (Wispr-style): start the mic once in the foreground, then keep it alive.** It can then record "indefinitely in the background", with the orange mic dot showing [Doc, Quinn/DTS]. Island buttons then only mark start and stop.
- **No app can type into another app's text field without a keyboard extension.** The options are: (a) the clipboard, now helped by the **iOS 27 "Paste from <App>" suggestion above the system keyboard** [Reported, press]; or (b) a thin wippr keyboard that inserts through `textDocumentProxy`. Keyboards cannot use the mic [Doc].
- **On-device stack:** `SpeechAnalyzer` + `SpeechTranscriber` (iOS 26) for ASR, and the Foundation Models on-device model for cleanup (4,096-token context, Apple Intelligence devices only, rate-limited in the background). Both run out of process. **iOS 27 blocks Neural Engine use in the background without the new `continued-processing.inference` entitlement [Doc]. GPU/Metal is blocked in the background [Doc].** In-process models like Parakeet or llama.cpp must plan around that.
- **Wake word: technically possible, bad in practice.** It needs an always-on mic session (orange dot, battery drain, Siri blocked, dies after a phone call). App Review may reject it under 2.5.4. Use **"Hey Siri, <App Shortcut phrase>"** as the hands-free trigger instead.

---

## 1. Can a Dynamic Island button start recording while the app is in the background?

### 1a. What the island views can do [Doc]

From [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) and [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities):

- Compact: "People can tap a compact Live Activity to open the app." Minimal behaves the same way.
- "When people touch and hold a Live Activity in a compact or minimal presentation, the system displays the content in an expanded presentation." Updates also flash the expanded view briefly.
- "Live Activities can include buttons or toggles in the **expanded and the Lock Screen presentation**." So **no interactive `Button` in compact or minimal.** A tap there just opens the app (use `widgetURL(_:)` / `Link` to deep-link).
- Buttons take an App Intent. "By default, the system runs the app intent in the same process as the widget extension. However, if … the intent conforms to `AudioPlaybackIntent`, `ForegroundContinuableIntent`, **`LiveActivityIntent`**, or `PushToTalkTransmissionIntent`, the system performs the app intent in the **app's process**." That is what we need: the app's process owns the audio engine and the models.
- "On a locked device, buttons and toggles are inactive and the system doesn't perform actions unless a person authenticates and unlocks their device." (Same page.) So **Lock Screen taps may need Face ID**.
- "Transient" Live Activities (`style: .transient`) exist, but they end when you leave the app. They are useless here.

### 1b. The background-recording rule [Doc]

- DTS (Apple engineer, [thread 770556](https://developer.apple.com/forums/thread/770556)): "An app must be in the foreground to start recording. If the app has specified the 'audio' background mode … it can then continue recording when it moves into the background."
- Apple engineer, Jan 2025 ([thread 771457](https://developer.apple.com/forums/thread/771457)): "In general, it is not possible to start a recording from the background. One alternative would be to implement the `AudioRecordingIntent` protocol."
- DTS Kevin Elliott, Feb 2026 ([thread 816408](https://developer.apple.com/forums/thread/816408), BLE-button trigger): "There's a privacy block in place that prevents recording sessions from activating in the background" within the general audio API. Only CallKit, LiveCommunicationKit and PushToTalk bypass it, and only for communication apps.
- The failure shows up as `AVAudioSession.ErrorCode.cannotStartRecording` (`'!rec'` = 561145187). Its doc says this "usually occurs when an app starts a mixable recording from the background" ([doc](https://developer.apple.com/documentation/coreaudiotypes/avaudiosession/errorcode/cannotstartrecording)).

### 1c. `AudioRecordingIntent` (iOS 18+) [Doc]

[`AudioRecordingIntent`](https://developer.apple.com/documentation/appintents/audiorecordingintent): "tell the system that your app records audio. As a result of this intent, the system displays an audio recording indicator. … **you must start a Live Activity when you begin the audio recording and keep it active as long as you record audio. If you don't start a Live Activity, the audio recording stops.**"

hex-iphone reports that iOS **hard-crashes** an `AudioRecordingIntent` that has an active audio session but no Live Activity ([code comment](https://github.com/Luraxx/hex-iphone/blob/main/Hex/App/AppModel.swift)) [Reported]. Wispr users who turned Live Activities off got "quit unexpectedly" crashes (see `wispr-flow-product.md`).

### 1d. Starting the Live Activity itself from the background [Doc]

[`LiveActivityIntent`](https://developer.apple.com/documentation/appintents/liveactivityintent): "In general, your app needs to be in the foreground to start a Live Activity. However, you can use a `LiveActivityIntent` and start the Live Activity in its `perform()` method. When the system performs the intent, the system launches your app process without opening the app, performs the intent, and starts the Live Activity."

### 1e. Resolved conflict: KeyVox (works headless) vs hex-iphone / OpenWhispr ("Target is not foreground")

| Project | Intent conformances | Result |
|---|---|---|
| [KeyVox](https://github.com/macmixing/keyvox) `ToggleKeyVoxDictationIntent` (v1.4.0, 2026-09-02) | `AudioRecordingIntent, LiveActivityIntent`; `openAppWhenRun = false`; `authenticationPolicy = .alwaysAllowed`; `@available(iOS 26) supportedModes = .background` | "Starts and stops dictation without opening KeyVox" [Reported, shipping] |
| [hex-iphone](https://github.com/Luraxx/hex-iphone) `ToggleDictationIntent` (iOS 18 target) | `AudioRecordingIntent, ForegroundContinuableIntent`. **No `LiveActivityIntent`** | `Activity.request` fails with "Target is not foreground", so it hops to the foreground |
| [forum 815725](https://developer.apple.com/forums/thread/815725) (Feb 2026) | `AudioRecordingIntent` (other conformances not shown) | "Live Activity start failed: … Target is not foreground" |

**Conclusion [Doc + Reported]:** the difference is the **`LiveActivityIntent` conformance**, which the docs name as the thing that grants permission to start a Live Activity from the background. hex-iphone itself relies on this for its *island* button: `StartDictationFromActivityIntent: LiveActivityIntent, AudioRecordingIntent`, whose code comment says "AudioRecordingIntent permits the background mic start". A community reply on 815725 claims a background start is impossible. That claim is not from Apple, and it predates KeyVox's release.

**KeyVox recipe** (read from `iOS/KeyVox iOS/App/Shortcuts/ToggleKeyVoxDictationIntent.swift`, `App/LiveActivity/KeyVoxSessionLiveActivityCoordinator.swift`, `iOS/Docs/ENGINEERING.md`):
1. Info.plist: `UIBackgroundModes = ["audio"]` (from ENGINEERING.md). Live Activities also need `NSSupportsLiveActivities = YES` [Doc]. App Group shared with the keyboard. Deployment target iOS 18.6. The `.background` mode applies only on iOS 26+.
2. Entitlement: `com.apple.developer.background-tasks.continued-processing.inference` (added for iOS 27 so its Core ML ASR can use the ANE in the background).
3. In `perform()`, call `Activity.request(attributes:content:pushType: nil)` **first** ("Live Activity preparation must complete before background microphone startup. Disabled Live Activities or failed preparation prevent recording from starting"). **Then** start the recorder (`.playAndRecord`).
4. Stop returns the transcript as the intent's value. The bundled Shortcut copies it to the clipboard and shows a notification. If the KeyVox keyboard is visible, it inserts the text via App Group IPC.

`supportedModes` / `IntentModes` are iOS 26 ([doc](https://developer.apple.com/documentation/appintents/appintent/supportedmodes)): `.background`, `.foreground(.immediate | .dynamic | .deferred)`. `openAppWhenRun` and `ForegroundContinuableIntent` are deprecated in favour of `supportedModes`. `authenticationPolicy` defaults to `.alwaysAllowed` ("including when the device is locked") ([doc](https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy)).

**Still unverified:**
- Starting from the **locked** Lock Screen. [Thread 836958](https://developer.apple.com/forums/thread/836958) (Jul 2026, iOS 26, no replies): `setActive` fails with `'!pla'` 561015905 inside an `AudioRecordingIntent` on the Lock Screen. That intent probably lacked `LiveActivityIntent` (not stated).
- A cold start after iOS has killed the app. The intent relaunches the process, but model load time adds latency.
- Whether App Review accepts it. KeyVox, Wispr and Spokenly ship similar flows (see `oss-alternatives.md`).

### 1f. What wippr's island button can do

- **Expanded-island button → `StartDictation: AudioRecordingIntent, LiveActivityIntent` (supportedModes `.background`) → mic starts, app stays in background.** [Reported to work; must verify]
- If it fails on device: set `supportedModes = [.background, .foreground(.dynamic)]` and continue in the foreground when needed. Or use the "armed session" fallback (§2): the mic is already running, so the button only marks utterance boundaries. This path needs no background activation, so it avoids the privacy block entirely [Doc].
- Compact-island tap = open the app. It could start recording on open, but iOS has no API to return to the previous app (see §3, keyboard).

## 2. How long can it keep recording and stay alive?

- **Recording:** Quinn (DTS), [thread 776949](https://developer.apple.com/forums/thread/776949): "we allow apps that start an audio recording session in the foreground to continue recording indefinitely in the background. That's visible to the user as the orange pill in the status bar." [Doc] So an active recording session keeps the process alive. Declare `audio` in [`UIBackgroundModes`](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes). Every shipping app here does (KeyVox, hex, Wispr).
- **Idle keep-alive** (no mic) = silent-audio tricks. That is an App Review 2.5.4 risk.
- **Live Activity max:** "active for up to eight hours … After the eight-hour limit, the system automatically ends the Live Activity, and immediately removes it from the Dynamic Island". It can stay on the Lock Screen up to 4 more hours (12 h total) [Doc]. A permanent "ready" island therefore dies every 8 h. To restart it, you need the foreground, a `LiveActivityIntent` (Action Button, Control, Siri), or an ActivityKit **push-to-start** from a server [Doc: [push doc](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)].
- **Payload:** static + dynamic data ≤ 4 KB [Doc]. So only a short transcript preview fits in the island.
- **Update budget:** documented for **push** updates only: "a certain budget of ActivityKit push notifications per hour". Priority 5 does not count against it. `NSSupportsLiveActivitiesFrequentUpdates` raises it, and users can turn that off [Doc]. There is no documented number for local `activity.update(...)` calls. Local updates from a running app are fine for a timer or state change (Emoji Rangers sample) [Unverified: exact local throttle].
- **Interruptions:** a phone call interrupts the session. After a call **in the background**, reactivation fails with `'!int'` 560557684 "until the app is opened again" ([thread 813278](https://developer.apple.com/forums/thread/813278), Jan 2026) [Reported]. Plan for a "Resume" button in the island that runs the `AudioRecordingIntent` again [Unverified that this works]. `prefersNoInterruptionsFromSystemAlerts` (iOS 14.5) reduces alert interruptions. iOS 27 adds `activate(options:completionHandler:)`, `AVAudioSession.DeactivationContext` / `InterruptionContext` / `ResumptionRecommendation` for richer interruption info [Doc: [activate](https://developer.apple.com/documentation/avfaudio/avaudiosession/activate(options:completionhandler:))].
- **Other apps:** a non-mixable session activated by another app interrupts ours. `insufficientPriority` = "isn't allowed to set the audio category because it's in use by another app". `siriIsRecording` exists too [Doc: [ErrorCode](https://developer.apple.com/documentation/coreaudiotypes/avaudiosession/errorcode)]. Wispr users report that Siri doesn't work while a Flow session holds the mic.

## 3. Getting text into the frontmost app

| Mechanism | Possible? | Notes |
|---|---|---|
| Type directly into another app's field from our app | **Impossible** | No public API. Accessibility APIs on iOS only expose your own UI. Voice Control and Dictation are system privileges. |
| Shortcuts action that types into the current field | **Impossible** | Shortcuts can copy to the clipboard, show a notification, or return a result. No "type text" action on iOS. |
| Universal Clipboard | Irrelevant | Cross-device only. |
| Writing Tools / Siri / "Type to Siri" | **No** | System UIs. iOS 27 Siri gains App Intents actions and View Annotations ([WWDC26 guide](https://developer.apple.com/wwdc26/guides/ios/)), but nothing inserts text into another app's field. |
| **Clipboard + user paste** | **Yes** | See below. |
| **Custom keyboard extension** | **Yes** | See below. |

### Clipboard

- Writing is free. Reading from **another** app without user intent triggers the iOS 16+ prompt. The prompt is shown **in the reading app**: "programmatic pasting raises a user alert … Use `UIPasteControl` to paste without a user prompt" ([UIPasteboard](https://developer.apple.com/documentation/uikit/uipasteboard), [UIPasteControl](https://developer.apple.com/documentation/uikit/uipastecontrol)) [Doc]. A user-initiated Paste in the target app (edit menu, ⌘V, system paste control) establishes intent. So wippr writing and the user pasting = no prompt. Per-app setting: Settings → app → Paste from Other Apps: Ask/Deny/Allow.
- **iOS 27:** the system keyboard's suggestion bar shows **"Paste from <App>"** with the last copied item: one tap to insert ([MacRumors](https://www.macrumors.com/2026/07/01/ios-27-new-copy-and-paste-feature/), [Paste blog](https://pasteapp.io/blog/ios-27-keyboard-paste-button)) [Reported, press]. The iOS 27 release notes mention "paste candidates" in the Keyboard section, which confirms the feature exists. **This is wippr's best keyboard-free delivery path:** dictate → tap the field → tap "Paste from wippr". One press piece ([The Blaze](https://www.theblaze.com/tech/ios27-paste-permissions)) claims iOS 27 prompts on every paste. Only that one source says so [Unverified].
- **Background writes may be rejected.** hex-iphone: "iOS may have rejected the app's background pasteboard write". It re-copies from the keyboard. Its intent returns the text so a Shortcut's "Copy to Clipboard" can do the copy, "which is allowed to write the pasteboard even though backgrounded apps are not". KeyVox also copies inside its Shortcut, not the app [Reported]. **Verify on device.** If direct writes fail, the island "Done" button can run an intent that returns the text, or we fall back to the Shortcut route.

### Custom keyboard extension [Doc unless marked]

- Sources: [Creating a custom keyboard](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard), [Configuring a custom keyboard interface](https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface), [Configuring open access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard), [archived guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html).
- **Insert text:** `UIInputViewController.textDocumentProxy` (`UITextDocumentProxy`) can "insert or delete text, manipulate the insertion point". No mic is needed.
- **Mic:** without open access: "No access to microphone and speaker". Archived guide: "Custom keyboards … have no access to the device microphone, so dictation input is not possible." An Apple engineer hinted that `RequestsOpenAccess` + `hasDictationKey` might allow it, but the developer still got `'!rec'` ([thread 775077](https://developer.apple.com/forums/thread/775077)). Every shipping app records in the containing app instead.
- **Receiving text from the app:** without open access, the keyboard gets "read-only access to the containing app's shared containers". With Full Access (`RequestsOpenAccess`), it gets a writable shared container and network access. hex-iphone says it needs Full Access to read the App Group [Reported, conflicts with the doc; verify]. Signal with Darwin notifications (hex, dictus).
- **Height:** "You can adjust the height … using Auto Layout". The width is always the screen width. No documented minimum. Minuum (2014) shipped a thin strip ([TechCrunch](https://techcrunch.com/2014/09/17/minuums-ios-8-keyboard-lets-you-see-a-lot-more-screen-as-you-type)). Developers report launch flicker through 0 → full screen → final height ([thread 813579](https://developer.apple.com/forums/thread/813579)). On Face ID iPhones the system also draws its own globe/dictation bar below the keyboard. **A ~50 pt strip is plausible [Unverified].**
- **The system keyboard is forced back for** secure fields and `phonePad` / `namePhonePad` fields. Apps can also reject third-party keyboards.
- **Opening the container app:** iOS 18 broke the selector-based `openURL:` trick. A SwiftUI `Link` still works ([KeyboardKit](https://keyboardkit.com/blog/2024/09/11/ios18-breaks-selector-based-url-opening)) [Reported]. **Returning to the host app is broken.** iOS 26.4 blocked every way to learn the host's bundle ID. Quinn: no public API. FB22247647 is open ([thread 826851](https://developer.apple.com/forums/thread/826851)). dictus uses private SPI (`_hostProcessIdentifier`) ([PR 538](https://github.com/getdictus/dictus-ios/pull/538)). **Avoid.**
- **App Review 4.4.1:** keyboards must work without Full Access, and "must not … Launch other apps besides Settings" ([guidelines](https://developer.apple.com/app-store/review/guidelines/)). Wispr ships a keyboard that launches its app anyway. wippr's keyboard wouldn't need to launch anything, since the island starts recording.
- **Memory:** about 48–60 MB (reported: [RN #31910](https://github.com/facebook/react-native/issues/31910), [dev.to](https://dev.to/tbds_2dadf2b626f315902eae/the-three-hard-constraints-of-an-ios-keyboard-extension-46af); dictus says "~50 MB"). No ASR or LLM inside the keyboard.

## 4. Wake word

- **Technically possible [Doc + Reported]:** once the mic is started in the foreground it can run indefinitely in the background (Quinn). Porcupine: "Developers have been able to successfully run Porcupine … on iOS … in background mode … we cannot guarantee" ([FAQ](https://picovoice.ai/docs/faq/porcupine/)). It **cannot be started** from the background (§1b) except via `AudioRecordingIntent`.
- **Costs:** the orange mic dot is on at all times. A Live Activity is needed if the session was started by an `AudioRecordingIntent`. Battery drain (Wispr users: 100% → 50% in < 2 h). Siri is blocked. Any phone call can kill it until the app is reopened (§2). Other apps' non-mixable sessions interrupt it.
- **App Review:** 2.5.4 "Multitasking apps may only use background services for their intended purposes". 2.5.14 requires consent plus a clear indicator when recording ([guidelines](https://developer.apple.com/app-store/review/guidelines/)). Several reported rejections: "audio background mode is only supposed to be used for audio playback" ([776949](https://developer.apple.com/forums/thread/776949)). Quinn: that is a business question for App Review. Always-listening = high rejection risk.
- **iOS 27:** ANE/GPU wake-word models need the inference entitlement in the background (§7). Porcupine and sherpa-onnx KWS run on the CPU, which is fine.
- **Libraries:** Picovoice Porcupine (commercial, ~1 MB model). [livekit-wakeword](https://github.com/livekit/livekit-wakeword): openWakeWord-compatible, Swift, iOS 16+, ONNX Runtime + CoreML EP. [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) keyword spotting (Apache-2.0, iOS Swift examples). Apple SoundAnalysis `SNClassifierIdentifier.version1` ([doc](https://developer.apple.com/documentation/soundanalysis/snclassifieridentifier/version1)) classifies ~300 sound classes. It is **not** a keyword spotter.
- **Better hands-free trigger:** an App Shortcut ([`AppShortcutsProvider`](https://developer.apple.com/documentation/appintents/appshortcutsprovider)) that runs the same `AudioRecordingIntent`: "Hey Siri, dictate with wippr". Apple owns the wake word, the battery cost and the indicator. [Doc for the API; Reported that it runs in the background by Wispr/KeyVox]

## 5. Other triggers

All of them end up running an App Intent. The background-mic rules from §1 apply to each one.

| Trigger | API | Runs without foregrounding? |
|---|---|---|
| Action Button | Control or App Shortcut (iOS 18) | Yes with `AudioRecordingIntent` + `LiveActivityIntent` [Reported: KeyVox, Wispr]. hex-iphone without `LiveActivityIntent` hops to the foreground. |
| Control Center / Lock Screen control | `ControlWidget` + `ControlWidgetButton` (iOS 18) ([doc](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system)). "buttons perform an action" | Same as above. A lock-screen tap may need authentication. |
| Live Activity expanded / Lock Screen button | `Button(intent:)` with `LiveActivityIntent` | Yes, runs in the app process [Doc]. Mic start: see §1. |
| Back Tap | Accessibility → Back Tap → Shortcut | Runs the Shortcut, which runs the intent. Same as above. |
| Siri | App Shortcut phrase | Same intent. [Reported: Wispr] |
| Compact / minimal island tap | `widgetURL` | **Always opens the app** [Doc]. |

Zero-code baseline users can build today: a Shortcut with iOS 26's "Use Model" action (on-device Apple model) for cleanup, then "Copy to Clipboard" ([Apple Support](https://support.apple.com/guide/iphone/use-apple-intelligence-in-shortcuts-iph78c41eaf8/ios)).

## 6. On-device ASR

| Option | Min iOS | Streaming | Languages | Speed (reported) | Background notes |
|---|---|---|---|---|---|
| **`SpeechAnalyzer` + `SpeechTranscriber`** ([doc](https://developer.apple.com/documentation/speech/speechtranscriber)) | 26 | Yes (volatile + final results, `AsyncSequence` input) | `supportedLocales`. Assets downloaded via `AssetInventory`, shared system-wide | 70× realtime, 14.0% WER on earnings22 (M4 Mac mini, [Argmax, 2025-06](https://www.argmaxinc.com/blog/apple-and-argmax)) | Models are system-managed, so no model in app memory [Unverified whether inference is out of process and exempt from the iOS 27 ANE rule]. `isAvailable` is device-dependent. |
| **`DictationTranscriber`** ([doc](https://developer.apple.com/documentation/speech/dictationtranscriber)) | 26 | Yes | Same as on-device `SFSpeechRecognizer`. Supports `contextualStrings` and custom language models | — | "compatible with older devices". Fallback when `SpeechTranscriber` is unavailable. |
| `SFSpeechRecognizer` + `requiresOnDeviceRecognition` | 13 | Yes | Per locale | — | Server mode has a 1-minute limit and throttles. On-device "won't be as accurate" [Doc]. |
| WhisperKit (Argmax, MIT) | see repo | Partial | ~99 | Whisper Small 35× / Base 111× (M4, Argmax) | In process, CoreML/ANE, so it needs the iOS 27 inference entitlement in the background. |
| **FluidAudio** (Parakeet TDT v2/v3 CoreML, Apache-2.0; models CC-BY-4.0) | Redux model iOS 18+; others see repo | Sliding-window streaming | v3: 25 European langs + ja | ~190× on M4 Pro ([repo](https://github.com/FluidInference/FluidAudio)). Parakeet v2 359× vs SpeechTranscriber 70× (Argmax Pro, M4). iPhone 16 Pro Max encoder warm 162 ms, cold compile 3.4 s (see `oss-alternatives.md`) | In process on the ANE. KeyVox had to add the inference entitlement for iOS 27. |
| sherpa-onnx (Apache-2.0) | iOS Swift examples | Yes (streaming zipformer) | Many | — | CPU ONNX, so no ANE entitlement issue. |
| whisper.cpp + CoreML encoder | — | Chunked | ~99 | — | CPU plus ANE encoder. KeyVox uses it and needed the entitlement. |

## 7. On-device LLM, and memory and compute limits

**Apple Foundation Models** ([framework](https://developer.apple.com/documentation/foundationmodels), [`SystemLanguageModel`](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)) [Doc unless marked]:
- About 3B parameters, 2-bit QAT ([tech report 2025](https://machinelearning.apple.com/research/apple-foundation-models-tech-report-2025)). Model versions track the OS: 26.0–26.3, 26.4, 27.0. **Re-test prompts on each OS.**
- Needs **Apple Intelligence-capable devices** and region. `availability` returns `.unavailable(.deviceNotEligible)` etc.
- Context: "the system model supports up to **4,096 tokens**". This counts instructions + prompt + output. Overflow throws `exceededContextWindowSize`.
- Guided generation with `@Generable` / `@Guide` gives typed output. `prewarm(promptPrefix:)` is available.
- **Background:** `GenerationError.rateLimited`: "only happen if your app is running in the background and exceeds the system defined rate limit".
- Speed: 0.6 ms per prompt token time-to-first-token, 30 tok/s on iPhone 15 Pro (Apple 2024). About 85 tok/s decode with a 27 MB in-process footprint on iPhone 17 Pro ([apple-silicon-llm-bench](https://github.com/john-rocky/apple-silicon-llm-bench), 2026) [Reported]. **It runs out of process**, so it barely touches our memory.
- iOS 27 additions: `PrivateCloudComputeLanguageModel` (free for Small Business Program apps), custom models via **Core AI** (`.aimodel`, a `LanguageModel` protocol, iOS 27) ([doc](https://developer.apple.com/documentation/foundationmodels/running-a-core-ai-model-in-a-foundation-models-session)). There is also a Shortcuts "Use Model" action.

**Bring-your-own models:** MLX Swift, llama.cpp xcframework, ExecuTorch, LiteRT-LM, MLC-LLM, Cactus, Core AI (iOS 27, successor path to Core ML for generative models — Apple ships export recipes for Qwen3 0.6B/1.7B/4B/8B at [github.com/apple/coreai-models](https://github.com/apple/coreai-models), same `LanguageModelSession` API, iOS KV cache capped at 1,024 tokens). iPhone 17 Pro, Qwen3-0.6B decode (dated, same-harness numbers): Core AI GPU 193.3 tok/s cold (2026-06-18), Core AI ANE 116.9–122.4 tok/s warm (2026-07-13), MLX 178.8 tok/s warm (2026-08-26, up from ~159 after early-2026 Qwen/Gemma kernel updates), LiteRT-LM 122.1 tok/s warm (2026-08-26), Core ML/ANE 37.7 tok/s cold (2026-06-17). Gemma-4-E2B: llama.cpp Q4_K_M 39 tok/s CPU (191 MB RSS, but hides ~2.9 GB mmap'd GGUF); LiteRT-LM wins decode+memory+energy on this model (2.2–9.5× less memory than any other loadable runtime) ([bench](https://github.com/john-rocky/apple-silicon-llm-bench), 2026) [Reported]. Full writeup, per-runtime background eligibility, and energy figures: `ios-llm-runtime.md`.

**Background compute rules (critical):**
- **GPU:** "iOS and tvOS restrict a background app's access to the GPU". New Metal command buffers fail with `notPermitted` ([doc](https://developer.apple.com/documentation/metal/preparing-your-metal-app-to-run-in-the-background)) [Doc]. MLX and llama.cpp Metal **cannot run while wippr is in the background**. The exception is `BGContinuedProcessingTask` + `continued-processing.gpu` (iOS 26, foreground-started, supported devices only) ([doc](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados)) — **but "supported devices" turns out to mean iPads with M3 or better only. DTS confirms no iPhone supports background GPU access at all**, entitlement or not ([forum 801229](https://developer.apple.com/forums/thread/801229), 2025-09; corroborated [forum 816774](https://developer.apple.com/forums/thread/816774)) [Doc/Reported]. There is no exception for an app with an active audio-recording session — real crashes (`Insufficient Permission (to submit GPU work from background)`) happen regardless of why the app is backgrounded ([llama.cpp #16998](https://github.com/ggml-org/llama.cpp/issues/16998); [mlx-swift-examples #230](https://github.com/ml-explore/mlx-swift-examples/issues/230)). See `ios-llm-runtime.md` §1/§3 for the full writeup.
- **Neural Engine (iOS 27):** "The system now restricts background access to the Neural Engine … Access to the Neural engine when your app is in the background requires the new entitlement `com.apple.developer.background-tasks.continued-processing.inference`." This applies to Core AI, Core ML and MPSGraph, **and to any background ANE use, not only inside a `BGContinuedProcessingTask`** — Apple's own doc text: "The system also requires the entitlement for any Neural Engine access while your app is in the background, regardless of whether it's running a continued background task" ([entitlement doc](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.background-tasks.continued-processing.inference), [release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes)) [Doc]. KeyVox added it in v1.2.15 (2026-07-15) to restore background Parakeet/Whisper after temporarily routing them CPU-only to dodge "an iOS 27 beta ANE failure." **It is self-enabled**: KeyVox's shipped `.entitlements` file declares it as an ordinary `<true/>` key alongside iCloud/App Group entitlements, and no Apple approval workflow for it is documented or evidenced anywhere (unlike genuinely restricted entitlements) — resolved from [Unverified] in the previous version of this note; see `ios-llm-runtime.md` §2 for the full KeyVox changelog/entitlements evidence. ANE memory now counts against the app's own footprint.
- **CPU** stays allowed while the audio session keeps the app alive. This is the only backend with zero background risk on iPhone.

**Memory limits:**
- App: the default limit varies by device. The `com.apple.developer.kernel.increased-memory-limit` entitlement raises it on some devices. Check `os_proc_available_memory()` ([doc](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit)) [Doc]. Background apps get jetsammed first [general].
- **Extensions:** "every extension point defines its own memory limit and that memory limit overrides" the increased-memory entitlement. It is hard-coded per extension type (Kevin Elliott, DTS, [thread 779756](https://developer.apple.com/forums/thread/779756)) [Doc].
- Reported numbers: **widget extension ~30 MB** ([733347](https://developer.apple.com/forums/thread/733347)); **keyboard ~48–60 MB**; a preview extension 100 MB (779756). **None of these is Apple-documented.**
- Live Activity button intents run in the **app** process [Doc]. So the widget's 30 MB cap only limits the island UI, not the ASR or LLM work.

---

## Recommended architecture for wippr

**Minimum iOS 26, targeting iOS 27.** iOS 26 brings `supportedModes = .background`, `SpeechAnalyzer`/`SpeechTranscriber` and Foundation Models. iOS 27 brings "Paste from <App>" and the ANE rule.

**Trigger path**
1. One intent, `StartStopDictationIntent: AudioRecordingIntent, LiveActivityIntent`, with `supportedModes = .background`, `authenticationPolicy = .alwaysAllowed`. It is exposed through:
   - an **expanded Dynamic Island / Lock Screen button** on a persistent "ready" Live Activity (long-press the island → tap mic);
   - a `ControlWidgetButton` (Control Center, Lock Screen, Action Button);
   - an App Shortcut ("Hey Siri, dictate with wippr"), which replaces a custom wake word.
2. In `perform()`: start or update the Live Activity **first**, then start `AVAudioEngine` (`.playAndRecord`). Info.plist: `UIBackgroundModes=audio`, `NSSupportsLiveActivities=YES`.
3. **Fallback if the background mic start fails on device:** an "Armed session" mode. The user taps Arm in the app once, the mic engine keeps running (orange dot) with an idle timeout, and island buttons only mark utterances. Documented-safe per Quinn. Costs battery and blocks Siri.
4. Keep the "ready" Live Activity alive: recreate it on each foreground or intent run (8 h cap). Push-to-start would need a server, so skip it.

**Recording + processing path (inside the app process, in the background)**
- ASR: `SpeechAnalyzer` + `SpeechTranscriber` (fallback `DictationTranscriber`), streaming, with the volatile preview in the expanded island (≤ 4 KB).
- Cleanup: Foundation Models `LanguageModelSession` with `@Generable` output, short prompts well under 4k tokens, prewarmed. Handle `rateLimited` and `deviceNotEligible` by falling back to rule-based cleanup. No GPU LLM in the background.
- If we later ship Parakeet or a custom LLM in process: add the iOS 27 inference entitlement, use CPU/ANE only, never Metal in the background.

**Text-delivery path**
1. **Default (no keyboard):** on Stop, write the cleaned text to `UIPasteboard.general`. The user taps the field and then **"Paste from wippr"** in the iOS 27 suggestion bar, or uses long-press → Paste. Show a haptic plus an island "Copied" state.
2. **Optional thin wippr keyboard** (compact strip, no mic, no app launching): it reads the latest result from the App Group and auto-inserts it via `textDocumentProxy.insertText`. This is for users who accept switching keyboards.
3. Do not attempt: host-app return tricks, private SPI, accessibility injection.

**Risks to verify on a real device (in order)**
1. Island button → `AudioRecordingIntent + LiveActivityIntent` → mic starts with the app suspended, and with the app killed. Test iOS 26.x and 27.x, unlocked and locked.
2. `Activity.request` inside that intent from the background: no "Target is not foreground".
3. `UIPasteboard` write from the background succeeds. The iOS 27 "Paste from wippr" chip appears, and pasting shows no prompt.
4. `SpeechTranscriber` + Foundation Models keep working while backgrounded on iOS 27 (ANE rule, `rateLimited`), and latency from end-of-speech to clipboard.
5. Recovery after a phone call or Siri interruption (`'!int'`) without reopening the app.
6. Memory and jetsam of the app in the background, with ASR + LLM loaded next to other apps.
7. App Review: `audio` background mode used for recording, the always-present Live Activity, and keyboard 4.4.1.
