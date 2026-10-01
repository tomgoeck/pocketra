#!/usr/bin/env python3

import csv
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TUTORIAL_GD = os.path.join(ROOT, "game", "scripts", "missions", "tutorial.gd")
DE_CSV = os.path.join(ROOT, "game", "i18n", "missions_tutorial_de.csv")
EN_FTL = os.path.join(ROOT, "tools", "maps_extra", "tutorial", "map.ftl")
OUT_DIR = os.path.join(ROOT, "build", "voice_ref")


_DE_ONES = "null eins zwei drei vier fünf sechs sieben acht neun".split()
_DE_ONES_PREFIX = ["", "ein", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun"]
_DE_TEENS = "zehn elf zwölf dreizehn vierzehn fünfzehn sechzehn siebzehn achtzehn neunzehn".split()
_DE_TENS = ["", "", "zwanzig", "dreißig", "vierzig", "fünfzig", "sechzig", "siebzig", "achtzig", "neunzig"]


def _de_under_100(n: int) -> str:
    if n < 10:
        return _DE_ONES[n]
    if n < 20:
        return _DE_TEENS[n - 10]
    t, o = divmod(n, 10)
    return (_DE_ONES_PREFIX[o] + "und" + _DE_TENS[t]) if o else _DE_TENS[t]


def _de_under_1000(n: int) -> str:
    h, rest = divmod(n, 100)
    s = "" if not h else ("hundert" if h == 1 else _DE_ONES_PREFIX[h] + "hundert")
    if rest:
        s += _de_under_100(rest)
    return s


def german_number(n: int) -> str:
    if n == 0:
        return "null"
    if n < 1000:
        return _de_under_1000(n)
    thousand, rest = divmod(n, 1000)
    s = "eintausend" if thousand == 1 else _de_under_1000(thousand) + "tausend"
    if rest:
        s += _de_under_1000(rest)
    return s


_EN_ONES = "zero one two three four five six seven eight nine".split()
_EN_TEENS = "ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen".split()
_EN_TENS = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]


def _en_under_100(n: int) -> str:
    if n < 10:
        return _EN_ONES[n]
    if n < 20:
        return _EN_TEENS[n - 10]
    t, o = divmod(n, 10)
    return _EN_TENS[t] + (f"-{_EN_ONES[o]}" if o else "")


def _en_under_1000(n: int) -> str:
    h, rest = divmod(n, 100)
    parts = []
    if h:
        parts.append(f"{_EN_ONES[h]} hundred")
    if rest:
        parts.append(_en_under_100(rest))
    return " ".join(parts)


def english_number(n: int) -> str:
    if n == 0:
        return "zero"
    if n < 1000:
        return _en_under_1000(n)
    thousand, rest = divmod(n, 1000)
    parts = [f"{_en_under_1000(thousand)} thousand"]
    if rest:
        parts.append(_en_under_1000(rest))
    return " ".join(parts)


_DE_SUBST = [
    (r"Bau-Fahrzeug", "Baufahrzeug"),
    (r"MG-Turm", "Maschinengewehrturm"),
    (r"Mehr\+", "Mehr hinzufügen"),
    (r"Ausw\.", "Auswahl"),
    (r"Rep\.", "Reparatur"),


    (r"\+\s*/\s*[−–-]", "Plus und Minus"),

    (r"\bdie 1\b", "die Gruppentaste eins"),
]
_EN_SUBST = [
    (r"\bSel\.", "Selection"),
    (r"\bRep\.", "Repair"),
    (r"\+\s*/\s*[−–-]", "plus and minus"),
    (r"\b(long-press|[Tt]ap) 1\b", r"\1 group button one"),
]


def normalize(text: str, lang: str) -> str:
    text = re.sub(r"\s*\([^)]*\)", "", text)
    for pat, rep in (_DE_SUBST if lang == "de" else _EN_SUBST):
        text = re.sub(pat, rep, text)
    to_words = german_number if lang == "de" else english_number
    text = re.sub(r"\d+", lambda m: to_words(int(m.group())), text)
    text = text.replace("%", " Prozent" if lang == "de" else " percent")
    text = text.replace("&", " und" if lang == "de" else " and")
    text = text.replace("/", " oder" if lang == "de" else " or")
    text = text.replace("+", "")
    text = text.replace("„", '"').replace("“", '"').replace("”", '"')


    text = re.sub(r"\b[A-ZÄÖÜ]{2,}\b", lambda m: m.group().lower(), text)
    return re.sub(r"\s+", " ", text).strip()


def step_keys() -> list[str]:
    with open(TUTORIAL_GD, encoding="utf-8") as f:
        src = f.read()
    keys = re.findall(r'"text":\s*"([a-z0-9-]+)"', src)
    seen, out = set(), []
    for k in keys:
        if k not in seen:
            seen.add(k)
            out.append(k)
    return out


def read_de() -> dict[str, str]:
    with open(DE_CSV, encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))
    return {r[0]: r[1] for r in rows[1:] if len(r) >= 2 and r[0]}


def read_en() -> dict[str, str]:
    out = {}
    with open(EN_FTL, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^([\w-]+)\s*=\s*(.+?)\s*$", line)
            if m:
                out[m.group(1)] = m.group(2)
    return out


_LEFTOVER = re.compile(r"\d|[+/%&]|\b[A-ZÄÖÜ][a-zäöüß]{0,6}\.\s|\b[A-Z][a-z]{0,6}\.\s")


def main() -> None:
    keys = step_keys()
    de_src, en_src = read_de(), read_en()
    missing_de = [k for k in keys if k not in de_src]
    missing_en = [k for k in keys if k not in en_src]
    if missing_de or missing_en:
        sys.exit(f"fehlende Schlüssel — de: {missing_de}  en: {missing_en}")

    os.makedirs(OUT_DIR, exist_ok=True)
    warnings = []
    for lang, src, out_name in (("de", de_src, "tutorial_de.csv"), ("en", en_src, "tutorial_en.csv")):
        out_path = os.path.join(OUT_DIR, out_name)
        with open(out_path, "w", encoding="utf-8", newline="") as f:
            w = csv.writer(f)
            w.writerow(["key", "text"])
            for k in keys:
                text = normalize(src[k], lang)
                w.writerow([k, text])


                if _LEFTOVER.search(text):
                    warnings.append(f"{lang}:{k}: {text!r}")
        print(f"{out_path}: {len(keys)} Zeilen")

    if warnings:
        print("WARNUNG — möglicherweise noch nicht sprechbar:")
        for w in warnings:
            print(f"  {w}")
    else:
        print("Keine Ziffern/+//%/& oder Abkürzungen mit Punkt übrig.")


if __name__ == "__main__":
    main()
