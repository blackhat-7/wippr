# ROCm / local inference setup notes (7900 XTX, gfx1100)

## llama.cpp (cleanup-LLM bench, 2026-09-26)
- The existing HIP build at `~/Documents/projects/llamacpp-tuner/tmp/llama.cpp/build-hip/bin/` works (build 1798, gfx1100, rocWMMA flash attention, HIP graphs). It is 137 commits behind upstream but loaded every candidate. It has no `llama-cli`, so use `llama-server` / `llama-bench`.
- For a CPU-only run on the HIP build, pass `-dev none`.
- Killing the `uv run` wrapper orphans `llama-server`, which keeps holding its port. `bench/llm/bench.py` handles SIGTERM and picks a free port.
- The HF xet download client can stall at concurrency 1: set `HF_XET_FIXED_DOWNLOAD_CONCURRENCY=8`.
- `llama-server --reasoning off` plus `chat_template_kwargs: {"enable_thinking": false}` per request is how to turn thinking off for Qwen3/Qwen3.5. Greedy decoding (temp 0) with thinking ON makes Qwen3.5 0.8B/2B loop to `max_tokens` with empty `content` on every request.
- CPU-only on the HIP build: `-dev none` for both `llama-server` and `llama-bench` (plus `-ngl 0` for llama-bench). Pin with `taskset -c <cpus>`. With `-ngl 0` alone, the HIP backend still offloads big prompt batches to the GPU (op offload), which spoils "CPU" numbers.
- `llama-bench -o json` → `avg_ts` per test; `n_prompt>0` rows are pp, `n_gen>0` rows are tg.
- GPU VRAM in use: `/sys/class/drm/card2/device/mem_info_vram_used` (bytes). Other projects can park a ~24 GB idle server there; `bench/llm/bench.py` waits for < 3 GB before taking `bench/.gpu.lock`.

## ASR bench env (bench/asr, 2026-09-27)
- torch 2.14.0 from the `download.pytorch.org/whl/rocm7.2` index, Python 3.12 (see `bench/asr/pyproject.toml`).
- `sherpa-onnx` 1.13.8 needs `sherpa-onnx-core` installed explicitly, or the import fails with `libonnxruntime.so: cannot open shared object file`.
- `bench.py` imports `whisper_normalizer`; the package is `whisper-normalizer`.
- whisper.cpp builds with `-DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1100` (see `bench/asr/run_all.sh`).
- `bench.py` had no `moonshine_voice` backend; it now calls the moonshine-voice C API directly (the Python wrapper copies audio through a Python list, which inflates latency). Models download to `~/.cache/moonshine_voice/`.
- sherpa-onnx prints `(null): No such file or directory` on every load. It is harmless.
- A killed sherpa download leaves a partial `.tar.bz2` in `~/.cache/wippr-asr/sherpa/`. Delete it; `sherpa_dir()` only checks for the extracted folder.
- Pre-download models before taking `.cpu.lock`, so the lock covers measurement only.
- whisper.cpp encodes a fixed 30 s window, so large-v3-turbo on 4 CPU threads takes several seconds per utterance (~2 h for the 800-utterance run). Run it last.

## Sharing the GPU / CPU
- Timed CPU runs: `flock bench/.cpu.lock` and `taskset -c 0,2,4,6` (4 P-cores = phone proxy). Untimed CPU work goes on cores 8-19.
- Wrap every timed GPU run in `flock bench/.gpu.lock`. Other projects on this machine (for example llamacpp-tuner) don't use the lock, so check for their `llama-server` processes before timing anything.
