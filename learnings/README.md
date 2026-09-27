# Learnings

Shared memory for every agent and session working on wippr. Read this folder before starting work.

## Rules

- One topic per file, kebab-case: `wispr-flow-product.md`, `bench-asr.md`.
- Start each file with a 3–6 line **TL;DR**. Details after.
- Cite sources (URL, subreddit/thread, X post, repo). Mark anything unverified as `(unverified)`.
- Put dates on facts that go stale (versions, prices, star counts). Today = 2026-09-26.
- Update an existing file instead of making a near-duplicate.
- Benchmarks: record hardware, model + quant, exact command, and raw numbers. Scripts live in `../bench/`.

## Machine (benchmark host)

- CPU: Intel i5-13600K (20 threads), 94 GB RAM
- GPU: AMD Radeon RX 7900 XTX, 24 GB, gfx1100, ROCm 7.2.4 (no CUDA)
- llama.cpp HIP build: `~/Documents/projects/llamacpp-tuner/tmp/llama.cpp/build-hip/bin/`
- Python via `uv`. System python is 3.14; use `uv` with 3.12 for ML deps.

## Index

<!-- Add a line per file: - [file.md](file.md) — one-line summary -->
- [wispr-flow-product.md](wispr-flow-product.md) — Wispr Flow features, iOS internals (keyboard + main-app mic session, Live Activity, Action Button/intents, clipboard fallback), cloud stack, pricing, privacy, Reddit/X sentiment, implications for wippr
- [wispr-onboarding-android.md](wispr-onboarding-android.md) — how Wispr Flow Android onboards: step order, try-it-first reps, real PiP Settings guide video, auto-return polling; what maps to iOS (AVPictureInPictureController, app Settings page has Keyboards + Full Access)
- [oss-alternatives.md](oss-alternatives.md) — ranked OSS phone dictation apps (iOS: KeyVox, OpenWhispr mobile, Diction; Android: FUTO, WhisperIME, notune Parakeet), keyboard-less iOS attempts + blockers, reusable libs with licenses
- [ios-platform-constraints.md](ios-platform-constraints.md) — what iOS allows (Apple-doc-cited): island buttons + AudioRecordingIntent/LiveActivityIntent background mic start, 8 h Live Activity, text delivery (clipboard + iOS 27 "Paste from" chip vs keyboard), wake word, triggers, ASR/LLM options, iOS 27 background ANE/GPU rules, memory caps, recommended architecture
- [architecture.md](architecture.md) — wippr v0.1 design: one toggle intent for all triggers, persistent ready island, Apple SpeechTranscriber + Foundation Models, clipboard delivery, no keyboard, Siri instead of wake word
- [ios-api-verification.md](ios-api-verification.md) — every Apple API in `ios/` checked against DocC JSON + WWDC25 SpeechAnalyzer sample: signatures/availability table, no SFSpeechRecognizer auth needed, auto locale reservation, LiveActivityIntent runs in app process, no code edits needed, what still needs a Mac
- [bench-cleanup-llm.md](bench-cleanup-llm.md) — 23 runs / 21 small LLMs (≤4B) on 66 dictation cases, Claude-judged: pick S1-mini Q4_K_M (0.48 GB, 0.8 s/60 words on 4 CPU threads), runner-up Qwen3.5-4B Q4_K_M (best quality, too slow on phone), vs Apple FM default; v2 prompt, thinking ruled out, output guard rejected, community prior art
- [rocm-setup.md](rocm-setup.md) — llama.cpp HIP build, sherpa-onnx/whisper-normalizer deps, GPU sharing with other projects
- [bench-asr.md](bench-asr.md) — PARTIAL (CPU only): bundled ASR (Parakeet v2/v3/110m, Whisper small.en, Moonshine) vs Apple SpeechTranscriber: WER on LibriSpeech/AMI/earnings22, 4-thread RTF/latency, published SpeechTranscriber numbers, verdict (keep SpeechTranscriber; Parakeet v2 is the bundle pick if ever needed)
- [decision-stack.md](decision-stack.md) — phone stack: Apple SpeechTranscriber + Foundation Models ship; Parakeet TDT 0.6B v2 and S1-mini are the bundled fallbacks; when to switch; what's ruled out
- [device-testing.md](device-testing.md) — Phase 4 on-device results (iPhone 18 Pro Max, iOS 27.0): build/signing notes, per-trigger results, latency
