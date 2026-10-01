#!/usr/bin/env python3

from __future__ import annotations

import argparse
import ast
import io
import shutil
import stat
import subprocess
import sys
import tokenize
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


EXTRA_EXCLUDE_PREFIXES = (
    ("project-docs",),
    ("docs",),
    ("design",),
    ("website",),
)
EXTRA_EXCLUDE_FILES = {"CLAUDE.md", ".gitmodules", "README.md", "tools/worktree.sh", "tools/apk_build.sh"}

STRIP_EXTENSIONS = {".gd", ".cpp", ".h", ".hpp", ".gdshader"}
STRIP_PY_EXTENSIONS = {".py"}
STRIP_PY_FILENAMES = {"SConstruct"}
STRIP_LINE_COMMENT_EXTENSIONS = {".sh", ".yaml", ".yml"}

ALWAYS_INCLUDE = ("LICENSE", "NOTICE")


SUBMODULES = {"gdext/godot-cpp": "https://github.com/godotengine/godot-cpp.git"}


def _line_offsets(text: str) -> list[int]:

    offsets = [0]
    for line in text.splitlines(keepends=True):
        offsets.append(offsets[-1] + len(line))
    return offsets


def _to_offset(offsets: list[int], lineno: int, col: int) -> int:
    return offsets[lineno - 1] + col


def _rstrip_and_collapse(chars: list[str], protected: list[bool], max_blank: int = 2) -> str:


    lines: list[tuple[str, list[bool], bool]] = []
    cur_text: list[str] = []
    cur_prot: list[bool] = []
    for ch, p in zip(chars, protected):
        if ch == "\n":
            lines.append(("".join(cur_text), cur_prot, p))
            cur_text, cur_prot = [], []
        else:
            cur_text.append(ch)
            cur_prot.append(p)
    lines.append(("".join(cur_text), cur_prot, False))

    out_lines: list[str] = []
    blank_run = 0
    for text, prot, closing_nl_protected in lines:
        j = len(text)
        while j > 0 and text[j - 1] in " \t" and not prot[j - 1]:
            j -= 1
        trimmed = text[:j]
        line_has_protected = any(prot) or closing_nl_protected
        if trimmed == "" and not line_has_protected:
            blank_run += 1
            if blank_run <= max_blank:
                out_lines.append("")
        else:
            blank_run = 0
            out_lines.append(trimmed)
    return "\n".join(out_lines)


def _strip_python_comments(source: str) -> str:

    offsets = _line_offsets(source)
    try:
        tokens = list(tokenize.generate_tokens(io.StringIO(source).readline))
    except (tokenize.TokenError, IndentationError, SyntaxError):
        return source
    spans: list[tuple[int, int]] = []
    for tok in tokens:
        if tok.type != tokenize.COMMENT:
            continue
        if tok.start[0] == 1 and tok.string.startswith("#!"):
            continue
        spans.append((_to_offset(offsets, *tok.start), _to_offset(offsets, *tok.end)))
    for start_off, end_off in sorted(spans, reverse=True):
        j = start_off
        while j > 0 and source[j - 1] in " \t":
            j -= 1
        source = source[:j] + source[end_off:]
    return source


def _python_docstring_nodes(source: str) -> list[tuple[ast.Expr, bool]]:

    try:
        tree = ast.parse(source)
    except SyntaxError:
        return []

    doc_nodes: list[tuple[ast.Expr, bool]] = []

    def consider(body: list[ast.stmt]) -> None:
        if body and isinstance(body[0], ast.Expr):
            val = body[0].value
            if isinstance(val, ast.Constant) and isinstance(val.value, str):
                doc_nodes.append((body[0], len(body) == 1))

    consider(tree.body)
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            consider(node.body)
    return doc_nodes


def _ast_char_offset(source: str, offsets: list[int], phys_lines: list[str], lineno: int, byte_col: int) -> int:


    line = phys_lines[lineno - 1]
    char_col = len(line.encode("utf-8")[:byte_col].decode("utf-8"))
    return offsets[lineno - 1] + char_col


