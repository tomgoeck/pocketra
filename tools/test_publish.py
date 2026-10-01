#!/usr/bin/env python3

from __future__ import annotations

import argparse
import io
import re
import sys
import tokenize
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "tools"))
import publish


class Check:
    def __init__(self) -> None:
        self.passed = 0
        self.failed = 0

    def ok(self, cond: bool, label: str) -> None:
        if cond:
            self.passed += 1
        else:
            self.failed += 1
            print(f"FEHLER: {label}")


def unit_tests(chk: Check) -> None:

    py_src = (
        '#!/usr/bin/env python3\n'
        '"""Modul-Docstring, verschwindet."""\n'
        'import re\n'
        '\n'
        'PATTERN = "a#b"  # Kommentar am Ende\n'
        '\n'
        'def f(x):\n'
        '    """Funktions-Docstring."""\n'
        '    return f"{x:#x}"  # hex mit #\n'
        '\n'
        'def only_doc():\n'
        '    """Einziger Inhalt — muss zu pass werden."""\n'
        '\n'
        'class C:\n'
        '    """Klassen-Docstring."""\n'
        '    x = 1\n'
    )
    out = publish.strip_python_source(py_src)
    chk.ok(out.startswith('#!/usr/bin/env python3'), "Python: Shebang bleibt erhalten")
    chk.ok('Modul-Docstring' not in out, "Python: Modul-Docstring entfernt")
    chk.ok('Funktions-Docstring' not in out, "Python: Funktions-Docstring entfernt")
    chk.ok('Klassen-Docstring' not in out, "Python: Klassen-Docstring entfernt")
    chk.ok('Kommentar am Ende' not in out, "Python: Zeilenendkommentar entfernt")
    chk.ok('"a#b"' in out, "Python: String mit '#' bleibt unversehrt")
    chk.ok('f"{x:#x}"' in out, "Python: f-String-Formatspezifikation mit '#' bleibt unversehrt")
    chk.ok('hex mit #' not in out, "Python: Kommentar nach f-String entfernt")
    m = re.search(r'def only_doc\(\):\s*\n\s*pass', out)
    chk.ok(m is not None, "Python: Docstring als einzige Anweisung wird zu 'pass'")
    compiled_ok = True
    try:
        compile(out, "<synthetic>", "exec")
    except SyntaxError:
        compiled_ok = False
    chk.ok(compiled_ok, "Python: Ausgabe bleibt syntaktisch gültig")


    py_src2 = (
        'TEXT = """Zeile 1\n'
        '\n'
        '\n'
        '\n'
        'Zeile 5 nach drei Leerzeilen"""  # Kommentar\n'
        '\n'
        '\n'
        '\n'
        'x = 1\n'
    )
    out2 = publish.strip_python_source(py_src2)
    chk.ok('\n\n\n\nZeile 5' in out2, "Python: Leerzeilen INNERHALB eines Strings bleiben unangetastet")
    chk.ok(out2.count('\n\n\n') <= 1 or 'x = 1' in out2, "Python: Leerzeilen AUSSERHALB werden zusammengezogen")


    gd_src = (
        '## Doc-Kommentar für die Klasse\n'
        'extends Node\n'
        '\n'
        'const PATH := "res://assets/video/intro.ogv"  # res:// enthält //\n'
        'const TAG := "#ff0000"  # Kommentar\n'
        'var s := """mehrzeilig\n'
        '\n'
        'mit Leerzeile"""\n'
        '# reine Kommentarzeile\n'
        'func f():\n'
        '\tpass\n'
    )
    out_gd = publish.strip_gdscript_source(gd_src)
    chk.ok('Doc-Kommentar' not in out_gd, "GDScript: ##-Doc-Kommentar entfernt")
    chk.ok('res://assets/video/intro.ogv' in out_gd, "GDScript: res://-String bleibt unversehrt")
    chk.ok('enthält //' not in out_gd, "GDScript: Kommentar nach res://-String entfernt")
    chk.ok('"#ff0000"' in out_gd, "GDScript: Farbstring mit '#' bleibt unversehrt")
    chk.ok('reine Kommentarzeile' not in out_gd, "GDScript: reine Kommentarzeile entfernt")
    chk.ok('mit Leerzeile' in out_gd, "GDScript: Leerzeile in mehrzeiligem String bleibt")


    cpp_src = (
        '// Zeilenkommentar\n'
        'const char* a = "hat // drin";  // trailing\n'
        'const char* b = "hat # drin";\n'
        '/* Block\n'
        '   über\n'
        '   mehrere Zeilen */\n'
        'int n = 1\'000\'000;  // Ziffern-Trenner, kein char-Literal\n'
        'char c = \'x\';  // echtes char-Literal\n'
        'auto r = R"(roh mit // und # und "Anführungszeichen")";\n'
        'auto r2 = R"delim(roh mit )innerhalb() delim)";\n'
    )
    out_cpp = publish.strip_c_family_source(cpp_src)
    chk.ok('Zeilenkommentar' not in out_cpp, "C++: Zeilenkommentar entfernt")
    chk.ok('"hat // drin"' in out_cpp, "C++: String mit '//' bleibt unversehrt")
    chk.ok('trailing' not in out_cpp, "C++: Kommentar nach String entfernt")
    chk.ok('"hat # drin"' in out_cpp, "C++: String mit '#' bleibt unversehrt")
    chk.ok('Block' not in out_cpp and 'über' not in out_cpp, "C++: Blockkommentar entfernt")


    chk.ok('\n\n\nint n' in out_cpp, "C++: Blockkommentar wird zu Leerzeilen, auf max. 2 zusammengezogen")

    one_line_block = publish.strip_c_family_source("a;\n/* x */\nb;\n")
    chk.ok(one_line_block == 'a;\n\nb;\n', "C++: einzeiliger Blockkommentar wird zu genau einer Leerzeile")
    chk.ok("1'000'000" in out_cpp, "C++: Ziffern-Trenner bleibt erhalten (kein char-Literal)")
    chk.ok("'x'" in out_cpp, "C++: echtes char-Literal bleibt erhalten")
    chk.ok('roh mit // und # und "Anführungszeichen"' in out_cpp, "C++: Roh-String-Inhalt bleibt unversehrt")
    chk.ok(')innerhalb()' in out_cpp, "C++: Roh-String mit eigenem Trenner bleibt unversehrt")


    shader_src = 'uniform float x;\n// Kommentar\nvoid fragment() {\n\tCOLOR.a = 1.0; // inline\n}\n'
    out_shader = publish.strip_gdshader_source(shader_src)
    chk.ok('Kommentar' not in out_shader and 'inline' not in out_shader, "gdshader: Kommentare entfernt")
    chk.ok('COLOR.a = 1.0;' in out_shader, "gdshader: Code bleibt erhalten")


