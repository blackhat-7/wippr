"""Phone-proxy speed: the 60-word case on 4 desktop P-cores (taskset 0,2,4,6), CPU only, warm prompt cache.

    uv run cputime.py [LLM...]
"""
import json
import subprocess
import sys
import time
import urllib.request

from huggingface_hub import hf_hub_download

import pipeline as p

case = next(c for c in p.CASES if c["id"] == "timing_60w")
res = {}
for llm in sys.argv[1:]:
    repo, file, style, _ = p.LLMS[llm]
    cmd = ["taskset", "-c", "0,2,4,6", str(p.BIN / "llama-server"), "-m", hf_hub_download(repo, file), "--port", str(p.PORT),
           "--no-webui", "--reasoning", "off", "-np", "1", "-c", "2048", "-dev", "none", "-ngl", "0", "-t", "4"]
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(240):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{p.PORT}/health", timeout=1)
                break
            except OSError:
                time.sleep(0.5)
        runs = []
        for i in range(4):  # 1st is cold (system prompt not cached), the rest warm
            if i:
                p.clean(llm, p.CASES[0]["raw"])
            t = time.perf_counter()
            _, tm = p.clean(llm, case["raw"])
            runs.append({"wall_ms": round((time.perf_counter() - t) * 1000), **tm})
        res[llm] = {"cold": runs[0], "warm": sorted(runs[1:], key=lambda r: r["wall_ms"])[1]}
        print(llm, json.dumps(res[llm]), flush=True)
    finally:
        proc.terminate()
        proc.wait()
(p.RESULTS / "cpu4.json").write_text(json.dumps(res, indent=1))