def python_docstring_spans(source: str) -> list[tuple[int, int]]:

    doc_nodes = _python_docstring_nodes(source)
    offsets = _line_offsets(source)
    phys_lines = source.splitlines()
    spans = []
    for expr_node, _only_stmt in doc_nodes:
        start_off = _ast_char_offset(source, offsets, phys_lines, expr_node.lineno, expr_node.col_offset)
        end_off = _ast_char_offset(source, offsets, phys_lines, expr_node.end_lineno, expr_node.end_col_offset)
        spans.append((start_off, end_off))
    return spans


def _strip_python_docstrings(source: str) -> str:
    doc_nodes = _python_docstring_nodes(source)
    offsets = _line_offsets(source)
    phys_lines = source.splitlines()

    def char_offset(lineno: int, byte_col: int) -> int:
        return _ast_char_offset(source, offsets, phys_lines, lineno, byte_col)

    for expr_node, only_stmt in sorted(doc_nodes, key=lambda x: x[0].lineno, reverse=True):
        start_off = char_offset(expr_node.lineno, expr_node.col_offset)
        end_off = char_offset(expr_node.end_lineno, expr_node.end_col_offset)
        stub = "pass" if only_stmt else ""
        source = source[:start_off] + stub + source[end_off:]
    return source


def _python_string_mask(source: str) -> list[bool]:

    mask = [False] * len(source)
    offsets = _line_offsets(source)
    try:
        tokens = list(tokenize.generate_tokens(io.StringIO(source).readline))
    except (tokenize.TokenError, IndentationError, SyntaxError):
        return mask
    fstring_types = set()
    for name in ("FSTRING_START", "FSTRING_MIDDLE", "FSTRING_END"):
        if hasattr(tokenize, name):
            fstring_types.add(getattr(tokenize, name))
    for tok in tokens:
        if tok.type == tokenize.STRING or tok.type in fstring_types:
            start_off = _to_offset(offsets, *tok.start)
            end_off = _to_offset(offsets, *tok.end)
            for k in range(start_off, min(end_off, len(source))):
                mask[k] = True
    return mask


def strip_python_source(source: str) -> str:
    source = _strip_python_comments(source)
    source = _strip_python_docstrings(source)
    mask = _python_string_mask(source)
    return _rstrip_and_collapse(list(source), mask)


def _gdscript_scan(source: str) -> tuple[list[str], list[bool]]:

    NORMAL, STR1, STR2, TSTR1, TSTR2, COMMENT = range(6)
    state = NORMAL
    chars: list[str] = []
    protected: list[bool] = []
    i, n = 0, len(source)

    def emit(c: str, prot: bool) -> None:
        chars.append(c)
        protected.append(prot)

    while i < n:
        c = source[i]
        if state == NORMAL:
            if c == "#":
                state = COMMENT
                i += 1
                continue
            if c == '"':
                if source[i:i + 3] == '"""':
                    emit('"', True); emit('"', True); emit('"', True)
                    i += 3
                    state = TSTR2
                    continue
                emit(c, True)
                i += 1
                state = STR2
                continue
            if c == "'":
                if source[i:i + 3] == "'''":
                    emit("'", True); emit("'", True); emit("'", True)
                    i += 3
                    state = TSTR1
                    continue
                emit(c, True)
                i += 1
                state = STR1
                continue
            emit(c, False)
            i += 1
            continue
        if state == COMMENT:
            if c == "\n":
                emit(c, False)
                state = NORMAL
            i += 1
            continue
        if state in (STR1, STR2):
            quote = "'" if state == STR1 else '"'
            if c == "\\" and i + 1 < n:
                emit(c, True); emit(source[i + 1], True)
                i += 2
                continue
            emit(c, True)
            i += 1
            if c == quote:
                state = NORMAL
            continue
        if state in (TSTR1, TSTR2):
            triple = "'''" if state == TSTR1 else '"""'
            if c == "\\" and i + 1 < n:
                emit(c, True); emit(source[i + 1], True)
                i += 2
                continue
            if source[i:i + 3] == triple:
                emit(triple[0], True); emit(triple[1], True); emit(triple[2], True)
                i += 3
                state = NORMAL
                continue
            emit(c, True)
            i += 1
            continue

    return chars, protected


def strip_gdscript_source(source: str) -> str:
    chars, protected = _gdscript_scan(source)
    return _rstrip_and_collapse(chars, protected)


