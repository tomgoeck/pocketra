#!/usr/bin/env python3

import argparse, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

EVA = """10minr 1minr 1objmet1 20minr 2minr 2objmet1 30minr 3minr 3objmet1 40minr 4minr 5minr
aappro1 aarive1 aarrive1 aarrivn1 aarrivs1 aarrivw1 aavail1 abldgin1 afallen1 alaunch1 aprep1
aready1 armorup1 aselect1 atlnch1 atprep1 aunitl1 baseatk1 bldginf1 bldgprg1 cancld1 chrochr1
chrordy1 chroyes1 cmdcntr1 cntlded1 conscmp1 convlst1 convyap1 enmyapp1 firepo1 flare1 flaree1
flaren1 flares1 flarew1 ironchg1 ironrdy1 load1 lopower1 misnlst1 misnwon1 mtimein1 navylst1
newopt1 nobuild1 nodeply1 nofunds1 nopowr1 objmet1 objnmet1 objnrch1 objrch1 onhold1 opterm1
pribldg1 progres1 pulse1 reinfor1 repair1 satlnch1 save1 silond1 slcttgt1 sovefal1 sovemp1
sovfapp1 sovforc1 sovrein1 spypln1 strckil1 strucap1 strusld1 targfre1 targres1 timergo1
timerno1 train1 unitful1 unitlst1 unitrdy1 unitrep1 unitsld1 unitspd1 xploplc1""".split()

CLASSIC_FIRST = "conscmp1 newopt1 unitrdy1 bldginf1 lopower1 baseatk1 reinfor1 progres1".split()


def build(lang: str, out: str, first: list[str], only: bool) -> None:
    d = os.path.join(ROOT, "game", "assets", "sfx", "de" if lang == "de" else "")
    clips = list(first)
    if not only:
        clips += [c for c in EVA if c not in clips]
    clips = [c for c in clips if os.path.exists(os.path.join(d, c + ".wav"))]
    if not clips:
        sys.exit(f"keine Clips in {d}")
    args = ["ffmpeg", "-v", "error", "-y"]
    fc = ""
    for i, c in enumerate(clips):
        args += ["-i", os.path.join(d, c + ".wav")]
        fc += f"[{i}:a]apad=pad_dur=0.25[p{i}];"
    fc += "".join(f"[p{i}]" for i in range(len(clips)))
    fc += f"concat=n={len(clips)}:v=0:a=1,afftdn=nf=-30,loudnorm=I=-18:TP=-1.5,aresample=24000"
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    subprocess.run(args + ["-filter_complex", fc, "-ac", "1", out], check=True)
    dur = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "csv=p=0", out], capture_output=True, text=True).stdout.strip()
    print(f"{out}: {len(clips)} Clips, {float(dur):.1f} s")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lang", choices=["de", "en"], required=True)
    ap.add_argument("out")
    ap.add_argument("--first", nargs="+", default=CLASSIC_FIRST, help="Clips, die vorne stehen")
    ap.add_argument("--only", action="store_true", help="nur --first, nicht alle EVA-Clips anhängen")
    a = ap.parse_args()
    build(a.lang, a.out, a.first, a.only)
