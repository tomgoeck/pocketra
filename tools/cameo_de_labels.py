#!/usr/bin/env python3

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_volkicon import encode_shp
from rafmt import ContentSet, NameDatabase, ShpFile, load_palette

ROOT = Path(__file__).resolve().parent.parent
DB = Path(__file__).resolve().parent / "rafmt" / "global_mix_database.dat"

W, H = 64, 48
TEXT_ROWS = range(41, 47)
BASE_ROW = 42
WHITE = 15
BLACK = 12
MARGIN = 1
SPACE_W = 4


GROUND_TRUTH = {
    "1tnkicon": "LEICHTER PANZER", "2tnkicon": "KAMPFPANZER", "3tnkicon": "SCHWERER PANZER",
    "4tnkicon": "MAMMUTPANZER", "afldicon": "FLUGFELD", "agunicon": "FLAK", "apcicon": "BMT",
    "apwricon": "GROSSKRAFTWERK", "artyicon": "ARTILLERIE", "atekicon": "TECH-ZENTRUM",
    "atomicon": "ATOMBOMBE", "barricon": "CYBORG-FABRIK", "brikicon": "BETONMAUER",
    "caicon": "KREUZER", "camicon": "SPIONAGEFLUGZEUG", "ddicon": "ZERSTÖRER",
    "dogicon": "WACHHUND", "domeicon": "RADAR", "domficon": "RADAR", "e1icon": "SCHÜTZE",
    "e2icon": "GRENADIER", "e4icon": "FLAMMENWERFER", "e6icon": "INVASOR", "e7icon": "TANYA",
    "facficon": "BAUHOF", "facticon": "BAUHOF", "fencicon": "STACHELDRAHTZAUN",
    "fixicon": "WERKSTATT", "fturicon": "FLAMMENTURM", "gapicon": "SCHATTEN-GEN.",
    "gunicon": "GESCHÜTZTURM", "harvicon": "ERZTRANSPORTER", "hboxicon": "TARNBUNKER",
    "heliicon": "HELIKOPTER", "hindicon": "HIND", "hpadicon": "HELIPORT",
    "infxicon": "UNVERWUNDBAR", "ironicon": "EISERNER VORHANG", "jeepicon": "RANGER",
    "kennicon": "ZWINGER", "lsticon": "TRANSPORTER", "mcvicon": "MBF", "mediicon": "MECHANOBOT",
    "mggicon": "MOB.SCHATTENGEN.", "migicon": "MIG-JAGDBOMBER", "mrjicon": "RADARSTÖRGERÄT",
    "msloicon": "RAKETENSILO", "pbmbicon": "FALLSCHIRMBOMBEN", "pboxicon": "BUNKER",
    "pdoxicon": "CHRONOSPHÄRE", "pinficon": "FALLSCHIRMJÄGER", "powricon": "KRAFTWERK",
    "procicon": "ERZRAFFINERIE", "pticon": "KANONENBOOT", "samicon": "FLARAK",
    "sbagicon": "SANDSACK.BARRIERE", "siloicon": "ERZSILO", "smigicon": "SPIONAGEFLUGZEUG",
    "sonricon": "SONAR", "spyicon": "SPION", "ssicon": "U-BOOT", "stekicon": "TECH-ZENTRUM",
    "syrdicon": "WERFT", "syrficon": "WERFT", "tenticon": "CYBORG-FABRIK", "thficon": "DIEB",
    "tranicon": "HELITRANS", "tslaicon": "TESLASPULE", "warpicon": "CHRONOPORT",
    "weaficon": "WAFFENFABRIK", "weapicon": "WAFFENFABRIK", "yakicon": "YAK-ANGRIFFSJÄGER",
}


