# Phone stack decision

**Decision (2026-09-27, from partial benchmarks; will be confirmed when the runs finish)**

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
  - S1-mini led the partial grading: 4.45/5, 0 of 6 questions answered, 0 of 5 injections obeyed.
  - Known weaknesses: spoken formatting commands, and occasional meaning changes on long input (a date, a name).
  - It needs its own required prompt (see its model card), not wippr's v2 prompt.

## Ruled out

- **Thinking-mode LLMs:** ~1.9 s per case on a desktop GPU, against a <1 s budget.
- **Moonshine:** hallucinates filler and trailing words; WER 11–13%.
- **Whisper small.en:** slower and less accurate than Parakeet.
- **Sub-0.5B general LLMs** (LFM2.5-350m, Gemma3-270m) and Llama3.2-1b: they mangle the text (CER > 1.2).
- **An output guard** (length or word-overlap fallback): correct cleanups delete too many words for it to tell good from bad. See `bench-cleanup-llm.md`.

## Pending

- Claude-graded scores for all 21 cleanup runs, plus Q8_0 for the top 2 → `bench-cleanup-llm.md`.
- GPU reference WER for all ASR models, including whisper-large-v3-turbo, nemotron and parakeet-unified → `bench-asr.md`.
- Revisit this file if either changes the ranking.
