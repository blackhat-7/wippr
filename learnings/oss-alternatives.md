# Open-source Wispr Flow alternatives for phones

**TL;DR (2026-09-26)**
- **iOS has no community-consensus OSS winner.** Reddit's iPhone picks are closed apps (Spokenly, Willow, Typeless, Aardvark, Wispr Flow). OSS iOS apps are young and have little social proof.
- **Closest to wippr: [KeyVox](https://github.com/macmixing/keyvox) (MIT source).** On-device Parakeet/Whisper, then a Qwen2.5-0.5B + LoRA cleanup through llama.cpp. It records in the background from the Action Button, Control Center or Shortcuts via `AudioRecordingIntent` + `LiveActivityIntent`, so the app never comes to the foreground. It delivers text through its keyboard or the clipboard.
- **Android has clear consensus:** FUTO Voice Input/Keyboard is the default pick, but its license is source-first and non-commercial. WhisperIME is the FOSS pick. Parakeet-based "Offline Voice Input" (notune) is the rising pick because it is faster.
- **Nobody gets text into another app without a keyboard extension or the clipboard.** Every iOS project uses one of those. The mic never lives in the keyboard: the containing app records, backed by a Live Activity.
- **Open conflict for `ios-platform-constraints.md`:** hex-iphone says a Live Activity can only start from the foreground (`Target is not foreground`), so the app flashes open. KeyVox says its intent runs with `openAppWhenRun = false` and `supportedModes = .background` (iOS 26+). The difference is probably the iOS version plus the `LiveActivityIntent` conformance (unverified).

Method: GitHub stats via `gh api` on 2026-09-26. Reddit via the pullpush.io archive (the bestiary reddit MCP had no session, and reddit.com blocks direct fetch). HN via the Algolia MCP. X only through web-search snippets: x.com returns HTTP 402 to fetch, so X quotes are short snippets and there are few of them.

---

## Ranked picks

### iOS (OSS only)
1. **KeyVox**: [macmixing/keyvox](https://github.com/macmixing/keyvox). The only OSS iOS app with the full wippr pipeline: on-device ASR, on-device LLM cleanup, and a background start without the keyboard. Low social proof: 47★, and the only Reddit mention is the dev's own post.
2. **OpenWhispr mobile**: [OpenWhispr/openwhispr](https://github.com/OpenWhispr/openwhispr), `openwhispr-mobile/`. The biggest community (8.6k★ monorepo, MIT). It has an iOS keyboard extension and a Live Activity (dictation-idle, keyboard-recording and meeting states). Its PR [#2362](https://github.com/OpenWhispr/openwhispr/pull/2362), merged 2026-09-25, documents the Live Activity rules. Built with Expo/React Native and whisper.rn. On-device, cloud or BYOK ASR, plus AI cleanup (cloud/BYOK on mobile).
3. **Diction**: [DictionLabs/Diction](https://github.com/DictionLabs/Diction), 203★, MIT. A keyboard with on-device Parakeet, or a self-hosted Go gateway (Whisper/Parakeet plus optional LLM cleanup through any OpenAI-compatible endpoint, e.g. Ollama). Claims "sub-second" latency.

Design reference, not ranked (1★): **[Luraxx/hex-iphone](https://github.com/Luraxx/hex-iphone)** (MIT). It is almost exactly the wippr flow, and its small XcodeGen repo is the easiest to read. Action Button → Dynamic Island timer with Done/Discard → Parakeet (FluidAudio) → clipboard + keyboard auto-insert.

### Android
1. **FUTO Voice Input / FUTO Keyboard**: the most-recommended option across r/androidapps, r/fossdroid, r/degoogle and HN. Uses Whisper tiny/base/small fine-tuned by FUTO (ACFT). Caveats: the *FUTO Source First License* is non-commercial, so it is not OSI open source. Critics say the models are stale ("the only model they offer is whisper-small").
2. **WhisperIME / Whisper+** ([woheller69](https://github.com/woheller69/whisperIME)): the pick when people want real FOSS, usually paired with HeliBoard. Whisper runs on TFLite (Whisper+ uses ONNX). Works as an IME plus a system `RecognitionService`.
3. **Offline Voice Input** ([notune/android_transcribe_app](https://github.com/notune/android_transcribe_app), MIT): Parakeet TDT v3 through `transcribe.cpp` (ggml) in a Rust core. Users switch to it from FUTO because it is "much faster".

Also mentioned: Transcribro (GrapheneOS favourite, but stale since 2025-08 and pulled from F-Droid), Outspoke (Parakeet v3 INT8 on ONNX Runtime with streaming partials), BiBi-Keyboard (805★, LLM post-processing), Dictate (cloud Whisper + LLM prompts).

---

## Comparison table (phones)

Stars and last push are from GitHub on 2026-09-26.

| Project | Repo | License | Platform | ★ | Last push | ASR | LLM cleanup | On-device? | UX surface | Latency claim |
|---|---|---|---|---|---|---|---|---|---|---|
| KeyVox | macmixing/keyvox | MIT source; LoRA adapters + branding excluded | iOS 18.6+, macOS | 47 | 2026-09-24 | Parakeet TDT v3 (FluidAudio CoreML), Whisper | Qwen2.5-0.5B-Instruct + KeyVox LoRA via llama.cpp xcframework ("Vibes", ~491 MB) | Yes | Keyboard ext; Action Button / Control Center / Shortcut background toggle; Live Activity; clipboard + notification | none |
| OpenWhispr mobile | OpenWhispr/openwhispr | MIT | iOS (Android untested in CI) | 8613 (monorepo) | 2026-09-26 | whisper.rn on-device, hosted, or BYOK | Yes (hosted/BYOK) | Optional | Keyboard ext; Live Activity + Dynamic Island | none |
| Diction | DictionLabs/Diction | MIT | iOS 17+ | 203 | 2026-09-22 | Parakeet on-device; Whisper/Parakeet on self-host | Optional, OpenAI-compatible (e.g. gemma2:9b on Ollama) | Optional | Keyboard ext (app records) | "sub-second" Parakeet; "<2 s" Whisper turbo |
| hex-iphone | Luraxx/hex-iphone | MIT | iOS 18+, iPhone 15 Pro+ | 1 | 2026-07-16 | Parakeet TDT v2/v3 (FluidAudio) | No | Yes | Action Button → Live Activity/Dynamic Island Done/Discard → clipboard + keyboard auto-insert | none |
| Muesli iOS | Muesli-HQ/muesli-ios | MIT | iOS 17+ | 26 | 2026-09-19 | Parakeet (FluidAudio) | Summaries only (ChatGPT / OpenRouter) | Yes (ASR) | Keyboard → deep link to app → poll App Group; Live Activity | none |
| Dictus iOS | getdictus/dictus-ios | MIT | iOS 17+ | 36 | 2026-09-24 | WhisperKit tiny/base/small, optional Parakeet | Roadmap only | Yes | Keyboard ext + "audio bridge" to app | none |
| VocaPhone | VocaHQ/vocaphone | AGPL-3.0 | iOS 17+, Android 13+ | 67 | 2026-09-25 | sherpa-onnx | Rule-based filler removal (no LLM) | Yes (+ optional self-host) | Keyboard (iOS app records); Live Activity; Android IME + foreground service | none |
| Voquill mobile | voquill/voquill `mobile/` | AGPL-3.0 (+ enterprise dir) | iOS/Android (Flutter) | 1012 (monorepo) | 2026-09-26 | Local Whisper or cloud (unverified on mobile) | Yes (BYOK) | Optional | Keyboard + Live Activity (`DictationService.swift`) | none |
| Chirp | tatarigami22/chirp | none | iOS | 0 | 2026-09-01 | Apple Speech | Optional API | Yes | Keyboard; app records in background | none |
| Swift-iOS_DictationAppWithoutKeyboard | 0Itsuki0/… | AGPL (per README) | iOS | 1 | 2026-05-28 | Apple Speech (unverified) | No | Yes | **No keyboard.** Shortcuts start/stop, then manual paste | none |
| VoiceInk iOS | Beingpax/VoiceInk-iOS | **no license** | iOS | 35 | 2025-09-23 | (unverified) | (unverified) | — | App + keyboard | — |
| Whisperboard | Saik0s/Whisperboard | GPL-3.0 | iOS | 1103 | 2025-12-18 | whisper.cpp | No | Yes | Recorder app (no system dictation) | — |
| FUTO Voice Input | futo-org/voice-input (GitLab mirror) | FUTO Source First 1.0 (non-commercial) | Android | 330 | 2026-09-25 | Whisper tiny/base/small (ACFT fine-tunes) | No | Yes | Voice IME subtype + RECOGNIZE_SPEECH floating window | none |
| FUTO Keyboard | futo-org/android-keyboard | FUTO Source First 1.1-kb | Android | 3251 | 2026-09-23 | Same as above | No | Yes | Full keyboard with built-in voice | none |
| WhisperIME | woheller69/whisperIME | MIT | Android | 641 | 2026-08-30 | Whisper (TFLite) | No | Yes | IME + RecognitionService + intent | none |
| Whisper+ | woheller69/whisperIMEplus | GPL-3.0 | Android | 418 | 2026-09-25 | Whisper (ONNX, RTranslator impl.) | No | Yes | IME + RecognitionService | "Fast" |
| Offline Voice Input | notune/android_transcribe_app | MIT | Android | 304 | 2026-07-19 | Parakeet TDT v3 via transcribe.cpp (any GGUF) | No | Yes | RecognitionService (panel over any keyboard) + IME | users: faster than FUTO |
| Transcribro | soupslurpr/Transcribro | ISC | Android | 753 | **2025-08-29** | whisper.cpp + Silero VAD | No | Yes | IME + recognition service | none |
| Outspoke | minburg/outspoke | GPL-3.0 | Android 11+ | 85 | 2026-08-29 | Parakeet TDT v3 INT8 (ONNX Runtime) + Silero VAD | No (n-gram word fixes) | Yes | IME, streaming partials | "real-time" |
| Sayboard | ElishaAz/Sayboard | GPL-3.0 | Android | 583 | 2025-07-01 | Vosk | No | Yes | IME | — |
| BiBi-Keyboard | BryceWG/BiBi-Keyboard | Apache-2.0 | Android 8+ | 805 | 2026-09-26 | sherpa-onnx (SenseVoice, Qwen3-ASR, Parakeet…) or cloud | Yes (LLM post-processing, BYOK) | Optional | IME + LSPosed bridge into other IMEs | none |
| Dictate Keyboard | DevEmperor/DictateKeyboard | Apache-2.0 | Android | 288 | 2026-09-26 | OpenAI/Groq Whisper API | Yes (prompt rewording) | No | Full keyboard | — |
| Dictus Android | getdictus/dictus-android | MIT | Android | 23 | 2026-09-01 | on-device (unverified which) | No | Yes | IME | — |

Not open source, but they set the UX bar people compare against: Spokenly, Wispr Flow, Willow, Typeless, Aardvark, Superwhisper, Whisperian (Android).

---

## Keyboard-less / Dynamic Island attempts on iOS (and what blocked them)

| Project | Trigger | Result | Blocker they hit |
|---|---|---|---|
| **KeyVox** | Shortcut / Action Button / Control Center → `ToggleKeyVoxDictationIntent: AudioRecordingIntent, LiveActivityIntent`, `openAppWhenRun = false`, `supportedModes = .background` (iOS 26) | Records with no app foregrounding. Stop returns text: clipboard + notification, or auto-insert if its keyboard is visible | Engineering doc: "Live Activity preparation must complete before background microphone startup. Disabled Live Activities or failed preparation prevent recording from starting." |
| **hex-iphone** | Action Button → `ToggleDictationIntent (AudioRecordingIntent)` | App flashes open, then recording continues in the background. Stop from the Dynamic Island. Clipboard + keyboard auto-insert | "Apps cannot start a recording purely in the background — a Live Activity is required and iOS only lets you start one from the foreground (`Target is not foreground`)". "Keyboard extensions cannot access the microphone at all". "Since iOS 18, keyboard extensions can no longer open their container app". |
| **OpenWhispr PR #2362** | Meeting recording reuses the existing dictation Live Activity | Lock-screen End button stops recording | "iOS only lets an app start a Live Activity from the foreground, but it can update one from the background". 8 h Live Activity cap. Processing resumes only after reopening the app. |
| **0Itsuki0 DictationAppWithoutKeyboard** | Two Shortcuts (start/stop) bound to AssistiveTouch | No keyboard. App opens only on first record | Final step is "Paste the dictated content (manually...)". No way to insert text. |
| **Spokenly** (closed, docs public) | Shortcut via Action Button / Back Tap / AssistiveTouch | Background dictation; insert via its keyboard ✓ or clipboard | "background dictation cannot work without [Live Activities]" (iOS 17+) |
| **Wispr Flow** (closed) | Keyboard → app bounce, then warm mic session | Mic stays open between dictations | Keyboard has no mic, so the app keeps "an active mic session" (orange dot complaints) |

Takeaways for wippr:
- A Live Activity is mandatory for background recording.
- The unresolved question is whether it can be *started* without the foreground. KeyVox says yes on iOS 26+ through a background-mode App Intent. hex-iphone says no.
- Text insertion always ends at a keyboard extension or the clipboard.
- A "warm" mic session is how Flow and Spokenly avoid re-bouncing to the app. It costs an orange-dot indicator and battery.

---

## Community quotes

### iOS
- "every single one foundered for me eventually in how shitty their keyboard was … hitting paste is a major time saver relative to what the other apps do" — u/zlingman, [r/iosapps](https://reddit.com/r/iosapps/comments/1r4tx5o/whats_the_best_wispr_flow_free_alternative_for/o5go6w8/)
- "Spokenly. You can use it entirely for free with local models and/or use your own api keys for free." — [r/iosapps](https://reddit.com/r/iosapps/comments/1r4tx5o/whats_the_best_wispr_flow_free_alternative_for/o5e99di/)
- Spokenly dev: "iOS doesn't allow keyboard extensions to access the microphone, so the app has to open briefly to start recording. … This is actually a one-time-per-session thing, not per tap." — [r/spokenly](https://reddit.com/r/spokenly/comments/1s8udbh/ui_could_please_get_rid_of_this_popup_screen/odms7sk/)
- Wispr Flow reply on the mic indicator: "Flow keeps the mic session open rather than tearing it down each time … so your next dictation starts instantly" — [r/WisprFlow](https://reddit.com/r/WisprFlow/comments/1uo2irk/spying_on_microphone/owszaj2/)
- "The iOS apps are garbage because iOS forces you to switch the screen to use voice dictation … the implementations in Android are actually very good now." — [r/macapps](https://reddit.com/r/macapps/comments/1ucezv2/os_fluidvoice_is_back_with_a_bang_free_local_ai/p4d24ow/)
- On a keyboard-based flow: "The Keyboard Switching Bottleneck - Having to manually switch keyboards every time you want to use voice dictation creates a workflow bottleneck." — [r/foss](https://reddit.com/r/foss/comments/1ts6uvx/whisperflow_alternative_for_free_and_privacy/oow7stt/)
- X (translated from Chinese): Wispr Flow's iOS keyboard dictation "keeps the app running in the background recording the mic … iOS keyboard extensions don't get mic permission, so this is really the only solution, but it's a bit too much of a workaround" — [@tualatrix](https://x.com/tualatrix/status/1951855378653950358)
- KeyVox dev's self-post: "open source and truly free dictation app for iOS and macOS … powered by Whisper and Parakeet" — [r/codex](https://reddit.com/r/codex/comments/1vyerip/show_rcodex_what_youve_been_building_with_codex/p5wgto1/) (self-promotion, not independent)

### Android
- "FUTO Voice is the best I've been able to find, it handles punctuation properly" (+10) — [r/fossdroid](https://reddit.com/r/fossdroid/comments/1tkt5ic/looking_for_a_proper_offlineopen_source_android/onc4ghy/)
- "You are not going to get even close to the same experience at all from an offline solution." (+38, top comment) — [r/fossdroid](https://reddit.com/r/fossdroid/comments/1tkt5ic/looking_for_a_proper_offlineopen_source_android/onawwdv/)
- "I used Futo for about two years and switched over to [Offline Voice Input, Parakeet V3] recently because it's faster. Much fas[ter]" — [r/androidapps](https://reddit.com/r/androidapps/comments/1thr5ui/day_2_voice_note_apps_still_feel_clunky_on/onq5gm8/)
- "While most Reddit posts will tell you to use the FUTO app, I would recommend this FOSS project: whisperIME" — [r/fossdroid](https://reddit.com/r/fossdroid/comments/1rrws91/why_is_everyone_recommending_futo_and_why_is/oab58hl/)
- "the voice input on FUTO was really great … Whisper+ on Heliboard is pretty good though … just not quite as good as FUTOs option." — [r/degoogle](https://reddit.com/r/degoogle/comments/1urm408/keyboard_alternative_to_futo/owhrdh8/)
- "Transcribro is good, although there's some issues on android 17 that have yet to be patched" — [r/degoogle](https://reddit.com/r/degoogle/comments/1umra7v/what_are_the_best_nongoogle_voicetotext_options/ovef5j8/)
- "the only model they offer is whisper-small, a very basic model from 2022." — fph on [HN](https://news.ycombinator.com/item?id=49601369)
- "Maybe there should be something that use like gemma 4 e2b for speech to text + post cleanups" — [r/fossdroid](https://reddit.com/r/fossdroid/comments/1tkt5ic/looking_for_a_proper_offlineopen_source_android/onn90mf/). Users want the LLM cleanup step that no FOSS Android app runs on-device.

### Desktop (for context)
- "Handy is the one that made me stop looking for local open source alternatives to Wispr Flow." — [HN](https://news.ycombinator.com/item?id=47668925)
- Grok's tally of 66 replies to @marckohlbrugge: "1. MacWhisper (10 mentions) … 2. Handy (8 mentions) - Free, open-source with Parakeet. 3. Superwhisper (7…" — [X](https://x.com/grok/status/2022170404324847832) (snippet only)
- Whispering Show HN: 591 points, 152 comments — [HN](https://news.ycombinator.com/item?id=44942731)

---

## Desktop-only tools (pipeline ideas only)

| Tool | ★ (2026-09-26) | License | Pipeline idea worth copying |
|---|---|---|---|
| [Handy](https://github.com/cjpais/Handy) | 32,232 | MIT | Silero VAD, then Parakeet V3 / Whisper, then optional post-process toggle. Its GGUF runtime [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp) (MIT, 1,961★) is reusable on Android. |
| [FluidVoice](https://github.com/altic-dev/FluidVoice) | 11,771 | GPL-3.0 | "custom trained AI enhancement model" for cleanup. Swaps between Parakeet, Cohere, Apple Speech and Whisper. |
| [OpenWhispr](https://github.com/OpenWhispr/openwhispr) | 8,613 | MIT | llama.cpp local cleanup LLM + cloud BYOK |
| [VoiceInk](https://github.com/Beingpax/VoiceInk) | 6,572 | GPL-3.0 | Parakeet via FluidAudio; per-app "power modes" |
| [Whispering/Epicenter](https://github.com/EpicenterHQ/epicenter) | 4,803 | MIT per Show HN post; GitHub shows NOASSERTION | Voice-activated mode; prompt-based "transformations" |
| [Hex](https://github.com/kitlangton/Hex) | 2,899 | MIT | Parakeet via FluidAudio, hold-to-talk; Rust rewrite at anomalyco/hex |
| [FreeFlow](https://github.com/zachlatta/freeflow) | 2,743 | MIT | — |
| [Amical](https://github.com/amicalhq/amical) | 1,537 | MIT | Context-aware formatting with local LLM; Android app + iOS beta (source not seen in repo) |

---

## Reusable pieces for wippr

| Piece | License | Use | Notes |
|---|---|---|---|
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | Apache-2.0 (models CC-BY-4.0 for Parakeet) | Parakeet TDT v3 / streaming EOU ASR + Silero VAD on the ANE | Used by KeyVox, hex-iphone, Muesli, VoiceInk and Hex. Its benchmarks on iPhone 16 Pro Max: encoder cold compile 3361 ms, warm 162 ms. So keep the model warm. |
| [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) | MIT | Whisper on CoreML | Used by Dictus |
| [llama.cpp](https://github.com/ggml-org/llama.cpp) xcframework | MIT | On-device cleanup LLM | KeyVox ships `llama.xcframework` for iOS arm64 |
| Qwen2.5-0.5B-Instruct | Apache-2.0 | Cleanup LLM baseline | KeyVox's choice (~491 MB with adapters). Candidate for `bench-cleanup-llm.md`. |
| KeyVox `ToggleKeyVoxDictationIntent.swift`, `KeyVoxSessionLiveActivityCoordinator`, `iOS/Docs/ENGINEERING.md` | MIT (not adapters/branding) | Reference for background intent + Live Activity + warm session + keyboard IPC | The best single reference for wippr's Phase 3 |
| [hex-iphone](https://github.com/Luraxx/hex-iphone) `project.yml`, `ToggleDictationIntent`, `HexKeyboard` (Darwin notify + App Group) | MIT | XcodeGen skeleton: app + widget + keyboard | Small and readable; UI strings are German |
| [Muesli iOS](https://github.com/Muesli-HQ/muesli-ios) | MIT | Keyboard → app handoff via App Group | — |
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp) | MIT | Fallback ASR | 53,940★ |
| [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) | Apache-2.0 | Cross-platform ASR/VAD (iOS + Android) | Used by VocaPhone, BiBi-Keyboard, WhisperTypeKeyboard |
| [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp) | MIT | ggml Parakeet/Whisper/Canary on Android | Used by notune Offline Voice Input |

Read for ideas, but do not copy code: VocaPhone, Voquill and 0Itsuki0 (AGPL); VoiceInk, FluidVoice, Whisper+ and Whisperboard (GPL); FUTO (non-commercial source-first); VoiceInk-iOS and Chirp (no license).