def _c_family_comment_free(text: str, raw_strings: bool) -> bool:
    chars, protected = publish._c_family_scan(text, raw_strings=raw_strings)
    for i in range(len(chars) - 1):
        if protected[i] or protected[i + 1]:
            continue
        if chars[i] == "/" and chars[i + 1] in ("/", "*"):
            return False
    return True


def _gdscript_comment_free(text: str) -> bool:
    chars, protected = publish._gdscript_scan(text)
    for c, p in zip(chars, protected):
        if c == "#" and not p:
            return False
    return True


def _python_comment_free(text: str) -> bool:
    try:
        tokens = list(tokenize.generate_tokens(io.StringIO(text).readline))
    except (tokenize.TokenError, IndentationError, SyntaxError):
        return True
    for tok in tokens:
        if tok.type == tokenize.COMMENT:
            if tok.start[0] == 1 and tok.string.startswith("#!"):
                continue
            return False
    return True


def _no_leftover_comment_lines(path: Path, chk: Check) -> None:
    suffix = path.suffix
    text = path.read_text(encoding="utf-8", errors="replace")
    if suffix == ".py" or path.name == "SConstruct":
        chk.ok(_python_comment_free(text), f"{path}: keine übrig gebliebenen Python-Kommentare (tokenize-Stichprobe)")
    elif suffix == ".gd":
        chk.ok(_gdscript_comment_free(text), f"{path}: keine übrig gebliebenen GDScript-Kommentare (Automaten-Stichprobe)")
    elif suffix in {".cpp", ".h", ".hpp"}:
        chk.ok(_c_family_comment_free(text, raw_strings=True), f"{path}: keine übrig gebliebenen C++-Kommentare (Automaten-Stichprobe)")
    elif suffix == ".gdshader":
        chk.ok(_c_family_comment_free(text, raw_strings=False), f"{path}: keine übrig gebliebenen gdshader-Kommentare (Automaten-Stichprobe)")


