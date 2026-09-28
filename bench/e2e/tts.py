"""Synthesize the 66 dictation cases (../llm/cases.jsonl) as speech, so ASR and the full pipeline can be scored.

    ../asr/.venv/bin/python tts.py        # the ROCm torch env; needs `kokoro` + `misaki[en]` installed there

Kokoro-82M (PyTorch, GPU, ~0.8 GB VRAM), two voices, 16 kHz mono. Writes data/<voice>/<id>.wav (clean) and
data/<voice>-noisy/<id>.wav (pink noise at 10 dB SNR). The spoken script is the case's `raw` text,
with a few spellings changed so the TTS says them the way a person would (SPOKEN).
"""

import json
import re
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

HERE = Path(__file__).parent
CASES = [json.loads(line) for line in (HERE.parent / "llm" / "cases.jsonl").read_text().splitlines() if line.strip()]
VOICES = {"us-f": ("a", "af_sarah"), "uk-m": ("b", "bm_george")}
SNR_DB = 10
CHUNK_WORDS = 18  # Kokoro truncates long unpunctuated input; speak it in breaths
PAUSE_S = 0.22

# What the TTS would otherwise misread. Keys are exact substrings of `raw`.
SPOKEN = {
    "7 30 i mean 8 30": "seven thirty i mean eight thirty",
    "2 pm": "two p m",
    "q3": "q three",
    "q2": "q two",
    "npm install then npm run dev and open localhost 3000": "n p m install then n p m run dev and open local host three thousand",
    "postgres 14 to 16": "postgres fourteen to sixteen",
    "1.30": "one point thirty",
    "the api returns a 404 when the json": "the a p i returns a four oh four when the jason",
    "asap": "a sap",
    "cc mr": "c c mister",
    "PR tonight and leave comments by 9 AM": "P R tonight and leave comments by nine A M",
}


def spoken(raw):
    for k, v in SPOKEN.items():
        raw = raw.replace(k, v)
    return raw


def breaths(text):
    """Split at punctuation if there is any, else every CHUNK_WORDS words."""
    parts = [p.strip() for p in re.split(r"(?<=[.?!,])\s+", text) if p.strip()]
    out = []
    for p in parts:
        words = p.split()
        out += [" ".join(words[i:i + CHUNK_WORDS]) for i in range(0, len(words), CHUNK_WORDS)]
    return out


def pink(n, rng):
    white = rng.standard_normal(n)
    f = np.fft.rfft(white)
    f /= np.sqrt(np.arange(1, len(f) + 1))
    x = np.fft.irfft(f, n)
    return x / np.std(x)


def main():
    from kokoro import KPipeline

    pipes = {lang: KPipeline(lang_code=lang, device="cuda") for lang, _ in VOICES.values()}
    rng = np.random.default_rng(0)
    meta = []
    for voice, (lang, name) in VOICES.items():
        for d in (voice, f"{voice}-noisy"):
            (HERE / "data" / d).mkdir(parents=True, exist_ok=True)
        for c in CASES:
            pieces = [np.zeros(int(0.4 * 24000), np.float32)]
            for chunk in breaths(spoken(c["raw"])):
                for seg in pipes[lang](chunk, voice=name, speed=1.0):
                    pieces.append(np.asarray(seg.audio, np.float32))
                pieces.append(np.zeros(int(PAUSE_S * 24000), np.float32))
            pieces.append(np.zeros(int(0.3 * 24000), np.float32))
            wav = resample_poly(np.concatenate(pieces), 2, 3).astype(np.float32)
            wav *= 0.5 / max(1e-6, np.abs(wav).max())
            sf.write(HERE / "data" / voice / f"{c['id']}.wav", wav, 16000, subtype="PCM_16")
            speech_rms = np.sqrt(np.mean(wav[np.abs(wav) > 0.01] ** 2))
            noisy = wav + pink(len(wav), rng) * speech_rms / 10 ** (SNR_DB / 20)
            noisy *= 0.5 / np.abs(noisy).max()
            sf.write(HERE / "data" / f"{voice}-noisy" / f"{c['id']}.wav", noisy.astype(np.float32), 16000, subtype="PCM_16")
            meta.append({"voice": voice, "id": c["id"], "duration": round(len(wav) / 16000, 2)})
            print(voice, c["id"], meta[-1]["duration"], flush=True)
    (HERE / "data" / "meta.json").write_text(json.dumps(meta, indent=1))


if __name__ == "__main__":
    main()
