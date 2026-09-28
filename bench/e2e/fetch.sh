#!/usr/bin/env bash
# Downloads the cleanup GGUFs into the HF cache (~8 GB). Kokoro and the Parakeet models download on first use.
set -euo pipefail
cd "$(dirname "$0")"
uv run python - <<'PY'
from huggingface_hub import hf_hub_download
import pipeline
for repo, file, *_ in pipeline.LLMS.values():
    print(hf_hub_download(repo, file), flush=True)
PY