TARGETS = [
    ("ctnkicon",  "CHRONOPANZER",    "ctnk — Chronopanzer"),
    ("dtrkicon",  "DYNAMIT-LKW",     "dtrk — Dynamit-Lkw"),
    ("ftrkicon",  "FLAKPANZER",      "ftrk — Flakpanzer"),
    ("mechicon",  "MECHANIKER",      "mech — Mechaniker"),
    ("mh60icon",  "BLACK HAWK",      "mh60 — Black Hawk"),
    ("msloicon2", "RAKETENSILO",     "mslo/mslf — Raketensilo"),
    ("mslficon",  "RAKETENSILO",     "mslf — Raketensilo (Attrappe)"),
    ("msubicon",  "RAKETEN-U-BOOT",  "msub — Raketen-U-Boot"),
    ("qtnkicon",  "MAD-PANZER",      "qtnk — MAD-Panzer"),
    ("shokicon",  "SCHOCKTRUPPE",    "shok — Schocktruppe"),
    ("stnkicon",  "PHASEN-PANZER",   "stnk — Phasen-Panzer"),
    ("trukicon",  "VERSORGUNGS-LKW", "truk — Versorgungs-Lkw"),
    ("ttnkicon",  "TESLA-PANZER",    "ttnk — Tesla-Panzer"),
    ("volkicon",  "VOLKOV",          "volk — Volkov", 37),
]


def _glyph_columns(frame: bytes) -> list[tuple]:

    return [tuple(1 if frame[row * W + x] == WHITE else 0 for row in TEXT_ROWS)
            for x in range(MARGIN, W - MARGIN)]


def _segment(cols: list[tuple]) -> list[tuple[int, tuple]]:

    out: list[tuple[int, tuple]] = []
    cur: list[tuple] = []
    start = 0
    for i, col in enumerate(cols + [(0,) * len(TEXT_ROWS)]):
        if any(col):
            if not cur:
                start = i
            cur.append(col)
        elif cur:
            out.append((start, tuple(cur)))
            cur = []
    return out


def build_font(cs_de: ContentSet) -> tuple[dict[str, list[tuple]], int]:

    variants: dict[str, set[tuple]] = {}
    used = 0
    for name, text in GROUND_TRUTH.items():
        try:
            raw = cs_de.read(name + ".shp")
        except KeyError:
            continue
        shp = ShpFile(raw)
        if (shp.width, shp.height) != (W, H):
            continue
        glyphs = [g for _, g in _segment(_glyph_columns(shp.frames[0]))]
        letters = text.replace(" ", "")
        if len(glyphs) != len(letters):
            continue
        used += 1
        for ch, g in zip(letters, glyphs):
            variants.setdefault(ch, set()).add(g)
    if not used:
        raise SystemExit("Schrift nicht lesbar: keine deutschen Cameos gefunden")
    return {ch: sorted(v, key=len) for ch, v in variants.items()}, used


def layout(text: str, font: dict[str, list[tuple]], widest: bool) -> list[tuple[int, tuple]] | None:

    out: list[tuple[int, tuple]] = []
    x = 0
    for ch in text:
        if ch == " ":
            x += SPACE_W
            continue
        vs = font.get(ch)
        if not vs:
            return None
        g = vs[-1] if widest else vs[0]
        out.append((x, g))
        x += len(g) + 1
    total = x - 1
    if total > W - 2 * MARGIN:
        return None
    off = MARGIN + (W - 2 * MARGIN - total) // 2
    return [(px + off, g) for px, g in out]


def relabel(frame: bytes, text: str, font: dict[str, list[tuple]],
            clear_from: int | None = None) -> bytes:

    plan = layout(text, font, widest=True) or layout(text, font, widest=False)
    if plan is None:
        raise SystemExit(f'„{text}“ passt nicht in {W - 2 * MARGIN} Pixel oder nutzt fremde Zeichen')
    out = bytearray(frame)
    for row in range(clear_from if clear_from is not None else TEXT_ROWS[0], TEXT_ROWS[-1] + 1):
        for x in range(MARGIN, W - MARGIN):
            if clear_from is not None or out[row * W + x] == WHITE:
                out[row * W + x] = BLACK
    for x0, g in plan:
        for dx, col in enumerate(g):
            for dy, on in enumerate(col):
                if on:
                    out[(TEXT_ROWS[0] + dy) * W + x0 + dx] = WHITE
    return bytes(out)


