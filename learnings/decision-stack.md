# Phone stack decision

> **Changed 2026-09-28:** cleanup now ships **S1-mini Q4_K_M via llama.cpp, CPU-only** (`ios/App/LocalCleaner.swift`), with the list rules before it (`ios/App/Prepass.swift`). Apple Foundation Models is only the fallback while the 484 MB model downloads, and it still does edit mode. Why: the user doubted AFM's quality, and it can't be benchmarked. S1-mini scored best of the phone-sized models end-to-end (4.18, `bench-e2e.md`). CPU is the only backend that is always allowed in the background (`ios-llm-runtime.md`). ASR is unchanged (SpeechTranscriber).

**Decision (2026-09-27, confirmed by the finished benchmarks)**

| Stage | Ships in v0.1 | Bundled fallback, if device tests demand one |
|---|---|---|
| ASR | Apple `SpeechTranscriber` (system, out of process, 0 MB) | **Parakeet TDT 0.6B v2** via FluidAudio (CoreML/ANE, ~0.6 GB) |
| Cleanup | Apple Foundation Models (system, ~3B, out of process, 0 MB) | **S1-mini Q4_K_M** (Qwen3-0.6B cleanup fine-tune, 484 MB) via llama.cpp on CPU |

## Why Apple first

- **No download and no app size.** The OS manages memory and model updates.
- **Runs out of process.** It avoids the GPU ban for background apps and, most likely, the iOS 27 background Neural Engine entitlement. See `ios-platform-constraints.md` §7.
- **Accuracy is close enough.** Published numbers put SpeechTranscriber at 2.1 / 4.6% WER on LibriSpeech clean/other and 14.0% on earnings22. Parakeet v2 measured 1.1 / 2.9 / 10.9% here (`bench-asr.md`). About 2 points on hard audio doesn't justify ~0.6 GB, a 3.4 s cold load and the extra entitlement for v0.1.

## When to switch to the fallback

- **ASR → Parakeet v2:** SpeechTranscriber fails in the background on iOS 27, or users hit accuracy problems on names or technical words.
  - Parakeet v3 only if non-English languages are needed; it is ~1.7 points worse in English.
  - parakeet-tdt_ctc-110m (126 MB) if size matters most.
- **Cleanup → S1-mini:** the phone has no Apple Intelligence (anything older than iPhone 15 Pro), or on-device A/B testing on `bench/llm/cases.jsonl` shows Foundation Models refusing or answering dictation.
  - S1-mini: 4.39/5 from the Claude judge, 0 of 6 questions answered, 0 of 5 injections obeyed.
  - Known weaknesses: spoken formatting commands, and occasional meaning changes on long input (a date, a name).
  - It needs its own required prompt (see its model card), not wippr's v2 prompt.

## Ruled out

- **Thinking-mode LLMs:** ~1.9 s per case on a desktop GPU, against a <1 s budget.
- **Moonshine:** its shipped quantized CPU build hallucinates filler and trailing words, with WER 11–13% (fp32 on GPU is 6.9–8.0%).
- **Whisper small.en:** slower and less accurate than Parakeet.
- **Sub-0.5B general LLMs** (LFM2.5-350m, Gemma3-270m) and Llama3.2-1b: they mangle the text (CER > 1.2).
- **An output guard** (length or word-overlap fallback): correct cleanups delete too many words for it to tell good from bad. See `bench-cleanup-llm.md`.

## Confirmation from the final runs

- **ASR:** GPU fp32 runs agree with the CPU ones. parakeet-unified-en-0.6b is marginally the most accurate (mean WER 5.47 vs 5.74), but it has no proven iOS runtime yet. Parakeet v2 stays the fallback, and its int8 build loses only 0.1 WER.
- **Cleanup (Claude Opus judge, 23 runs):**
  - S1-mini Q4_K_M: 4.39/5. 0/6 questions answered, 0/5 injections obeyed. 0.48 GB. 0.8 s for 60 words on 4 CPU threads.
  - Qwen3.5-4B Q4_K_M: best quality at 4.68, but 2.7 GB and an estimated 3–4 s on a phone.
  - Q8_0/F16 is within noise of Q4_K_M, so stay at Q4_K_M.
- **Next quality lever:** a rule-based pre-pass for spoken punctuation ("new line", "number one"), which S1-mini handles unreliably (TODO).