_RAW_PREFIXES = ("u8R", "uR", "UR", "LR", "R")


def _c_family_scan(source: str, raw_strings: bool = True) -> tuple[list[str], list[bool]]:

    chars: list[str] = []
    protected: list[bool] = []
    i, n = 0, len(source)

    def emit(c: str, prot: bool) -> None:
        chars.append(c)
        protected.append(prot)

    def emit_str(s: str, prot: bool) -> None:
        for c in s:
            emit(c, prot)

    while i < n:
        c = source[i]


        if c == "/" and i + 1 < n and source[i + 1] == "/":
            i += 2
            while i < n and source[i] != "\n":
                i += 1
            continue


        if c == "/" and i + 1 < n and source[i + 1] == "*":
            i += 2
            while i < n and not (source[i] == "*" and i + 1 < n and source[i + 1] == "/"):
                if source[i] == "\n":
                    emit("\n", False)
                i += 1
            i += 2
            continue


        if raw_strings and c in ("R", "u", "U", "L"):
            matched = None
            for pfx in _RAW_PREFIXES:
                if source.startswith(pfx + '"', i):
                    matched = pfx
                    break
            if matched:
                emit_str(matched, False)
                emit('"', True)
                i += len(matched) + 1
                delim_start = i
                while i < n and source[i] != "(":
                    i += 1
                paren_pos = i
                delim = source[delim_start:paren_pos]
                emit_str(delim, True)
                if paren_pos < n:
                    emit("(", True)
                    i = paren_pos + 1
                closing = ")" + delim + '"'
                end = source.find(closing, i)
                if end == -1:
                    emit_str(source[i:], True)
                    i = n
                else:
                    emit_str(source[i:end + len(closing)], True)
                    i = end + len(closing)
                continue


        if c == '"':
            emit(c, True)
            i += 1
            while i < n:
                if source[i] == "\\" and i + 1 < n:
                    emit(source[i], True)
                    emit(source[i + 1], True)
                    i += 2
                    continue
                emit(source[i], True)
                closed = source[i] == '"'
                i += 1
                if closed:
                    break
            continue


        if c == "'":
            prev = chars[-1] if chars else ""
            if prev.isdigit():
                emit(c, False)
                i += 1
                continue
            emit(c, True)
            i += 1
            while i < n:
                if source[i] == "\\" and i + 1 < n:
                    emit(source[i], True)
                    emit(source[i + 1], True)
                    i += 2
                    continue
                emit(source[i], True)
                closed = source[i] == "'"
                i += 1
                if closed:
                    break
            continue

        emit(c, False)
        i += 1

    return chars, protected


def strip_c_family_source(source: str, raw_strings: bool = True) -> str:
    chars, protected = _c_family_scan(source, raw_strings=raw_strings)
    return _rstrip_and_collapse(chars, protected)


def strip_gdshader_source(source: str) -> str:


    return strip_c_family_source(source, raw_strings=False)


def _is_extra_excluded(rel: Path) -> bool:
    parts = rel.parts
    for prefix in EXTRA_EXCLUDE_PREFIXES:
        if parts[: len(prefix)] == prefix:
            return True
    return False


def _strip_line_comments(source: str) -> str:
    out = []
    for i, line in enumerate(source.splitlines()):
        s = line.lstrip()
        if s.startswith("#") and not (i == 0 and s.startswith("#!")):
            continue
        out.append(line.rstrip())
    text = "\n".join(out)
    while "\n\n\n" in text:
        text = text.replace("\n\n\n", "\n\n")
    return text.strip("\n") + "\n"


def list_source_files(root: Path) -> list[Path]:
    proc = subprocess.run(
        ["git", "ls-files", "--cached"],
        cwd=root, capture_output=True, text=True, check=True,
    )
    seen: set[Path] = set()
    files: list[Path] = []
    for line in proc.stdout.splitlines():
        if not line:
            continue
        rel = Path(line)
        if _is_extra_excluded(rel) or str(rel) in EXTRA_EXCLUDE_FILES:
            continue
        if not (root / rel).is_file():
            continue
        if rel not in seen:
            seen.add(rel)
            files.append(rel)
    return files


