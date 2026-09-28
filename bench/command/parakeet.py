# uv run --with parakeet-mlx python parakeet.py — transcribes every benchmark clip with Parakeet TDT 0.6B v2 (MLX) into .build/heard/parakeet/<clip>.txt.
import pathlib
from parakeet_mlx import from_pretrained
here = pathlib.Path(__file__).parent
out = here / ".build/heard/parakeet"; out.mkdir(parents=True, exist_ok=True)
model = from_pretrained("mlx-community/parakeet-tdt-0.6b-v2")
for wav in sorted((here / "audio").glob("*.wav")):
    target = out / (wav.stem + ".txt")
    if not target.exists():
        try:
            text = model.transcribe(str(wav)).text.strip()
        except ValueError:  # too short to analyse
            text = ""
        target.write_text(text)
print(len(list(out.glob("*.txt"))), "transcripts")
