# wippr TODO

Shared tracker for the main session and subagents. Mark `[x]` when done, `[~]` when in progress (add your agent name). Add new tasks where they belong. Put findings in `learnings/`, not here.

## Goal

Wispr-Flow-style dictation on iPhone **without a keyboard taking up the screen**. Start from the Dynamic Island / Live Activity. Speak, get clean text, get it into whatever app you're in. Fallback trigger: wake word.

## Phase 1 — Research

- [x] What Wispr Flow does and how its iOS app works → `learnings/wispr-flow-product.md`
- [x] Open-source Wispr Flow alternatives for phones, ranked by X + Reddit sentiment → `learnings/oss-alternatives.md`
- [x] iOS feasibility: Live Activity mic start, text insertion into other apps, wake word → `learnings/ios-platform-constraints.md`

## Phase 2 — Benchmarks (on 7900 XTX)

- [x] ASR candidates: accuracy (WER) + speed → `learnings/bench-asr.md` (GPU all 9 models; CPU phone proxy for 5)
- [x] Cleanup LLM candidates: quality + speed → `learnings/bench-cleanup-llm.md` (S1-mini Q4_K_M pick, Qwen3.5-4B runner-up)
- [ ] Cleanup bench: CPU-4t (phone proxy) speed for the remaining runs was skipped — run `cd bench/llm && uv run bench.py speed-cpu` if on-phone estimates need firming up
- [x] Pick the phone stack (ASR + LLM) and write the decision → `learnings/decision-stack.md` (from partial results; recheck when benches finish)

## Phase 3 — Build (iOS)

- [x] Architecture doc → `learnings/architecture.md`
- [x] Xcode project spec (XcodeGen) for app + widget extension → `ios/project.yml`
- [x] Live Activity / Dynamic Island UI with mic control → `ios/Widgets/`
- [x] Recording from the island (AudioRecordingIntent + LiveActivityIntent) → `ios/Shared/ToggleDictationIntent.swift`
- [x] On-device ASR (Apple SpeechTranscriber) → `ios/App/Transcriber.swift`
- [x] On-device cleanup LLM (Apple Foundation Models) → `ios/App/Cleaner.swift`
- [x] Update cleanup prompt from `bench-cleanup-llm.md` results (v2 tagged prompt ported to Cleaner.swift)
- [ ] A/B Apple Foundation Models vs S1-mini on device: Home → Experimental → Cleanup model (testing only; AFM stays the default and the shipping path)
- [-] S1-mini via llama.cpp CPU-only — dropped 2026-09-28 for the Neural Engine path below
- [x] Experimental: S1-mini on the Neural Engine via Core AI, iOS 27 (`ios/NeuralCleaner/`, loaded at runtime by `ios/App/NeuralEngine.swift`); model exported with `coreai.llm.export --platform iOS`, copied into the app container by hand
- [x] Pre-pass: list rules only (`ios/App/Prepass.swift`); the full spoken-punctuation pass didn't help end-to-end (`learnings/bench-e2e.md`)
- [x] End-to-end bench: TTS → Parakeet → cleanup → judge (`bench/e2e`, `learnings/bench-e2e.md`)
- [x] S1-mini on the Neural Engine: 8-bit export scores 4.20 on device (mixed 4/8-bit broke it: 3.21); see `learnings/bench-e2e.md`, on-device section
- [ ] S1-mini in the background: needs `com.apple.developer.background-tasks.continued-processing.inference` on the App ID (signing refused it for team CRH6P5D9K2)
- [ ] S1-mini: ship or download the model (today it's copied into the container by hand)
- [ ] CI: Xcode 26.6 can't build the iOS 27 NeuralCleaner target
- [ ] Record real dictation of `cases.jsonl` (a few voices) and rerun `bench/e2e` on it — TTS audio is too clean
- [ ] ASR: pass contact names / custom vocabulary to SpeechTranscriber (`AnalysisContext` contextual strings) — ASR word errors are now the biggest loss
- [x] Deliver text: clipboard + iOS 27 "Paste from wippr"; retry on app open if the background write is refused
- [x] Wake word → not needed: Siri App Shortcut "Dictate with wippr" (see `ios-platform-constraints.md` §4)
- [x] Verify every Apple API against docs (can't compile on Linux) → `learnings/ios-api-verification.md` (no fixes needed; all files pass `swiftc -parse`; unverified items listed there)

## Phase 4 — Verify

- [x] Compile check in CI (GitHub Actions `macos-26`, Xcode 26.6, `.github/workflows/ios-build.yml`) — app + widget build clean for the simulator, no code warnings (2026-09-27). Xcode 27 SDK not yet tested.
- [x] Build on a Mac with Xcode (`cd ios && xcodegen`), sign, run on device (iPhone 18 Pro Max, iOS 27.0, Xcode 27 SDK — `learnings/device-testing.md`)
- [ ] Keyboard: "switch to typing keyboard" key right of delete (tap = next keyboard, hold = list) — test on device
- [x] Keyboard mic button → app (mic kept on in the background) → text typed into the focused field (2026-09-27 redesign; hold-to-talk works on device)
- [ ] Edit mode (slide up while holding): rewrite selection / text before cursor, generate into empty field, terminal commands, undo — test on device
- [ ] Background mic survives app switching, screen lock, a phone call; restarts after interruption
- [-] Always-on "wipper" wake word: detection, end-of-speech, survives background / lock / calls, battery — dropped 2026-09-27: keyboard-driven design, no Live Activity / wake word
- [-] Island button starts the mic with the app suspended / killed / phone locked (iOS 26 and 27) — dropped 2026-09-27: keyboard-driven design, no Live Activity / wake word
- [-] No "Target is not foreground" when the island was dismissed and the Control/Siri path must start a new Live Activity — dropped 2026-09-27: keyboard-driven design, no Live Activity / wake word
- [ ] Clipboard write from the background succeeds; "Paste from wippr" chip appears; no paste prompt
- [ ] SpeechTranscriber + Foundation Models work in the background on iOS 27 (ANE rule, `rateLimited`) — if SpeechTranscriber fails backgrounded, try the `continued-processing.inference` entitlement (docs scope it to Core AI/Core ML/MPSGraph; see `ios-api-verification.md`)
- [ ] Latency: stop tap → text on clipboard (target < 1.5 s for a 15 s dictation)
- [ ] Recovery after a phone call / Siri interruption
- [ ] Battery and memory over a day with the ready island