def _strip_for(rel: Path, text: str) -> str | None:

    name = rel.name
    suffix = rel.suffix
    if name in STRIP_PY_FILENAMES:
        return strip_python_source(text)
    if suffix in STRIP_PY_EXTENSIONS:
        return strip_python_source(text)
    if suffix == ".gd":
        return strip_gdscript_source(text)
    if suffix == ".gdshader":
        return strip_gdshader_source(text)
    if suffix in {".cpp", ".h", ".hpp"}:
        return strip_c_family_source(text)
    if suffix in STRIP_LINE_COMMENT_EXTENSIONS:
        return _strip_line_comments(text)
    return None


README_PUBLIC = """\
<p align="center">
  <img src="https://pocketra.net/img/battle-05.png" alt="PocketRA gameplay: mammoth tanks, infantry and artillery clash in a large field battle" width="640">
</p>

<h1 align="center">PocketRA</h1>
<p align="center"><em>Command &amp; Conquer: Red Alert, rebuilt for touch, with multiplayer by game code and game logic that follows OpenRA.</em></p>

<p align="center">
  <a href="https://pocketra.net"><img alt="Website" src="https://img.shields.io/badge/website-pocketra.net-ffd140?style=flat-square"></a>
  <img alt="License" src="https://img.shields.io/badge/license-GPL--3.0--or--later-4c6ef5?style=flat-square">
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS-8c7540?style=flat-square">
</p>

**EA has not endorsed and does not support this product.** *Command & Conquer* and *Red Alert* are
trademarks of Electronic Arts Inc. PocketRA is a free, non-commercial fan project with no
affiliation to EA or Westwood Studios, and this repository contains no EA game data. See
[Legal](#legal) below for the details.

## What it is

PocketRA rebuilds *Command & Conquer: Red Alert* from scratch for the phone in your pocket.
Interface and touch controls run in Godot 4, and the game simulation itself runs in C++
(GDExtension), deterministic and integer-only, at 25 ticks per second like the original. Damage,
armour, ranges, build times, pathfinding, superweapons and AI follow the open rule files of
[OpenRA](https://www.openra.net); deviations are marked as such in the code.

## Downloads

| Platform | Get it |
|---|---|
| Android | [Download the APK](https://github.com/tomgoeck/pocketra/releases/latest/download/pocketra-dist.apk). Not on the Play Store, so allow installs from this source once. |
| iOS | [Join the TestFlight beta](https://testflight.apple.com/join/vE3V2vBf). No App Store review yet. |
| Windows | [Download the installer](https://github.com/tomgoeck/pocketra/releases/latest/download/pocketra-windows-setup.exe). Built for touch, meant for trying out. |
| macOS | [Download the disk image](https://github.com/tomgoeck/pocketra/releases/latest/download/pocketra-macos.dmg). Built for touch, meant for trying out. |

All release notes and install steps: **[pocketra.net](https://pocketra.net)**. Source code and
issues live here, and every release is also attached to this repository's
[Releases page](https://github.com/tomgoeck/pocketra/releases).

## What's inside

- **Skirmish** against up to five AI opponents at three strengths, with 142 maps from OpenRA in
  temperate and snow, all units, superweapons, ships and aircraft, and save/load.
- **Multiplayer by game code.** Open a room and share a six-character code with friends: no
  account, no sign-up. Lockstep like OpenRA, so only orders are transmitted and every device
  simulates the same match, with text chat and hold-to-talk voice. Your seat is kept if a
  notification drops you out.
- **Tutorial** mission that walks through base building, the build bar, command bar, radial menu
  and gestures step by step, narrated in German and English.
- German and English throughout, with German voice lines pulled from your own CD.
- Self-updating: the app fetches new content on start, so no reinstall is needed for content
  updates.
- Note: campaign missions are imported but not reliably playable yet. Some run, many break or
  can't be won, so the menu marks them as "in testing". Skirmish and multiplayer are the finished
  part of the game.
- No map editor, no mods yet.

## Screenshots

<p align="center">
  <img src="https://pocketra.net/img/battle-01.png" alt="Tesla coils and Tesla tanks stop an Allied tank rush" width="45%">
  <img src="https://pocketra.net/img/battle-02.png" alt="Mammoth tanks and V2 launchers lay siege to an Allied base" width="45%">
  <br>
  <img src="https://pocketra.net/img/battle-03.png" alt="Missile submarines and destroyers shell a coastal base" width="45%">
  <img src="https://pocketra.net/img/battle-04.png" alt="MiGs strike an Allied base while flak guns fire back" width="45%">
</p>

Menu, multiplayer lobby and skirmish setup:

<p align="center">
  <img src="https://pocketra.net/img/menu.png" alt="PocketRA main menu" width="30%">
  <img src="https://pocketra.net/img/create.png" alt="Creating a multiplayer room" width="30%">
  <img src="https://pocketra.net/img/lobby.png" alt="Multiplayer lobby with teams, chat and map preview" width="30%">
</p>

### Gameplay

<p align="center"><img src="https://pocketra.net/img/battle.gif" alt="Soviet and Allied forces fighting in a skirmish" width="70%"></p>

## Layout

| Folder | Contents |
|---|---|
| `game/` | Godot project (GDScript, scenes, translations, icons) |
| `gdext/` | GDExtension bridge to the simulation, `godot-cpp` as a submodule |
| `sim/` | C++ simulation (deterministic, integer-only) and tests |
| `tools/` | Pipeline: MIX/SHP/AUD/VQA from the original game files to atlases, sounds, maps and rules |

## Building

Requirements: Godot 4.7, Python 3.11+, SCons, ffmpeg, Android SDK/NDK for the APK.

1. Get the game data (not in this repository): unpack `ra-quickinstall.zip` from an OpenRA mirror
   (list: https://www.openra.net/packages/ra-quickinstall-mirrors.txt) into `content/ra/`, or copy
   `MAIN.MIX`/`REDALERT.MIX` from your own CD there.
2. OpenRA reference for rules and maps: `git clone --depth 1 https://github.com/OpenRA/OpenRA reference/OpenRA`
3. Pipeline (creates `game/assets/`):
   ```bash
   python3 tools/rules2json.py
   python3 tools/tileset2atlas.py temperat && python3 tools/tileset2atlas.py snow && python3 tools/tileset2atlas.py interior
   python3 tools/mapconvert.py
   python3 tools/audconvert.py $(cat tools/sounds.txt) -o game/assets/sfx
   ```
4. Simulation and bridge:
   ```bash
   sim/tests/run.sh
   git submodule update --init
   cd gdext && scons platform=macos arch=arm64 target=template_debug
   cd gdext && scons platform=android arch=arm64 target=template_debug
   ```
5. Godot: `Godot --headless --path game --import`, then `Godot --path game` to run, or
   `Godot --headless --path game --export-debug Android ../build/pocketra.apk`.

## Legal

PocketRA is a free, non-commercial fan project. It is not endorsed by Electronic Arts and not
affiliated with Electronic Arts or Westwood Studios. *Command & Conquer* and *Red Alert* are
trademarks of Electronic Arts Inc.

The original game files are used, as in OpenRA, under the licence granted by Electronic Arts'
C&C Franchise Modding Guidelines: free of charge, non-commercial and without any music files from
C&C games. Neither this repository nor the app contains or distributes those files; the app
downloads the freely available base files from the same mirrors OpenRA uses, or reads them from
your own copy of the game.

PocketRA's own source code is licensed under the GNU General Public License, version 3 or later
(`LICENSE`, GPL-3.0-or-later). The game rules are derived from the rule files of
[OpenRA](https://www.openra.net), which are also GPLv3. PocketRA is an independent project and not
part of OpenRA; origin notes for third-party code and assets are in `NOTICE`.

This is an automatically generated, comment-free publication copy (`tools/publish.py`).
"""


