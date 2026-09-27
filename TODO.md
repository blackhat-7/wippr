# wippr TODO

Shared tracker for the main session and subagents. Mark `[x]` when done, `[~]` when in progress (add your agent name). Add new tasks where they belong. Put findings in `learnings/`, not here.

## Goal

Wispr-Flow-style dictation on iPhone **without a keyboard taking up the screen**. Start from the Dynamic Island / Live Activity. Speak, get clean text, get it into whatever app you're in. Fallback trigger: wake word.

## Phase 1 — Research

- [x] What Wispr Flow does and how its iOS app works → `learnings/wispr-flow-product.md`
- [x] Open-source Wispr Flow alternatives for phones, ranked by X + Reddit sentiment → `learnings/oss-alternatives.md`
- [x] iOS feasibility: Live Activity mic start, text insertion into other apps, wake word → `learnings/ios-platform-constraints.md`

## Phase 2 — Benchmarks (on 7900 XTX)

- [~] ASR candidates: accuracy (WER) + speed → `learnings/bench-asr.md` (asr-bench agent: CPU runs in progress, GPU blocked by another project holding VRAM)
- [~] Cleanup LLM candidates: quality + speed → `learnings/bench-cleanup-llm.md` (partial; paused for another session's GPU bench — resume `cd bench/llm && uv run bench.py all`)
- [ ] Pick the phone stack (ASR + LLM) and write the decision → `learnings/decision-stack.md`

## Phase 3 — Build (iOS)

- [x] Architecture doc → `learnings/architecture.md`
- [x] Xcode project spec (XcodeGen) for app + widget extension → `ios/project.yml`
- [x] Live Activity / Dynamic Island UI with mic control → `ios/Widgets/`
- [x] Recording from the island (AudioRecordingIntent + LiveActivityIntent) → `ios/Shared/ToggleDictationIntent.swift`
- [x] On-device ASR (Apple SpeechTranscriber) → `ios/App/Transcriber.swift`
- [x] On-device cleanup LLM (Apple Foundation Models) → `ios/App/Cleaner.swift`
- [x] Update cleanup prompt from `bench-cleanup-llm.md` results (v2 tagged prompt ported to Cleaner.swift)
- [ ] A/B Apple Foundation Models vs the bench winner on device with `bench/llm/cases.jsonl`
- [x] Deliver text: clipboard + iOS 27 "Paste from wippr"; retry on app open if the background write is refused
- [x] Wake word → not needed: Siri App Shortcut "Dictate with wippr" (see `ios-platform-constraints.md` §4)
- [x] Verify every Apple API against docs (can't compile on Linux) → `learnings/ios-api-verification.md` (no fixes needed; all files pass `swiftc -parse`; unverified items listed there)

## Phase 4 — Verify

- [ ] Build on a Mac with Xcode (`cd ios && xcodegen`), fix compile errors
- [ ] Island button starts the mic with the app suspended / killed / phone locked (iOS 26 and 27)
- [ ] No "Target is not foreground" when the island was dismissed and the Control/Siri path must start a new Live Activity
- [ ] Clipboard write from the background succeeds; "Paste from wippr" chip appears; no paste prompt
- [ ] SpeechTranscriber + Foundation Models work in the background on iOS 27 (ANE rule, `rateLimited`) — if SpeechTranscriber fails backgrounded, try the `continued-processing.inference` entitlement (docs scope it to Core AI/Core ML/MPSGraph; see `ios-api-verification.md`)
- [ ] Latency: stop tap → text on clipboard (target < 1.5 s for a 15 s dictation)
- [ ] Recovery after a phone call / Siri interruption
- [ ] Battery and memory over a day with the ready island
