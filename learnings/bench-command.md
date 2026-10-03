# Command bench: dictating shell commands

**TL;DR** (2026-09-28, `bench/command`, M4 Pro Mac)
- **Terminal fields use Whisper small.en (q8_0, 264 MB) primed with a shell prompt, CPU only.** Normal dictation stays on Apple SpeechTranscriber.
- Exact-match accuracy, 4 macOS voices (2 US, 2 Indian English), after `SpokenSymbols` + `CommandWriter`:

  | Recognizer | Public set (47 commands + 8 prompts) | Private set (45 commands from my shell history) |
  |---|---|---|
  | Apple SpeechTranscriber (what normal dictation uses) | 22–36% | – |
  | Parakeet TDT 0.6B v2 (MLX) | 49–58% | 20–33% |
  | **Whisper small.en q8_0 + shell prompt, `-ac 512`** | **55–64%** | **27–40%** |

- **Symbols are solved in code** (`SpokenSymbols`: dash dash → `--`, slash, dot, tilde, pipe, and and, quote…, at → `@` before a host). It's a closed set; the model did it badly (dropped slashes and dots).
- **Names are the hard part.** Speech recognizers write commands as English ("get status", "Cuba control get pods", "10 p.m. run dev"). The on-device model (`CommandWriter`) fixes some, guarded so it can only change words: same symbols, ≥ 0.5 similarity. That guard stops invented commands (e.g. "Coop control get pods" → a `curl -X POST …` line).
- **Whisper's prompt is what wins.** Without a prompt Whisper small scores 30–45%. A prompt written in the spoken style ("git pull dash dash rebase and and git log. cd tilde slash projects…") plus command names makes it write symbols as words (which `SpokenSymbols` then spaces correctly) and hear names: 53–66% at full precision. Parakeet hears better raw but has no prompt.
- **Prose in terminals** (prompts for Claude Code): a rule, not the model. ≥ 4 words, ≥ 2 English function words, no symbols → typed as normal dictation. All 8 prompt cases pass, including "make sure…" and "find where…". Asking the model to classify (a Bool in the guided output) called commands prose and was 3–4× slower.

## Noise (2026-10-02, iPad 10th gen + Mac test clips)
- **Sound-alike shortcut matching** (`Shortcuts.soundAlike`): words → `soundKey` (plus r after a vowel dropped), at most one sound off, no tie. 1,768 clips (macOS voices; fan, traffic, babble at 0–10 dB SNR): tmux shortcuts caught 56% → 76%, 0 wrong, 0 false triggers on 1,152 non-shortcut clips. Catches 13 of 20 real iPad mishearings ("Teamworks attach", "T-Marks attach"). Distance 2 or joining words gave false triggers; on short delete phrases it picked the wrong delete, so deletes stay exact.
- **Voice detector (Silero via whisper.cpp)** stops Whisper's phantom words ("you") on silence, taps and breaths, but missed real speech over a fan 14 times, so it only runs when Apple heard nothing.

## Dropped
- **Other open recognizers via audio.cpp** (2026-10-03, Metal, the same 1,768 noisy clips, scored through the app's matching): Whisper small.en + shell prompt 75% shortcuts / 45% exact commands; Qwen3-ASR-0.6B (1.15 GB) 59% / 31%, with the shell prompt as context 58% / 44% and 2 false triggers; Parakeet-TDT 0.6B v3 47% / 34% (multilingual, drifts to Russian in noise); Nemotron 3.5 ASR 0.6B (en-US) 45% / 22%; Moonshine medium 46% / 28%; Canary 180M aborted the batch (max tokens on noise). Whisper stays.
- **Apple voice processing** (`setVoiceProcessingEnabled`, FaceTime's noise suppression): no better with a fan or a video playing nearby; on with the video, Whisper got worse.
- **Scoring shortcut phrases against the audio** (Whisper teacher-forced log-probability vs its free transcript): +1–3 points at safe cutoffs, dozens of false triggers at useful ones. In noise every phrase scores badly; when the audio is clear, the free transcript already has it.
- **Apple custom language models** (`SFCustomLanguageModelData`, templates + X-SAMPA pronunciations, prepared on device in ~6 s): 2–13% with SFSpeechRecognizer, weight default or 1.0. Only DictationTranscriber/SFSpeechRecognizer take them, and both hear commands worse than SpeechTranscriber (DictationTranscriber 0–6%).
- **Recognizer alternatives** didn't help (±4 points).
- **Command list in the model's instructions**: ~150 names made each call slower than the 3 s timeout.

## Costs of Whisper (see `ios-platform-constraints.md`)
- Runs in the background, where iOS 27 blocks GPU and (without an entitlement) the ANE: CPU only. On the Mac's CPU, 4 threads, a 1.5 s clip takes 0.63 s with `audio_ctx` 512 vs 2.1 s at the default 30 s window. q5_1 (190 MB) lost ~5 points vs q8_0.
- Memory: ~666 MB peak on macOS (q8_0). Watch for jetsam on device.
- One-tap download on Home; never automatic.

## Caveats
- Test audio is macOS TTS reading the spoken form, which mispronounces jargon worse than people do ("dish aswak" for "dash s work"). Real speech is probably easier; confirm on device.
- The benchmark's whisper-cli uses beam search; the app decodes greedily.
- Examples in prompts are chosen not to overlap the test cases; the built-in command list does include common tools the cases use (git, tmux, nix…), as a shipped list would.
