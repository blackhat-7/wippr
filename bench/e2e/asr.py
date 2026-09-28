"""Transcribe the synthesized dictation clips with each ASR model (GPU, bf16, one model at a time).

    ../asr/.venv/bin/python asr.py [MODEL...]

Writes results/asr/<model>.json: per condition (voice, clean/noisy) the hypothesis per case, WER against
the spoken script (whisper normalizer) and GPU time. bf16 keeps Parakeet 0.6B near 1.5 GB of VRAM.
"""

import json
import sys
import time
from pathlib import Path

import jiwer
import soundfile as sf
import torch
from whisper_normalizer.english import EnglishTextNormalizer

from tts import CASES, VOICES, spoken

HERE = Path(__file__).parent
CONDITIONS = [v for voice in VOICES for v in (voice, f"{voice}-noisy")]
MODELS = {
    "parakeet-tdt-0.6b-v2": "nvidia/parakeet-tdt-0.6b-v2",
    "parakeet-tdt-0.6b-v3": "nvidia/parakeet-tdt-0.6b-v3",
    "parakeet-tdt_ctc-110m": "nvidia/parakeet-tdt_ctc-110m",
}


def load(name):
    import nemo.collections.asr as nemo_asr
    from omegaconf import OmegaConf, open_dict

    # NeMo's TDT greedy decoder defaults to CUDA graphs, which need the NVIDIA driver; off on ROCm.
    cfg = nemo_asr.models.ASRModel.from_pretrained(name, return_config=True)
    with open_dict(cfg):
        cfg.decoding.greedy.use_cuda_graph_decoder = False
    override = Path.home() / ".cache" / "wippr-asr" / f"{name.replace('/', '__')}.yaml"
    override.parent.mkdir(parents=True, exist_ok=True)
    OmegaConf.save(cfg, override)
    model = nemo_asr.models.ASRModel.from_pretrained(name, override_config_path=str(override), map_location="cuda")
    return model.eval().to(torch.bfloat16)


@torch.inference_mode()
def transcribe(model, wav):
    out = model.transcribe([wav], batch_size=1, verbose=False)
    out = out[0] if isinstance(out, tuple) else out
    return out[0].text if hasattr(out[0], "text") else out[0]


def main(models):
    norm = EnglishTextNormalizer()
    (HERE / "results" / "asr").mkdir(parents=True, exist_ok=True)
    for m in models:
        torch.cuda.reset_peak_memory_stats()
        model = load(MODELS[m])
        transcribe(model, sf.read(HERE / "data" / CONDITIONS[0] / "filler_01.wav", dtype="float32")[0])  # warm up
        res = {"model": m, "precision": "bf16", "conditions": {}}
        for cond in CONDITIONS:
            hyps, refs, rows, gpu_s, audio_s = [], [], {}, 0.0, 0.0
            for c in CASES:
                wav, sr = sf.read(HERE / "data" / cond / f"{c['id']}.wav", dtype="float32")
                t = time.perf_counter()
                text = transcribe(model, wav)
                torch.cuda.synchronize()
                gpu_s += time.perf_counter() - t
                audio_s += len(wav) / sr
                rows[c["id"]] = text
                refs.append(norm(spoken(c["raw"])))
                hyps.append(norm(text))
            wer = jiwer.wer(refs, hyps)
            res["conditions"][cond] = {"wer": round(100 * wer, 2), "rtf": round(gpu_s / audio_s, 4), "hyps": rows}
            print(f"{m} {cond}: WER {100 * wer:.2f}%  RTF {gpu_s / audio_s:.4f}", flush=True)
        res["gpu_peak_mb"] = round(torch.cuda.max_memory_allocated() / 2**20)
        print(m, "peak VRAM MB", res["gpu_peak_mb"], flush=True)
        (HERE / "results" / "asr" / f"{m}.json").write_text(json.dumps(res, indent=1, ensure_ascii=False))
        del model
        torch.cuda.empty_cache()


if __name__ == "__main__":
    main(sys.argv[1:] or list(MODELS))
