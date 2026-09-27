"""Benchmark one ASR model on one device.

    uv run bench.py <model> <gpu|cpu>

GPU = reference-precision runtime on the 7900 XTX (NeMo / transformers on torch-ROCm, whisper.cpp HIP).
CPU = the quantized runtime that also ships on iOS (sherpa-onnx int8, whisper.cpp q8_0, moonshine-voice), 4 threads.
Writes results/<model>__<device>.json with WER per set, RTF, clip latencies, peak memory and all hypotheses.
"""

import json
import os
import resource
import subprocess
import sys
import tarfile
import time
import urllib.request
from pathlib import Path
from statistics import median

import jiwer
import numpy as np
import soundfile as sf
from whisper_normalizer.english import EnglishTextNormalizer

ROOT = Path(__file__).parent
CACHE = Path.home() / ".cache" / "wippr-asr"
SETS = ["ls-clean", "ls-other", "ami", "earnings22"]
THREADS = 4
WHISPER_CPP = ROOT / ".build" / "whisper.cpp"
SHERPA_URL = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/{}.tar.bz2"

# model -> {device: (backend, arg)}
MODELS = {
    "parakeet-tdt-0.6b-v2": {
        "gpu": ("nemo", "nvidia/parakeet-tdt-0.6b-v2"),
        "cpu": ("sherpa_offline", "sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8"),
    },
    "parakeet-tdt-0.6b-v3": {
        "gpu": ("nemo", "nvidia/parakeet-tdt-0.6b-v3"),
        "cpu": ("sherpa_offline", "sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"),
    },
    "parakeet-unified-en-0.6b": {
        "gpu": ("nemo", "nvidia/parakeet-unified-en-0.6b"),
        "cpu": ("sherpa_offline", "sherpa-onnx-nemo-parakeet-unified-en-0.6b-int8-non-streaming"),
    },
    "parakeet-tdt_ctc-110m": {
        "gpu": ("nemo", "nvidia/parakeet-tdt_ctc-110m"),
        "cpu": ("sherpa_offline", "sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8"),
    },
    "nemotron-streaming-en-0.6b": {
        "gpu": ("nemo", "nvidia/nemotron-speech-streaming-en-0.6b", [70, 6]),  # 560 ms chunk, same as cpu
        "cpu": ("sherpa_online", "sherpa-onnx-nemotron-speech-streaming-en-0.6b-560ms-int8-2026-04-25"),
    },
    "whisper-large-v3-turbo": {
        "gpu": ("whispercpp", "ggml-large-v3-turbo-q8_0.bin"),
        "cpu": ("whispercpp", "ggml-large-v3-turbo-q8_0.bin"),
    },
    "whisper-small.en": {
        "gpu": ("whispercpp", "ggml-small.en-q8_0.bin"),
        "cpu": ("whispercpp", "ggml-small.en-q8_0.bin"),
    },
    "moonshine-streaming-medium": {
        "gpu": ("hf_moonshine", "moonshine-ai/moonshine-streaming-medium"),
        "cpu": ("moonshine_voice", "medium-streaming"),
    },
    "moonshine-streaming-small": {
        "gpu": ("hf_moonshine", "moonshine-ai/moonshine-streaming-small"),
        "cpu": ("moonshine_voice", "small-streaming"),
    },
}


def gpu_sync():
    import torch

    torch.cuda.synchronize()


# ---------------------------------------------------------------- backends
# Each returns (transcribe(wav) -> str, sync(), info dict).


def load_nemo(device, name, att_context=None):
    import torch
    import nemo.collections.asr as nemo_asr
    from omegaconf import OmegaConf, open_dict

    # NeMo defaults TDT/RNNT greedy decoding to CUDA graphs, which need the NVIDIA driver; off on ROCm.
    cfg = nemo_asr.models.ASRModel.from_pretrained(name, return_config=True)
    with open_dict(cfg):
        cfg.decoding.greedy.use_cuda_graph_decoder = False
    override = CACHE / f"{name.replace('/', '__')}.yaml"
    override.parent.mkdir(parents=True, exist_ok=True)
    OmegaConf.save(cfg, override)
    model = nemo_asr.models.ASRModel.from_pretrained(name, override_config_path=str(override), map_location="cuda").eval()
    if att_context:  # cache-aware streaming model: full-utterance pass with the streaming attention window
        model.encoder.set_default_att_context_size(att_context)

    @torch.inference_mode()
    def transcribe(wav):
        out = model.transcribe([wav], batch_size=1, verbose=False)
        out = out[0] if isinstance(out, tuple) else out
        return out[0].text if hasattr(out[0], "text") else out[0]

    params = sum(p.numel() for p in model.parameters())
    return transcribe, gpu_sync, {"params_m": round(params / 1e6, 1), "precision": "fp32"}


def sherpa_dir(name):
    d = CACHE / "sherpa" / name
    if not d.exists():
        d.parent.mkdir(parents=True, exist_ok=True)
        tmp = d.parent / f"{name}.tar.bz2"
        urllib.request.urlretrieve(SHERPA_URL.format(name), tmp)
        with tarfile.open(tmp) as t:
            t.extractall(d.parent)
        tmp.unlink()
    return d


