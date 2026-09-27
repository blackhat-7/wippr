"""Summarise results/*.json into markdown tables (stdout)."""

import json
from pathlib import Path

from bench import MODELS, SETS

R = {}
for f in sorted((Path(__file__).parent / "results").glob("*.json")):
    d = json.loads(f.read_text())
    R[d["model"], d["device"]] = d


def g(model, dev):
    return R.get((model, dev))


def wer_cells(d):
    if not d:
        return ["–"] * (len(SETS) + 1)
    w = [d["sets"][s]["wer"] for s in SETS]
    return [f"{x:.2f}" for x in w] + [f"{sum(w) / len(w):.2f}"]


def rtf(d):
    if not d:
        return "–"
    return f"{sum(s['proc_s'] for s in d['sets'].values()) / sum(s['audio_s'] for s in d['sets'].values()):.4f}"


def ms(d, k):
    return f"{1000 * d['latency'][k]:.0f}" if d and k in d["latency"] else "–"


print("### Accuracy (WER %, Whisper English normalizer; 200 utts per set)\n")
print("| model | runtime | " + " | ".join(SETS) + " | mean |")
print("|---|---|" + "---|" * (len(SETS) + 1))
for m in MODELS:
    for dev in ("gpu", "cpu"):
        d = g(m, dev)
        if d:
            print(f"| {m} | {dev}: {d['backend']} {d.get('precision', '')} | " + " | ".join(wer_cells(d)) + " |")

print("\n### Speed (batch 1; RTF = compute time / audio time, lower is better)\n")
print("| model | GPU RTF | GPU 5s clip ms | GPU 15s clip ms | CPU-4t RTF | CPU-4t 5s clip ms | CPU-4t 15s clip ms | CPU peak RSS MB | GPU peak alloc MB | CPU model on disk MB |")
print("|---|---|---|---|---|---|---|---|---|---|")
for m in MODELS:
    gd, cd = g(m, "gpu"), g(m, "cpu")
    print(f"| {m} | {rtf(gd)} | {ms(gd, 'clip5_s')} | {ms(gd, 'clip15_s')} | {rtf(cd)} | {ms(cd, 'clip5_s')} | {ms(cd, 'clip15_s')} "
          f"| {cd['peak_rss_mb'] if cd else '–'} | {gd.get('gpu_peak_alloc_mb', '–') if gd else '–'} | {cd.get('disk_mb', '–') if cd else '–'} |")
