#!/usr/bin/env python3

import argparse, csv, difflib, os, re, sys, time

import torch, torchaudio as ta

if torch.backends.mps.is_available():
    DEVICE = "mps"
    _load = torch.load

    def _patched(*a, **k):
        k.setdefault("map_location", torch.device("mps"))
        return _load(*a, **k)
    torch.load = _patched
else:
    DEVICE = "cpu"

import perth
if perth.PerthImplicitWatermarker is None:
    class _NoWatermark:
        def apply_watermark(self, wav, sample_rate=None, **k):
            return wav
    perth.PerthImplicitWatermarker = _NoWatermark
from chatterbox.mtl_tts import ChatterboxMultilingualTTS


def normalize(text: str, subst: list[tuple[str, str]]) -> str:
    text = re.sub(r"\s*\([^)]*\)", "", text)
    text = text.replace("„", '"').replace("“", '"').replace("”", '"')
    text = text.replace(" — ", ", ").replace("—", ",").replace(" – ", ", ")
    for a, b in subst:
        text = re.sub(rf"\b{re.escape(a)}\b", b, text)
    return re.sub(r"\s+", " ", text).strip()


def chunks(text: str, limit: int) -> list[str]:
    sents = re.split(r"(?<=[.!?:;])\s+", text)
    out, cur = [], ""
    for s in sents:
        if cur and len(cur) + 1 + len(s) > limit:
            out.append(cur)
            cur = s
        else:
            cur = f"{cur} {s}".strip()
    if cur:
        out.append(cur)
    return out


def wer(ref: str, hyp: str) -> float:
    norm = lambda s: re.sub(r"[^\wäöüß ]", "", s.lower()).split()
    r, h = norm(ref), norm(hyp)
    sm = difflib.SequenceMatcher(a=r, b=h)
    return 1 - sm.ratio() if r else 0.0


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lang", choices=["de", "en"], required=True)
    ap.add_argument("--ref", required=True, help="Referenz-WAV (tools/tts_ref.py)")
    ap.add_argument("--out", required=True, help="Zielordner")
    ap.add_argument("--csv", help="key,text-Datei")
    ap.add_argument("--text", nargs=2, metavar=("KEY", "TEXT"), action="append", default=[])
    ap.add_argument("--only", nargs="*", default=None, help="nur diese Schlüssel")
    ap.add_argument("--subst", action="append", default=[], help="FROM=TO, mehrfach")
    ap.add_argument("--chunk", type=int, default=250)
    ap.add_argument("--exaggeration", type=float, default=0.5)
    ap.add_argument("--cfg", type=float, default=0.5)
    ap.add_argument("--temperature", type=float, default=0.8)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--skip-existing", action="store_true")
    ap.add_argument("--verify", action="store_true", help="Whisper-Gegenprobe")
    ap.add_argument("--retries", type=int, default=3,
                    help="mit --verify: bei WER > 15 %% bis zu N weitere Seeds probieren, bestes Ergebnis behalten")
    a = ap.parse_args()

    items: list[tuple[str, str]] = list(a.text)
    if a.csv:
        with open(a.csv, encoding="utf-8", newline="") as f:
            rows = list(csv.reader(f))
        items += [(r[0], r[1]) for r in rows[1:] if len(r) >= 2 and r[0]]
    if a.only is not None:
        items = [it for it in items if it[0] in a.only]
    if not items:
        sys.exit("nichts zu tun (--csv oder --text)")
    subst = [tuple(s.split("=", 1)) for s in a.subst]
    os.makedirs(a.out, exist_ok=True)

    t0 = time.time()
    model = ChatterboxMultilingualTTS.from_pretrained(device=DEVICE)
    print(f"Modell auf {DEVICE} in {time.time() - t0:.0f} s geladen", flush=True)
    whisper = None
    if a.verify:
        from faster_whisper import WhisperModel
        whisper = WhisperModel("large-v3", device="cpu", compute_type="int8")

    gap = torch.zeros(1, int(0.3 * model.sr))

    def synth(text: str, seed: int) -> torch.Tensor:
        parts = []
        for piece in chunks(text, a.chunk):
            torch.manual_seed(seed)
            parts.append(model.generate(piece, language_id=a.lang, audio_prompt_path=a.ref,
                                        exaggeration=a.exaggeration, cfg_weight=a.cfg,
                                        temperature=a.temperature).cpu())
        return parts[0] if len(parts) == 1 else torch.cat(sum(([p, gap] for p in parts), [])[:-1], dim=1)

    def check(path: str, text: str) -> tuple[float, str]:
        segs, _ = whisper.transcribe(path, language=a.lang, beam_size=5)
        hyp = " ".join(s.text.strip() for s in segs)
        return wer(text, hyp), hyp

    for key, raw in items:
        out = os.path.join(a.out, f"{key}.wav")
        if a.skip_existing and os.path.exists(out):
            continue
        text = normalize(raw, subst)
        t0 = time.time()
        best = None
        for attempt in range(1 + (a.retries if whisper else 0)):
            seed = a.seed + attempt
            wav = synth(text, seed)
            ta.save(out, wav, model.sr)
            if not whisper:
                best = (0.0, "", wav, seed)
                break
            w, hyp = check(out, text)
            if best is None or w < best[0]:
                best = (w, hyp, wav, seed)
            if w <= 0.15:
                break
        w, hyp, wav, seed = best
        ta.save(out, wav, model.sr)
        msg = f"OK {out}  {wav.shape[-1] / model.sr:.1f} s  ({time.time() - t0:.0f} s, Seed {seed})"
        if whisper:
            msg += f"  WER {w:.0%}" + (f"\n   SOLL: {text}\n   IST:  {hyp}" if w > 0.15 else "")
        print(msg, flush=True)


if __name__ == "__main__":
    main()