def pick(d, stem):
    """encoder.int8.onnx / encoder-epoch-99.int8.onnx etc."""
    (f,) = [p for p in d.glob(f"*{stem}*.onnx") if "int8" in p.name] or list(d.glob(f"*{stem}*.onnx"))
    return str(f)


def load_sherpa_offline(device, name):
    import sherpa_onnx

    d = sherpa_dir(name)
    tokens = str(d / "tokens.txt")
    if list(d.glob("*joiner*.onnx")):
        rec = sherpa_onnx.OfflineRecognizer.from_transducer(
            encoder=pick(d, "encoder"), decoder=pick(d, "decoder"), joiner=pick(d, "joiner"),
            tokens=tokens, num_threads=THREADS, model_type="nemo_transducer",
        )
    else:
        rec = sherpa_onnx.OfflineRecognizer.from_nemo_ctc(model=pick(d, "model"), tokens=tokens, num_threads=THREADS)

    def transcribe(wav):
        s = rec.create_stream()
        s.accept_waveform(16000, wav)
        rec.decode_stream(s)
        return s.result.text

    return transcribe, lambda: None, {"precision": "int8 onnx", "disk_mb": dir_mb(d)}


def load_sherpa_online(device, name):
    """Real streaming: feed 100 ms chunks, decode as frames become ready. Records tail latency
    (time from last audio chunk to final text), which is what the user waits for after they stop talking."""
    import sherpa_onnx

    d = sherpa_dir(name)
    rec = sherpa_onnx.OnlineRecognizer.from_transducer(
        encoder=pick(d, "encoder"), decoder=pick(d, "decoder"), joiner=pick(d, "joiner"),
        tokens=str(d / "tokens.txt"), num_threads=THREADS, model_type="nemo_transducer",
    )
    tails = []

    def transcribe(wav):
        s = rec.create_stream()
        for i in range(0, len(wav), 1600):
            s.accept_waveform(16000, wav[i : i + 1600])
            while rec.is_ready(s):
                rec.decode_stream(s)
        t = time.perf_counter()
        s.accept_waveform(16000, np.zeros(16000 // 2, dtype=np.float32))  # tail padding flushes the last chunk
        s.input_finished()
        while rec.is_ready(s):
            rec.decode_stream(s)
        text = rec.get_result(s)
        tails.append(time.perf_counter() - t)
        return text if isinstance(text, str) else text.text

    return transcribe, lambda: None, {"precision": "int8 onnx", "disk_mb": dir_mb(d), "tails": tails}


def load_whispercpp(device, fname):
    import requests
    from huggingface_hub import hf_hub_download

    path = hf_hub_download("ggerganov/whisper.cpp", fname)
    build = "build-hip" if device == "gpu" else "build-cpu"
    port = 8391 if device == "gpu" else 8392
    cmd = [str(WHISPER_CPP / build / "bin" / "whisper-server"), "-m", path, "-t", str(THREADS),
           "-l", "en", "-nt", "--port", str(port)]
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    url = f"http://127.0.0.1:{port}/inference"
    for _ in range(600):
        try:
            requests.get(f"http://127.0.0.1:{port}/", timeout=1)
            break
        except requests.ConnectionError:
            time.sleep(0.1)
    import atexit

    atexit.register(proc.terminate)

    def transcribe(wav):
        import io

        buf = io.BytesIO()
        sf.write(buf, wav, 16000, format="WAV", subtype="PCM_16")
        r = requests.post(url, files={"file": ("a.wav", buf.getvalue())}, data={"response_format": "json"})
        r.raise_for_status()
        return r.json()["text"]

    info = {"precision": "q8_0 ggml", "disk_mb": round(os.path.getsize(path) / 2**20),
            "server_pid": proc.pid}
    return transcribe, lambda: None, info


def load_hf_moonshine(device, name):
    import torch
    from transformers import AutoModelForSpeechSeq2Seq, AutoProcessor

    proc = AutoProcessor.from_pretrained(name)
    model = AutoModelForSpeechSeq2Seq.from_pretrained(name).to("cuda").eval()

    @torch.inference_mode()
    def transcribe(wav):
        inputs = proc(wav, sampling_rate=16000, return_tensors="pt").to("cuda")
        # moonshine's recommended cap: ~6.5 tokens per second of audio
        max_new = int(len(wav) / 16000 * 6.5) + 10
        ids = model.generate(**inputs, max_new_tokens=max_new)
        return proc.batch_decode(ids, skip_special_tokens=True)[0]

    params = sum(p.numel() for p in model.parameters())
    return transcribe, gpu_sync, {"params_m": round(params / 1e6, 1), "precision": "fp32"}


def load_moonshine_voice(device, arch):
    """moonshine-voice C++/onnxruntime runtime (the one its iOS package ships), whole-utterance decode.
    Calls the C API directly: the Python wrapper copies audio through a Python list, which would inflate latency."""
    import ctypes

    from moonshine_voice import Transcriber, get_model_for_language
    from moonshine_voice.errors import check_error
    from moonshine_voice.moonshine_api import TranscriptC, string_to_model_arch

    path, model_arch = get_model_for_language("en", string_to_model_arch(arch))
    t = Transcriber(path, model_arch)

    def transcribe(wav):
        wav = np.ascontiguousarray(wav, dtype=np.float32)
        out = ctypes.POINTER(TranscriptC)()
        check_error(t._lib.moonshine_transcribe_without_streaming(
            t._handle, wav.ctypes.data_as(ctypes.POINTER(ctypes.c_float)), len(wav), 16000, 0, ctypes.byref(out)))
        return " ".join(line.text for line in t._parse_transcript(out).lines)

    return transcribe, lambda: None, {"precision": "quantized ort", "disk_mb": dir_mb(path)}


BACKENDS = {
    "nemo": load_nemo,
    "moonshine_voice": load_moonshine_voice,
    "sherpa_offline": load_sherpa_offline,
    "sherpa_online": load_sherpa_online,
    "whispercpp": load_whispercpp,
    "hf_moonshine": load_hf_moonshine,
}

# ---------------------------------------------------------------- measurement


def dir_mb(d):
    return round(sum(p.stat().st_size for p in Path(d).rglob("*") if p.is_file()) / 2**20)


def load_set(name):
    return [json.loads(line) for line in open(ROOT / "sets" / f"{name}.jsonl")]


def read(path):
    wav, sr = sf.read(ROOT / path, dtype="float32")
    assert sr == 16000
    return wav


def timed(transcribe, sync, wav):
    t = time.perf_counter()
    text = transcribe(wav)
    sync()
    return text, time.perf_counter() - t


def peak_rss_mb(info):
    """Peak RSS of this process, or of the whisper-server child if there is one."""
    pid = info.pop("server_pid", None)
    if pid:
        for line in open(f"/proc/{pid}/status"):
            if line.startswith("VmHWM"):
                return round(int(line.split()[1]) / 1024)
    return round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024)


def main(model, device):
    backend, *args = MODELS[model][device]
    if device == "cpu":
        import torch

        torch.set_num_threads(THREADS)

    t0 = time.perf_counter()
    transcribe, sync, info = BACKENDS[backend](device, *args)
    load_s = time.perf_counter() - t0
    tails = info.pop("tails", None)

    clips = json.loads((ROOT / "sets" / "clips.json").read_text())
    clip_wavs = {k: read(v["audio"]) for k, v in clips.items()}
    for _ in range(3):  # warmup (kernel compile, allocator, caches)
        timed(transcribe, sync, clip_wavs["clip5"])

    latency = {}
    for k, wav in clip_wavs.items():
        runs = []
        for _ in range(5):
            if tails is not None:
                tails.clear()
            _, dt = timed(transcribe, sync, wav)
            runs.append(tails[-1] if tails is not None else dt)
            if tails is not None:
                latency[f"{k}_total_s"] = round(dt, 4)
        latency[f"{k}_s"] = round(median(runs), 4)

    norm = EnglishTextNormalizer()
    results = {}
    for name in SETS:
        hyps, refs, rows, proc_s, audio_s = [], [], [], 0.0, 0.0
        for utt in load_set(name):
            wav = read(utt["audio"])
            text, dt = timed(transcribe, sync, wav)
            proc_s += dt
            audio_s += len(wav) / 16000
            rows.append({"id": utt["id"], "hyp": text, "s": round(dt, 4)})
            ref = norm(utt["text"])
            if ref.strip():
                refs.append(ref)
                hyps.append(norm(text))
        wer = jiwer.wer(refs, hyps)
        results[name] = {"wer": round(100 * wer, 2), "rtf": round(proc_s / audio_s, 4), "proc_s": round(proc_s, 2),
                         "audio_s": round(audio_s, 2), "n": len(refs), "hyps": rows}
        print(f"{model} {device} {name}: WER {100 * wer:.2f}%  RTF {proc_s / audio_s:.4f}", flush=True)

    mem = {"peak_rss_mb": peak_rss_mb(info)}
    if device == "gpu" and backend in ("nemo", "hf_moonshine"):
        import torch

        mem["gpu_peak_alloc_mb"] = round(torch.cuda.max_memory_allocated() / 2**20)

    out = {"model": model, "device": device, "backend": backend, "args": args, "threads": THREADS if device == "cpu" else None,
           "load_s": round(load_s, 1), **info, **mem, "latency": latency, "sets": results,
           "date": time.strftime("%Y-%m-%d %H:%M")}
    (ROOT / "results").mkdir(exist_ok=True)
    (ROOT / "results" / f"{model}__{device}.json").write_text(json.dumps(out, indent=1) + "\n")
    print(json.dumps({k: v for k, v in out.items() if k != "sets"}), flush=True)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
