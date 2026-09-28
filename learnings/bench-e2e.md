# End-to-end bench: speech → ASR → cleanup LLM

**TL;DR (2026-09-28)**
- The 66 cleanup cases (`bench/llm/cases.jsonl`) were spoken with Kokoro TTS (2 voices, clean and 10 dB pink noise), transcribed with Parakeet, cleaned with 7 LLMs, and graded by the same Claude Opus judge as `bench-cleanup-llm.md`.
- **Pick: S1-mini Q4_K_M + the list rules (`ios/App/Prepass.swift`): 4.18/5 end-to-end** on Parakeet v2 output (4.44 on the hand-written text). On the phone it runs on the Neural Engine via Core AI (iOS 27, experimental, Home → Experimental); an earlier llama.cpp CPU version was dropped. Apple Foundation Models stays the default. Qwen3.5-4B is better (4.36) but ~7× larger and too slow on a phone CPU.
- **The LLM is worth +0.8.** Parakeet text alone scores 3.38. With S1-mini it reaches 4.14, or 4.18 with the list rules.
- **ASR costs every LLM ~0.25.** S1-mini goes 4.38 → 4.14, Qwen3.5-4B 4.64 → 4.36. Most of the losses are ASR word errors no cleanup can undo ("useEffect" → "use of FectHook", "API" → "PI", "comma" → "Common", "Mei" → "May"), plus wrong ASR sentence breaks ("running on. Staging").
- **The new 2026 fine-tunes lose to S1-mini here.** BudgieScribe-Nano-en: 3.97 text / 3.61 ASR. speakoflow-mini: 3.17 text / 3.89 ASR. It is also ~1.5× slower on CPU (Qwen3.5 architecture).
- The full spoken-command pre-pass (comma/period/new line → punctuation) does **not** help: +lists but −spoken_format. The ASR mangles the command words, and S1-mini already handles most of them. Keep only the list rules.

## Results (Parakeet v2, US voice, clean, unless noted)

Judge 1–5 over 66 cases. Differences under ~0.1 are noise (one judge pass).

| cleanup | input | judge | ≥4 | answered | corr missed | lists | spoken fmt | long |
|---|---|---|---|---|---|---|---|---|
| Qwen3.5-4B Q4_K_M | hand-written text | 4.64 | 58 | 0 | 2 | 5.0 | 4.2 | 2.5 |
| **S1-mini + list rules** | hand-written text | **4.44** | 56 | 0 | 2 | 4.5 | 4.5 | 2.0 |
| S1-mini | hand-written text | 4.38 | 54 | 0 | 2 | 3.7 | 4.5 | 2.0 |
| Qwen3.5-4B Q4_K_M | ASR | 4.36 | 55 | 0 | 3 | 4.2 | 3.7 | 2.5 |
| **S1-mini + list rules** | ASR | **4.18** | 51 | 0 | 3 | 4.2 | 4.2 | 2.0 |
| S1-mini | ASR | 4.14 | 48 | 0 | 3 | 3.8 | 4.2 | 2.0 |
| S1-mini, full pre-pass | ASR | 4.12 | 50 | 0 | 3 | 4.3 | 3.7 | 2.0 |
| S1-mini, lowercased/unpunctuated input | ASR | 4.14 | 50 | 0 | 3 | 3.5 | 3.8 | 2.5 |
| S1-mini | Parakeet v3 | 3.95 | 46 | 0 | 2 | 3.7 | 3.8 | 2.0 |
| S1-mini + list rules | ASR, UK voice, noisy | 3.92 | 44 | 0 | 2 | 4.0 | 4.2 | 2.0 |
| Qwen3.5-2B | ASR | 3.91 | 43 | 0 | 9 | 3.8 | 3.2 | 2.0 |
| speakoflow-mini Q4_K_M | ASR | 3.89 | 41 | 0 | 2 | 3.7 | 3.5 | 2.0 |
| S1-mini | Parakeet 110m | 3.80 | 41 | 0 | 2 | 2.8 | 4.0 | 2.0 |
| BudgieScribe-Nano-en | ASR | 3.61 | 37 | 0 | 4 | 2.8 | 2.5 | 1.5 |
| Qwen3.5-0.8B | ASR | 3.55 | 34 | 1 | 10 | 3.3 | 3.0 | 2.0 |
| none (ASR only) | ASR | 3.38 | 27 | 0 | 10 | 3.0 | 2.7 | 2.0 |

Full table (29+ runs, all variants and categories): `bench/e2e/results/summary.md`.

**ASR WER on the synthetic dictation** (whisper normalizer, vs the spoken script; GPU bf16):

| model | US clean | US noisy | UK clean | UK noisy | peak VRAM |
|---|---|---|---|---|---|
| parakeet-tdt-0.6b-v2 | 4.90 | 5.94 | 4.82 | 5.14 | 4.8 GB |
| parakeet-tdt-0.6b-v3 | 4.74 | 5.46 | 4.58 | 5.94 | 4.9 GB |
| parakeet-tdt_ctc-110m | 5.54 | 6.35 | 6.27 | 7.55 | 0.9 GB |

v3 has slightly lower WER, but its text cleans worse (3.95 vs 4.14). Its errors land on words that matter (technical terms: 2.7 vs 3.7).

**Phone-proxy speed** (60-word case, 4 desktop P-cores, CPU only, llama.cpp b10709): S1-mini 663 ms warm / 816 ms cold; BudgieScribe-Nano 718 / 798; speakoflow-mini 1038 / 1397; Qwen3.5-0.8B 1136 / 2431. Qwen3.5-architecture models are slower on CPU at the same size. (These CPU numbers are from when llama.cpp was the plan; the app now uses the Neural Engine instead. On-device numbers are in the section below.)

## Caveats

- **TTS, not people.** Kokoro reads the raw script evenly, with no real disfluency prosody or room acoustics, so WER is optimistic. Some errors are TTS artefacts ("comma" pronounced like "common"). The ranking of LLMs should hold. Absolute ASR numbers won't.
- **Apple SpeechTranscriber (what the app uses for ASR) can't run on Linux.** Parakeet stands in for it. SpeechTranscriber also punctuates and capitalizes, but its errors differ.
- The fine-tunes' own evals disagree with this one. speakoflow reports S1-mini at 15% on its exact-match set, for example. Its metric rewards returning already-clean text untouched, while this judge rewards applying fillers/lists/ITN.
- Parakeet 0.6B peaked at ~4.8 GB of VRAM on the 60 s clips, even in bf16. Chunk long audio if VRAM is tight.

## What didn't help

- **Full spoken-command pre-pass** (`prepass.py` `prepass()`): 4.12 vs 4.14. It fixes lists but breaks formatting when the ASR has already mangled the command words.
- **Lowercasing / stripping ASR punctuation** before S1-mini ("as it was trained"): 4.14, no change.
- **Qwen3.5-2B:** keeps both halves of self-corrections (9 missed).

## Reproduce

```bash
cd bench/e2e && ./fetch.sh
../asr/.venv/bin/python tts.py         # ROCm torch env + `uv pip install kokoro 'misaki[en]'` there
../asr/.venv/bin/python asr.py         # Parakeet v2/v3/110m, GPU
uv run pipeline.py gen s1-mini/parakeet-tdt-0.6b-v2:us-f/lists ...   # see pipeline.py docstring
uv run pipeline.py judge && uv run pipeline.py report
uv run cputime.py s1-mini budgie-nano  # phone-proxy CPU timing
uv run prepass.py                      # pre-pass unit tests
```
