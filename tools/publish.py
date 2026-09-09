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
    ("docs", "research"),
)

STRIP_EXTENSIONS = {".gd", ".cpp", ".h", ".hpp", ".gdshader"}
STRIP_PY_EXTENSIONS = {".py"}
STRIP_PY_FILENAMES = {"SConstruct"}


ALWAYS_INCLUDE = ("README.md", "docs/ARCHITEKTUR.md", "CLAUDE.md", "LICENSE")


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


def list_source_files(root: Path) -> list[Path]:
    proc = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard"],
        cwd=root, capture_output=True, text=True, check=True,
    )
    seen: set[Path] = set()
    files: list[Path] = []
    for line in proc.stdout.splitlines():
        if not line:
            continue
        rel = Path(line)
        if _is_extra_excluded(rel):
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
    return None


NOTICE_HEADER = """\
## Lizenz und Herkunft

Der Code in diesem Repository steht unter der GNU General Public License v3.0
(Volltext in [`LICENSE`](LICENSE)). Die Spielregeln und die Missionslogik sind von
[OpenRA](https://github.com/OpenRA/OpenRA) (ebenfalls GPLv3) abgeleitet bzw. eng
daran angelehnt; Abweichungen sind im Code kommentiert. Die Original-Grafiken, -Sounds
und -Videos gehören Westwood Studios/Electronic Arts und liegen diesem Repository
nicht bei — wer selbst bauen will, bezieht sie über das EA-Freeware-Paket
(`ra-quickinstall.zip`, siehe Abschnitt „Setup" unten). Dieser Kommentar-freie Stand
ist eine automatisch erzeugte Veröffentlichungskopie (`tools/publish.py`).

---

"""


def build_public_copy(root: Path, out_dir: Path) -> tuple[int, int]:
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)

    files = list_source_files(root)
    for rel in ALWAYS_INCLUDE:
        p = Path(rel)
        if p not in files and (root / p).is_file():
            files.append(p)

    file_count = 0
    stripped_count = 0
    for rel in files:
        src = root / rel
        dst = out_dir / rel
        dst.parent.mkdir(parents=True, exist_ok=True)

        if rel == Path("README.md"):
            text = src.read_text(encoding="utf-8")
            dst.write_text(NOTICE_HEADER + text, encoding="utf-8")
            file_count += 1
            continue

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


def setup_git_orphan(out_dir: Path, remote_url: str) -> None:
    git_dir = out_dir / ".git"
    if not git_dir.exists():
        subprocess.run(["git", "init", "-q"], cwd=out_dir, check=True)
        subprocess.run(["git", "checkout", "-q", "-b", "public"], cwd=out_dir, check=True)
        subprocess.run(
            ["git", "config", "user.email", "publish@localhost"], cwd=out_dir, check=True,
        )
        subprocess.run(["git", "config", "user.name", "publish.py"], cwd=out_dir, check=True)
    subprocess.run(["git", "add", "-A"], cwd=out_dir, check=True)
    diff = subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=out_dir)
    if diff.returncode != 0:
        subprocess.run(
            ["git", "commit", "-q", "-m", "Public snapshot (kommentarfrei)"],
            cwd=out_dir, check=True,
        )
    remotes = subprocess.run(
        ["git", "remote"], cwd=out_dir, capture_output=True, text=True, check=True,
    ).stdout.split()
    if "origin" not in remotes:
        subprocess.run(["git", "remote", "add", "origin", remote_url], cwd=out_dir, check=True)
    else:
        subprocess.run(["git", "remote", "set-url", "origin", remote_url], cwd=out_dir, check=True)
    print(f"Git-Repo bereit unter {out_dir} (Branch public). Push von Hand mit:")
    print(f"  cd {out_dir} && git push -u origin public")


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
        setup_git_orphan(out_dir, args.git)

    return 0


if __name__ == "__main__":
    sys.exit(main())
