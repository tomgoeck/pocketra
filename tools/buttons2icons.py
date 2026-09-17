#!/usr/bin/env python3

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

DEFAULT_SRC = Path(__file__).resolve().parent.parent / "design" / "app" / "buttons"
DEFAULT_OUT = Path(__file__).resolve().parent.parent / "game" / "icons" / "ui"
FFMPEG = "/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg"


FRAME_SPECS = {
    "panel_frame.png": {"width": 512, "bg_remove": False},
    "plate_empty.png": {"width": 192, "bg_remove": True},
}


def _has_real_alpha(img) -> bool:
    if img.mode != "RGBA":
        return False
    return img.getchannel("A").getextrema()[0] < 255


def _remove_flat_background(img, thresh: int, blur: float, erode: int):

    from PIL import Image, ImageChops, ImageDraw, ImageFilter
    img = img.convert("RGBA")
    w, h = img.size
    work = img.convert("RGB")
    mark = (1, 254, 13)
    for xy in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        ImageDraw.floodfill(work, xy, mark, thresh=thresh)
    diff = ImageChops.difference(work, Image.new("RGB", (w, h), mark)).convert("L")
    alpha = diff.point(lambda p: 0 if p == 0 else 255)
    if erode > 0:
        eroded = alpha.filter(ImageFilter.MinFilter(erode))
        fill_val = 254
        comp = eroded.copy()
        ImageDraw.floodfill(comp, (w // 2, h // 2), fill_val, thresh=0)
        comp = comp.point(lambda p: 255 if p == fill_val else 0).filter(ImageFilter.MaxFilter(erode))
        alpha = ImageChops.multiply(alpha, comp)
    if blur > 0:
        alpha = alpha.filter(ImageFilter.GaussianBlur(blur))
    img.putalpha(alpha)
    return img


def _recenter_to_bbox(img, pad_frac: float):
    from PIL import Image
    bbox = img.getchannel("A").getbbox()
    if bbox is None:
        return img
    cropped = img.crop(bbox)
    side = max(cropped.size)
    pad = max(1, round(side * pad_frac))
    canvas_side = side + 2 * pad
    canvas = Image.new("RGBA", (canvas_side, canvas_side), (0, 0, 0, 0))
    canvas.paste(cropped, ((canvas_side - cropped.width) // 2, (canvas_side - cropped.height) // 2), cropped)
    return canvas


def _punch_up(img, gamma: float, sat_mult: float):
    from PIL import Image
    if gamma == 1.0 and sat_mult == 1.0:
        return img
    alpha = img.getchannel("A")
    hsv = img.convert("RGB").convert("HSV")
    h, s, v = hsv.split()
    if sat_mult != 1.0:
        s = s.point(lambda p: max(0, min(255, round(p * sat_mult))))
    if gamma != 1.0:
        v = v.point(lambda p: max(0, min(255, round(255.0 * (p / 255.0) ** gamma))))
    rgb = Image.merge("HSV", (h, s, v)).convert("RGB")
    rgb.putalpha(alpha)
    return rgb


def convert_pillow(src: Path, dst: Path, size: int, thresh: int, blur: float, erode: int,
                    pad_frac: float = 0.06, gamma: float = 1.15, sat_mult: float = 1.12) -> None:
    from PIL import Image
    with Image.open(src) as raw:
        img = raw.convert("RGBA")
        if not _has_real_alpha(img):
            img = _remove_flat_background(img, thresh, blur, erode)
        img = _recenter_to_bbox(img, pad_frac)
        img = _punch_up(img, gamma, sat_mult)
        img = img.resize((size, size), Image.LANCZOS)
        img.save(dst)


def convert_frame_pillow(src: Path, dst: Path, target_w: int, bg_remove: bool,
                          thresh: int, blur: float, erode: int) -> None:
    from PIL import Image
    with Image.open(src) as raw:
        img = raw.convert("RGBA")
        if bg_remove and not _has_real_alpha(img):
            img = _remove_flat_background(img, thresh, blur, erode)
        w, h = img.size
        target_h = max(1, round(h * target_w / w))
        img = img.resize((target_w, target_h), Image.LANCZOS)
        img.save(dst)


def convert_ffmpeg(ffmpeg: str, src: Path, dst: Path, size: int) -> None:


    probe = subprocess.run([ffmpeg, "-loglevel", "error", "-i", str(src), "-vf", "crop=1:1:0:0",
                             "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True, check=True)
    r, g, b = probe.stdout[0:3]
    subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-i", str(src),
                     "-vf", f"colorkey=0x{r:02x}{g:02x}{b:02x}:0.12:0.06,scale={size}:{size}:flags=lanczos",
                     str(dst)], check=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", type=Path, default=DEFAULT_SRC)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--size", type=int, default=192)
    ap.add_argument("--bg-thresh", type=int, default=26, help="Flutfüllung: Farbtoleranz gegen die Eckfarbe")
    ap.add_argument("--bg-blur", type=float, default=1.5, help="Weichzeichner-Radius der Alphamaske (0 = aus)")
    ap.add_argument("--bg-erode", type=int, default=41,
                     help="Öffnungsradius (ungerade) gegen isolierte Hintergrundflecken, 0 = aus")
    ap.add_argument("--plate-pad", type=float, default=0.06,
                     help="Rand um die freigestellte Platte nach dem Zuschnitt auf die Bounding-Box, "
                          "als Anteil der Plattenseite (einheitliche Knopfgröße, Toms Handtest 2026-09-04)")
    ap.add_argument("--gamma", type=float, default=1.15,
                     help="Gamma > 1 dunkelt die Mitten ab, Schwarz/Weiß bleiben fest (Gold-Symbol kaum betroffen)")
    ap.add_argument("--saturation", type=float, default=1.12, help="Sättigungsfaktor (1 = unverändert)")
    a = ap.parse_args()

    pngs = sorted(a.src.glob("*.png"))
    if not pngs:
        print(f"Keine PNGs in {a.src}", file=sys.stderr)
        return 1
    frame_pngs = [p for p in pngs if p.name in FRAME_SPECS]
    pngs = [p for p in pngs if p.name not in FRAME_SPECS]

    have_pillow = True
    try:
        import PIL
    except ImportError:
        have_pillow = False
    ffmpeg = shutil.which(FFMPEG) or (FFMPEG if Path(FFMPEG).exists() else shutil.which("ffmpeg"))
    if not have_pillow and not ffmpeg:
        print("Weder Pillow noch ffmpeg gefunden — python3 -m pip install pillow oder ffmpeg-full installieren",
              file=sys.stderr)
        return 2
    if not have_pillow:
        print("Pillow fehlt — weiche auf ffmpeg aus (gröberes Freistellen, nur Eckfarbe statt Flutfüllung)",
              file=sys.stderr)

    a.out.mkdir(parents=True, exist_ok=True)
    for src in frame_pngs:
        spec = FRAME_SPECS[src.name]
        dst = a.out / src.name
        if not have_pillow:
            print(f"{src.name}: übersprungen (Rahmen/Platte brauchen Pillow für die Freistellung)", file=sys.stderr)
            continue
        convert_frame_pillow(src, dst, spec["width"], spec["bg_remove"], a.bg_thresh, a.bg_blur, a.bg_erode)
        print(f"{src.name} -> {dst.relative_to(a.out.parent.parent.parent)} (Breite {spec['width']}, Seitenverhältnis erhalten)")
    for src in pngs:
        dst = a.out / f"btn_{src.stem}.png"
        if have_pillow:
            convert_pillow(src, dst, a.size, a.bg_thresh, a.bg_blur, a.bg_erode,
                           a.plate_pad, a.gamma, a.saturation)
        else:
            convert_ffmpeg(ffmpeg, src, dst, a.size)
        print(f"{src.name} -> {dst.relative_to(a.out.parent.parent.parent)} ({a.size}x{a.size}, "
              f"{'Pillow' if have_pillow else 'ffmpeg'})")
    print(f"{len(pngs) + len(frame_pngs)} Knopfbild(er) geschrieben.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