def build_public_copy(root: Path, out_dir: Path) -> tuple[int, int]:
    if out_dir.exists():
        for child in out_dir.iterdir():
            if child.name == ".git":
                continue
            shutil.rmtree(child) if child.is_dir() else child.unlink()
    out_dir.mkdir(parents=True, exist_ok=True)

    files = list_source_files(root)
    for rel in ALWAYS_INCLUDE:
        p = Path(rel)
        if p not in files and (root / p).is_file():
            files.append(p)

    (out_dir / "README.md").write_text(README_PUBLIC, encoding="utf-8")
    (out_dir / ".gitignore").write_text(
        "content/\ngame/assets/\n.godot/\ngame/bin/*.so\ngame/bin/*.dylib\ngame/bin/*.dll\n"
        "*.translation\nbuild/\n*.os\n*.obj\n.sconsign.dblite\ncompile_commands.json\n*.o\n*.a\n"
        ".DS_Store\nreference/\n__pycache__/\n*.pyc\n", encoding="utf-8")
    file_count = 2
    stripped_count = 0
    for rel in files:
        src = root / rel
        dst = out_dir / rel
        dst.parent.mkdir(parents=True, exist_ok=True)

        try:
            text = src.read_text(encoding="utf-8")
        except (UnicodeDecodeError, ValueError):
            text = None

        if text is not None:
            stripped = _strip_for(rel, text)
            if stripped is not None:
                dst.write_text(stripped, encoding="utf-8")
                st = src.stat()
                if st.st_mode & stat.S_IXUSR:
                    dst.chmod(dst.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
                file_count += 1
                stripped_count += 1
                continue

        shutil.copy2(src, dst)
        file_count += 1

    return file_count, stripped_count


def setup_git_orphan(out_dir: Path, remote_url: str, root: Path) -> None:
    git_dir = out_dir / ".git"
    if not git_dir.exists():
        subprocess.run(["git", "init", "-q", "-b", "main"], cwd=out_dir, check=True)
        subprocess.run(["git", "config", "user.email", "tomgoeck@users.noreply.github.com"], cwd=out_dir, check=True)
        subprocess.run(["git", "config", "user.name", "tomgoeck"], cwd=out_dir, check=True)
    subprocess.run(["git", "add", "-A"], cwd=out_dir, check=True)
    for path, url in SUBMODULES.items():
        sha = subprocess.run(["git", "rev-parse", f"HEAD:{path}"], cwd=root,
                             capture_output=True, text=True, check=True).stdout.strip()
        (out_dir / ".gitmodules").write_text(
            f'[submodule "{path}"]\n\tpath = {path}\n\turl = {url}\n', encoding="utf-8")
        subprocess.run(["git", "add", ".gitmodules"], cwd=out_dir, check=True)
        subprocess.run(["git", "update-index", "--add", "--cacheinfo", f"160000,{sha},{path}"],
                       cwd=out_dir, check=True)
    diff = subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=out_dir)
    if diff.returncode != 0:
        subprocess.run(
            ["git", "commit", "-q", "-m", "PocketRA: public snapshot"],
            cwd=out_dir, check=True,
        )
    remotes = subprocess.run(
        ["git", "remote"], cwd=out_dir, capture_output=True, text=True, check=True,
    ).stdout.split()
    if "origin" not in remotes:
        subprocess.run(["git", "remote", "add", "origin", remote_url], cwd=out_dir, check=True)
    else:
        subprocess.run(["git", "remote", "set-url", "origin", remote_url], cwd=out_dir, check=True)
    print(f"Git-Repo bereit unter {out_dir} (Branch main). Push von Hand mit:")
    print(f"  cd {out_dir} && git push -u origin main")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default="build/public", help="Zielverzeichnis (Standard: build/public)")
    parser.add_argument("--git", metavar="URL", default=None,
                         help="Legt in --out ein Git-Repo mit orphan-Branch 'public' an und zeigt den "
                              "Push-Befehl an — pusht NICHT von selbst.")
    args = parser.parse_args()

    out_dir = Path(args.out)
    if not out_dir.is_absolute():
        out_dir = REPO_ROOT / out_dir

    if not (REPO_ROOT / "LICENSE").is_file():
        print("Fehler: LICENSE fehlt im Repo-Root — vor der Veröffentlichung anlegen.", file=sys.stderr)
        return 1

    file_count, stripped_count = build_public_copy(REPO_ROOT, out_dir)
    print(f"Veröffentlichungskopie erzeugt unter {out_dir}: {file_count} Dateien, "
          f"davon {stripped_count} kommentarfrei umgeschrieben.")

    if args.git:
        setup_git_orphan(out_dir, args.git, REPO_ROOT)

    return 0


if __name__ == "__main__":
    sys.exit(main())
