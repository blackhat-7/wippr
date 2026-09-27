#!/usr/bin/env bash
# Reproduce the whole ASR benchmark from scratch:  ./run_all.sh  [model ...]
# GPU runs hold ../.gpu.lock (shared with the LLM bench). CPU runs are pinned to 4 P-cores.
set -euo pipefail
cd "$(dirname "$0")"

WCPP=.build/whisper.cpp
if [ ! -x "$WCPP/build-cpu/bin/whisper-server" ]; then
  git clone --depth 1 https://github.com/ggml-org/whisper.cpp "$WCPP"
  cmake -S "$WCPP" -B "$WCPP/build-hip" -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1100 -DCMAKE_BUILD_TYPE=Release
  cmake --build "$WCPP/build-hip" -j 12 --target whisper-server
  cmake -S "$WCPP" -B "$WCPP/build-cpu" -DCMAKE_BUILD_TYPE=Release
  cmake --build "$WCPP/build-cpu" -j 12 --target whisper-server
fi

uv sync
[ -f sets/clips.json ] || uv run prep_data.py

models=("$@")
[ ${#models[@]} -gt 0 ] || mapfile -t models < <(uv run python -c 'import bench; print(*bench.MODELS, sep="\n")')
for m in "${models[@]}"; do
  flock ../.gpu.lock uv run bench.py "$m" gpu
  taskset -c 0,2,4,6 uv run bench.py "$m" cpu
done
uv run report.py > results/table.md
cat results/table.md