def read_icon(cs: ContentSet, name: str) -> bytes | None:

    try:
        return cs.read(name)
    except KeyError:
        pass
    for d in (ROOT / "reference" / "OpenRA" / "mods" / "ra" / "bits", ROOT / "game" / "data" / "bits"):
        p = d / name
        if p.is_file():
            return p.read_bytes()
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--content", type=Path, default=ROOT / "content" / "ra")
    ap.add_argument("--content-de", type=Path, default=ROOT / "content" / "ra_de")
    ap.add_argument("-o", "--out", type=Path, default=ROOT / "build" / "cameos_de")
    ap.add_argument("--preview", type=Path, default=None,
                    help="Kontaktbogen (englisch/deutsch, 4-fach) schreiben — braucht Pillow")
    a = ap.parse_args()

    if not a.content_de.is_dir():
        print(f"keine deutsche CD unter {a.content_de} — nichts zu tun", file=sys.stderr)
        return 0
    names = NameDatabase(DB)
    cs_de = ContentSet(a.content_de, names)
    cs = ContentSet(a.content, names)

    font, used = build_font(cs_de)
    print(f"Schrift: {len(font)} Zeichen aus {used} deutschen Cameos "
          f"({sum(len(v) for v in font.values())} Glyphen)")

    a.out.mkdir(parents=True, exist_ok=True)
    made: list[tuple[str, bytes, bytes]] = []
    for stem, text, _label, *rest in TARGETS:
        raw = read_icon(cs, stem + ".shp")
        if raw is None:
            print(f"  {stem}: Vorlage fehlt — übersprungen", file=sys.stderr)
            continue
        shp = ShpFile(raw)
        if (shp.width, shp.height) != (W, H):
            print(f"  {stem}: {shp.width}×{shp.height} statt {W}×{H} — übersprungen", file=sys.stderr)
            continue
        new = relabel(shp.frames[0], text, font, rest[0] if rest else None)
        out = a.out / f"{stem}.shp"
        out.write_bytes(encode_shp(W, H, new))
        made.append((stem, shp.frames[0], new))
        print(f"  {stem}: {text}")
    print(f"{len(made)} deutsche Cameos in {a.out}")

    if a.preview and made:
        write_preview(a.preview, made, cs_de)
    return 0


def write_preview(path: Path, made: list[tuple[str, bytes, bytes]], cs: ContentSet) -> None:
    from PIL import Image, ImageDraw

    pal = load_palette(cs.read("temperat.pal"))
    scale, pad, head = 4, 8, 18
    cw, ch = W * scale, H * scale

    def img(frame: bytes) -> Image.Image:
        im = Image.new("RGB", (W, H))
        im.putdata([tuple(pal[i][:3]) for i in frame])
        return im.resize((cw, ch), Image.NEAREST)

    label = {t[0]: t[2] for t in TARGETS}
    sheet = Image.new("RGB", (pad * 3 + cw * 2, head + len(made) * (ch + head + pad) + pad), (18, 18, 18))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 4), "Cameos der Erweiterung: englisch (links) / neu deutsch (rechts)", fill=(230, 230, 230))
    y = head + pad
    for stem, old, new in made:
        d.text((pad, y - 13), label.get(stem, stem), fill=(240, 210, 120))
        sheet.paste(img(old), (pad, y))
        sheet.paste(img(new), (pad * 2 + cw, y))
        y += ch + head + pad
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)
    print(f"Kontaktbogen: {path}")


if __name__ == "__main__":
    sys.exit(main())