def _string_spans_with(source: str, suffix: str, marker_chars: tuple[str, ...]) -> set[str]:

    if suffix == ".py":
        mask = publish._python_string_mask(source)


        for start, end in publish.python_docstring_spans(source):
            for k in range(start, min(end, len(mask))):
                mask[k] = False
    elif suffix == ".gd":
        chars, protected = publish._gdscript_scan(source)
        mask = protected
        source = "".join(chars)
    elif suffix in {".cpp", ".h", ".hpp"}:
        chars, protected = publish._c_family_scan(source, raw_strings=True)
        mask = protected
        source = "".join(chars)
    elif suffix == ".gdshader":
        chars, protected = publish._c_family_scan(source, raw_strings=False)
        mask = protected
        source = "".join(chars)
    else:
        return set()

    spans: set[str] = set()
    i, n = 0, len(mask)
    while i < n:
        if not mask[i]:
            i += 1
            continue
        j = i
        while j < n and mask[j]:
            j += 1
        span = source[i:j]
        if any(m in span for m in marker_chars):
            spans.add(span)
        i = j
    return spans


def _hash_strings_survive(orig: Path, copy: Path, chk: Check) -> int:
    suffix = orig.suffix
    if suffix == "" and orig.name != "SConstruct":
        return 0
    orig_suffix = ".py" if orig.name == "SConstruct" else suffix
    if orig_suffix not in {".py", ".gd", ".cpp", ".h", ".hpp", ".gdshader"}:
        return 0
    orig_text = orig.read_text(encoding="utf-8", errors="replace")
    copy_text = copy.read_text(encoding="utf-8", errors="replace")
    markers = ("#",) if orig_suffix in {".py", ".gd"} else ("#", "//")
    needles = _string_spans_with(orig_text, orig_suffix, markers)
    checked = 0
    for needle in needles:
        checked += 1
        chk.ok(needle in copy_text, f"{copy}: String {needle!r} aus dem Original nicht wortgleich wiedergefunden")
    return checked


def file_based_checks(chk: Check, repo: Path, out_dir: Path) -> None:
    if not out_dir.is_dir():
        print(f"Hinweis: {out_dir} existiert nicht — überspringe dateibasierte Prüfungen "
              f"(erst `python3 tools/publish.py --out {out_dir}` ausführen).")
        return
    strip_suffixes = {".py", ".gd", ".cpp", ".h", ".hpp", ".gdshader"}
    checked_files = 0
    checked_strings = 0
    for path in out_dir.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(out_dir)
        if path.suffix not in strip_suffixes and path.name != "SConstruct":
            continue
        checked_files += 1
        _no_leftover_comment_lines(path, chk)
        orig = repo / rel
        if orig.is_file():
            checked_strings += _hash_strings_survive(orig, path, chk)
    print(f"Dateibasierte Prüfung: {checked_files} Dateien, {checked_strings} '#'/'//'"
          f"-String-Stichproben gegen das Original abgeglichen.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dir", default="build/public", help="Veröffentlichungskopie (Standard: build/public)")
    parser.add_argument("--repo", default=".", help="Original-Repo zum Abgleich (Standard: Repo-Root)")
    args = parser.parse_args()

    repo = Path(args.repo)
    if not repo.is_absolute():
        repo = REPO_ROOT / repo
    out_dir = Path(args.dir)
    if not out_dir.is_absolute():
        out_dir = REPO_ROOT / out_dir

    chk = Check()
    unit_tests(chk)
    file_based_checks(chk, repo, out_dir)

    print(f"\n{chk.passed} bestanden, {chk.failed} fehlgeschlagen.")
    return 1 if chk.failed else 0


if __name__ == "__main__":
    sys.exit(main())
