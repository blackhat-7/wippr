"""Build the ASR test sets from hf-audio/open-asr-leaderboard (the Open ASR Leaderboard's own test data).

Writes 16 kHz mono wavs to data/<set>/ (gitignored) and a manifest sets/<set>.jsonl (committed)
listing exactly which utterances were used. Deterministic: fixed shards + random.Random(0).
"""

import io
import json
import random
from pathlib import Path

import librosa
import pyarrow.parquet as pq
import soundfile as sf
from huggingface_hub import hf_hub_download

ROOT = Path(__file__).parent
REPO = "hf-audio/open-asr-leaderboard"
N = 200
MIN_S, MAX_S = 2.0, 20.0

# set name -> parquet shard (AMI/earnings22 shards are length-sorted; these hold mid-length utterances)
SETS = {
    "ls-clean": "librispeech/test.clean-00000-of-00001.parquet",
    "ls-other": "librispeech/test.other-00000-of-00001.parquet",
    "ami": "ami/test-00003-of-00015.parquet",
    "earnings22": "earnings22/test-00002-of-00005.parquet",
}


def decode(audio: dict):
    wav, sr = sf.read(io.BytesIO(audio["bytes"]), dtype="float32", always_2d=True)
    wav = wav.mean(axis=1)
    if sr != 16000:
        wav = librosa.resample(wav, orig_sr=sr, target_sr=16000)
    return wav


def main():
    (ROOT / "sets").mkdir(exist_ok=True)
    clip_pool = []
    for name, shard in SETS.items():
        rows = pq.read_table(hf_hub_download(REPO, shard, repo_type="dataset")).to_pylist()
        items = []
        for i, r in enumerate(rows):
            wav = decode(r["audio"])
            dur = len(wav) / 16000
            if MIN_S <= dur <= MAX_S and r["text"].strip():
                items.append((str(r.get("id") or f"{name}-{i}"), r["text"], wav, dur))
        if name == "ls-clean":
            clip_pool = items
        chosen = sorted(random.Random(0).sample(items, N), key=lambda x: x[0])
        out = ROOT / "data" / name
        out.mkdir(parents=True, exist_ok=True)
        with open(ROOT / "sets" / f"{name}.jsonl", "w") as f:
            for uid, text, wav, dur in chosen:
                path = out / (uid.removesuffix(".wav").replace("/", "_") + ".wav")
                sf.write(path, wav, 16000)
                rec = {"id": uid, "audio": str(path.relative_to(ROOT)), "duration": round(dur, 3), "text": text}
                f.write(json.dumps(rec) + "\n")
        total = sum(c[3] for c in chosen)
        print(f"{name}: {len(chosen)} of {len(items)} eligible, {total / 60:.1f} min from {shard}")

    # latency clips: test-clean utterances closest to 5 s and 15 s
    clips = {}
    for target in (5, 15):
        uid, text, wav, dur = min(clip_pool, key=lambda x: abs(x[3] - target))
        path = ROOT / "data" / f"clip{target}.wav"
        sf.write(path, wav, 16000)
        clips[f"clip{target}"] = {"id": uid, "audio": str(path.relative_to(ROOT)), "duration": round(dur, 3), "text": text}
    (ROOT / "sets" / "clips.json").write_text(json.dumps(clips, indent=1) + "\n")
    print("clips:", {k: (v["id"], v["duration"]) for k, v in clips.items()})


if __name__ == "__main__":
    main()
