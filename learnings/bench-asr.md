# ASR bench: bundled model vs Apple SpeechTranscriber

**TL;DR** (2026-09-27. GPU reference runs done for all 9 models; CPU phone-proxy runs for 5 models + 1 partial. The full table is in `bench/asr/results/table.md` and in the GPU section below.)
- **Keep Apple SpeechTranscriber for v0.1.** No bundled model is better by enough to pay ~0.5 GB of app size, a 3.4 s cold ANE compile and the iOS 27 background ANE entitlement.
- **Best bundled model: Parakeet TDT 0.6B v2** (English). Mean WER 5.8% on our 4 sets, RTF 0.14 on 4 CPU cores. It beats SpeechTranscriber by ~2.3 WER points on earnings22 (11.7 vs 14.0 in Argmax's same-subset test) and ~0.4–1.4 points on LibriSpeech (published numbers).
- **Runner-up: Parakeet TDT 0.6B v3** (multilingual, 25 European langs). ~1.7 points worse than v2 in English. Pick it only if you need non-English.
- whisper-small.en is smaller (252 MB) but less accurate and ~2× slower than Parakeet on CPU. Moonshine streaming small/medium are the least accurate here: they hallucinate filler ("yeah") and tail words on whole-utterance decode.
- If app size or CPU budget matters most: parakeet-tdt_ctc-110m (126 MB, RTF 0.013, ~10× faster than v2) is about whisper-small.en accuracy on LibriSpeech (partial run).
- **GPU (full precision) confirms the ranking.** The most accurate is parakeet-unified-en-0.6b (mean 5.47; best on AMI at 7.37 and earnings22 at 10.24), just ahead of v2 (5.74). Unified has no proven iOS runtime yet (FluidAudio ships TDT v2/v3), so v2 stays the fallback pick.
- **Moonshine is hurt by its quantized CPU runtime, not its architecture.** At fp32 on GPU, medium scores 6.85 mean; its shipped quantized CPU build scores 11.05.
- Revisit if on-device tests show SpeechTranscriber failing in the background, or if users hit accuracy limits on jargon/names.

## Results: CPU 4-thread, phone proxy (partial) (sherpa-onnx / whisper.cpp / moonshine-voice on 4 P-cores of an i5-13600K)

WER % with the Whisper English normalizer, 200 utterances per set. RTF = compute / audio time over all 800 utterances (77 min). Latency = median of 5 runs on one 5 s and one 15 s LibriSpeech clip, whole-utterance decode. Disk = CPU model files.

| model | params | clean | other | AMI | earnings22 | mean | CPU-4t RTF | 5 s ms | 15 s ms | disk MB | streaming | iOS runtime path |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| parakeet-tdt-0.6b-v2 (int8) | 600M | **1.08** | **2.93** | **8.46** | **10.90** | **5.84** | **0.144** | 843 | 1133 | 631 | no (FluidAudio sliding window) | FluidAudio CoreML/ANE; sherpa-onnx CPU |
| parakeet-tdt-0.6b-v3 (int8) | 600M | 1.65 | 4.57 | 10.35 | 13.84 | 7.60 | 0.157 | 1403 | 1346 | 640 | no (FluidAudio sliding window) | FluidAudio CoreML/ANE (library default); sherpa-onnx CPU |
| whisper-small.en (q8_0) | 244M | 2.20 | 6.37 | 15.70 | 12.20 | 9.12 | 0.272 | 1729 | 2012 | 252 | no (30 s windows) | WhisperKit CoreML/ANE; whisper.cpp |
| moonshine-streaming-medium | 266M | 3.65 | 8.43 | 16.20 | 15.92 | 11.05 | 0.319 | 1302 | 4062 | 257 | yes | moonshine-voice (ORT CPU) |
| moonshine-streaming-small | 140M | 4.38 | 10.88 | 18.98 | 16.81 | 12.76 | 0.186 | 938 | 2771 | 136 | yes | moonshine-voice (ORT CPU) |
| parakeet-tdt_ctc-110m (int8) — partial * | 114M | 2.41 | 5.89 | 14.31 | – | – | 0.013 | – | – | 126 | no | sherpa-onnx CPU |
| nemotron-streaming-en-0.6b (int8, 560 ms) | 618M | not run | | | | | | | | | yes | sherpa-onnx CPU; FluidAudio lists Nemotron streaming |
| parakeet-unified-en-0.6b (int8) | 600M | not run | | | | | | | | | yes | sherpa-onnx CPU; FluidAudio lists Parakeet Unified |
| whisper-large-v3-turbo (q8_0) | 809M | not run | | | | | | | | 834 | no | WhisperKit CoreML/ANE; whisper.cpp |
| **Apple SpeechTranscriber** (NOT measured here) | n/a (system asset) | 2.12 † | 4.56 † | – | 14.0 ‡ | – | ~70× realtime ‡ (M4) | – | – | 0 in app | yes (volatile + final) | system, out of process |

† [Lyonesse benchmark](https://lyonesse.app/blog/apple-speech-api-benchmark.html) (2026-07-13, product team, M2 Pro, macOS 26.5.1): full LibriSpeech test-clean/test-other (5,559 utts), OpenAI-style normalizer. Labelled "SpeechAnalyzer"; module not stated (presumably SpeechTranscriber). Same test: Whisper Small 3.74 / 7.95.
‡ [Argmax](https://www.argmaxinc.com/blog/apple-and-argmax) (2025-06-20, M4 Mac mini, macOS 26 beta 1): random 10% of earnings22 (~12 h). Same test: parakeet-v2 (Argmax Pro) 11.7, whisper-small.en 12.8, whisper-base.en 15.2.

\* 110m was stopped during earnings22 when the plan switched to GPU-only, so it has no results JSON; numbers are from `bench/asr/logs/parakeet-tdt_ctc-110m__cpu.log`. Latency clips were measured but not saved.

Cross-check: our earnings22 numbers track Argmax's on the models both tested (parakeet-v2 10.9 vs 11.7; whisper-small.en 12.2 vs 12.8). So the 14.0 for SpeechTranscriber sits on roughly the same scale, but it is a different subset and a different machine.

## Is a bundled model worth it over SpeechTranscriber?

**No, not for v0.1.**
- Accuracy gain: Parakeet v2 is ~2.3 points better on earnings22 (~16% relative) and ~0.4 / 1.4 points better on LibriSpeech (model card: 1.69 / 3.19 on full test sets, vs SpeechTranscriber 2.12 / 4.56). Real, but small, and the cleanup LLM fixes part of the gap (unverified: not measured).
- Cost: ~450–630 MB model in the app bundle or a first-run download, ~2 GB RSS on CPU (int8 onnx), a 3.4 s cold CoreML compile on iPhone 16 Pro Max (FluidAudio; see `oss-alternatives.md`), and the iOS 27 `continued-processing.inference` entitlement to use the ANE in the background. On CPU (no entitlement) a 15 s dictation takes ~1.1 s on 4 desktop P-cores; phone cores are slower, so it would miss the 1.5 s target (unverified on device).
- SpeechTranscriber ships no weights, streams, and runs out of process.
- **When to switch:** if on-device tests show SpeechTranscriber is unavailable or rate-limited in the background, or users report accuracy problems. Then bundle Parakeet v2 via FluidAudio (English) or v3 (multilingual).

## GPU reference results (full precision, 2026-09-27)

Run by the main session after the blocked agent runs. NeMo needed one fix: its TDT/RNNT greedy decoder defaults to CUDA graphs, which need the NVIDIA driver. `load_nemo` now turns off `use_cuda_graph_decoder`.

| model | runtime | clean | other | AMI | earn22 | mean | GPU RTF | 5 s ms | 15 s ms |
|---|---|---|---|---|---|---|---|---|---|
| parakeet-unified-en-0.6b | nemo fp32 | 1.15 | 3.13 | **7.37** | **10.24** | **5.47** | 0.022 | 59 | 129 |
| parakeet-tdt-0.6b-v2 | nemo fp32 | **1.13** | **2.82** | 8.71 | 10.30 | 5.74 | 0.011 | 47 | 108 |
| parakeet-tdt-0.6b-v3 | nemo fp32 | 1.49 | 3.72 | 9.39 | 11.18 | 6.45 | 0.011 | 46 | 104 |
| moonshine-streaming-medium | hf fp32 | 1.39 | 4.90 | 9.30 | 11.82 | 6.85 | – | – | – |
| nemotron-streaming-en-0.6b | nemo fp32, 560 ms chunks | 1.57 | 5.33 | 8.80 | 12.89 | 7.15 | 0.020 | 54 | 126 |
| whisper-large-v3-turbo | whisper.cpp q8_0 HIP | 1.42 | 3.72 | 12.63 | 11.31 | 7.27 | 0.021 | 117 | 186 |
| parakeet-tdt_ctc-110m | nemo fp32 | 1.73 | 5.44 | 12.71 | 11.06 | 7.74 | 0.014 | 27 | 75 |
| moonshine-streaming-small | hf fp32 | 1.52 | 6.88 | 10.52 | 13.05 | 7.99 | – | – | – |
| whisper-small.en | whisper.cpp q8_0 HIP | 2.26 | 6.40 | 15.91 | 12.23 | 9.20 | 0.016 | 97 | 234 |

Parakeet v2 at int8 on CPU (5.84) is within 0.1 of fp32 (5.74), so its shipped quantized build loses almost nothing.

## Commands

```bash
cd bench/asr
# CPU (phone proxy): 4 P-cores, shared lock with the cleanup-LLM bench
flock ../.cpu.lock taskset -c 0,2,4,6 uv run bench.py <model> cpu
# GPU (only when VRAM is free)
flock ../.gpu.lock uv run bench.py <model> gpu
uv run report.py > results/table.md
```
Raw results incl. every hypothesis: `bench/asr/results/<model>__<device>.json`. Logs: `bench/asr/logs/`.

## Caveats

- Hardware: desktop i5-13600K, 4 P-cores (`taskset -c 0,2,4,6`), 4 threads. Not a phone. Treat RTF/latency as relative rankings.
- The cleanup-LLM bench ran untimed work on cores 8–19 at the same time. Shared L3/memory bandwidth makes latencies noisy (e.g. v3 5 s clip 1403 ms vs 15 s clip 1346 ms). Use RTF over 77 min of audio as the stable speed number.
- 200 utterances per set: WER differences under ~0.5 points (clean) or ~1 point (AMI/earnings22) are noise.
- AMI references are verbatim (repetitions, "the the the"). Whisper drops disfluencies, which costs it WER on AMI but is what you want in dictation.
- CPU int8/q8 runtimes, not the CoreML/ANE builds that would ship. ANE builds are fp16 and usually a bit more accurate.
- Moonshine streaming models: latency here is whole-utterance decode; in real streaming use the wait after you stop talking is only the tail, which would be much shorter.
- whisper.cpp always encodes a 30 s window, so short clips cost as much as 30 s ones. WhisperKit does the same by default.
- SpeechTranscriber numbers are published, not measured here: different subsets, machines and normalizers. It can't run on Linux.
