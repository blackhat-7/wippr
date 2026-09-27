### Accuracy (WER %, Whisper English normalizer; 200 utts per set)

| model | runtime | ls-clean | ls-other | ami | earnings22 | mean |
|---|---|---|---|---|---|---|
| parakeet-tdt-0.6b-v2 | gpu: nemo fp32 | 1.13 | 2.82 | 8.71 | 10.30 | 5.74 |
| parakeet-tdt-0.6b-v2 | cpu: sherpa_offline int8 onnx | 1.08 | 2.93 | 8.46 | 10.90 | 5.84 |
| parakeet-tdt-0.6b-v3 | gpu: nemo fp32 | 1.49 | 3.72 | 9.39 | 11.18 | 6.45 |
| parakeet-tdt-0.6b-v3 | cpu: sherpa_offline int8 onnx | 1.65 | 4.57 | 10.35 | 13.84 | 7.60 |
| parakeet-unified-en-0.6b | gpu: nemo fp32 | 1.15 | 3.13 | 7.37 | 10.24 | 5.47 |
| parakeet-tdt_ctc-110m | gpu: nemo fp32 | 1.73 | 5.44 | 12.71 | 11.06 | 7.74 |
| nemotron-streaming-en-0.6b | gpu: nemo fp32 | 1.57 | 5.33 | 8.80 | 12.89 | 7.15 |
| whisper-large-v3-turbo | gpu: whispercpp q8_0 ggml | 1.42 | 3.72 | 12.63 | 11.31 | 7.27 |
| whisper-small.en | gpu: whispercpp q8_0 ggml | 2.26 | 6.40 | 15.91 | 12.23 | 9.20 |
| whisper-small.en | cpu: whispercpp q8_0 ggml | 2.20 | 6.37 | 15.70 | 12.20 | 9.12 |
| moonshine-streaming-medium | gpu: hf_moonshine fp32 | 1.39 | 4.90 | 9.30 | 11.82 | 6.85 |
| moonshine-streaming-medium | cpu: moonshine_voice quantized ort | 3.65 | 8.43 | 16.20 | 15.92 | 11.05 |
| moonshine-streaming-small | gpu: hf_moonshine fp32 | 1.52 | 6.88 | 10.52 | 13.05 | 7.99 |
| moonshine-streaming-small | cpu: moonshine_voice quantized ort | 4.38 | 10.88 | 18.98 | 16.81 | 12.76 |

### Speed (batch 1; RTF = compute time / audio time, lower is better)

| model | GPU RTF | GPU 5s clip ms | GPU 15s clip ms | CPU-4t RTF | CPU-4t 5s clip ms | CPU-4t 15s clip ms | CPU peak RSS MB | GPU peak alloc MB | CPU model on disk MB |
|---|---|---|---|---|---|---|---|---|---|
| parakeet-tdt-0.6b-v2 | 0.0112 | 47 | 108 | 0.1444 | 843 | 1133 | 2040 | 4956 | 631 |
| parakeet-tdt-0.6b-v3 | 0.0110 | 46 | 104 | 0.1565 | 1403 | 1346 | 2068 | 5026 | 640 |
| parakeet-unified-en-0.6b | 0.0215 | 59 | 129 | – | – | – | – | 4960 | – |
| parakeet-tdt_ctc-110m | 0.0142 | 27 | 75 | – | – | – | – | 1035 | – |
| nemotron-streaming-en-0.6b | 0.0195 | 54 | 126 | – | – | – | – | 5015 | – |
| whisper-large-v3-turbo | 0.0205 | 117 | 186 | – | – | – | – | – | – |
| whisper-small.en | 0.0162 | 97 | 234 | 0.2718 | 1729 | 2012 | 576 | – | 252 |
| moonshine-streaming-medium | 0.0729 | 129 | 513 | 0.3195 | 1302 | 4062 | 1788 | 1135 | 257 |
| moonshine-streaming-small | 0.0545 | 99 | 372 | 0.1882 | 938 | 2771 | 1441 | 623 | 136 |
