
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Node:
    key: str
    value: str = ""
    children: list["Node"] = field(default_factory=list)

    def child(self, key: str) -> "Node | None":
        for c in self.children:
            if c.key == key:
                return c
        return None

    def get(self, key: str, default: str = "") -> str:
        c = self.child(key)
        return c.value if c is not None and c.value != "" else default

    def path(self, *keys: str) -> "Node | None":
        n: Node | None = self
        for k in keys:
            if n is None:
                return None
            n = n.child(k)
        return n

    def as_dict(self) -> dict:
        return {c.key: (c.value if not c.children else c.as_dict()) for c in self.children}


def parse(text: str) -> list[Node]:
    root = Node("")
    stack: list[tuple[int, Node]] = [(-1, root)]
    for raw in text.splitlines():
        line = raw.rstrip()

        if "#" in line:
            line = line[: line.index("#")].rstrip()
        if not line.strip():
            continue
        depth = 0
        while depth < len(line) and line[depth] == "\t":
            depth += 1
        body = line.strip()
        if ":" in body:
            key, _, value = body.partition(":")
            key, value = key.strip(), value.strip()
        else:
            key, value = body, ""
        node = Node(key, value)
        while stack and stack[-1][0] >= depth:
            stack.pop()
        stack[-1][1].children.append(node)
        stack.append((depth, node))
    return root.children


def parse_file(path: Path) -> list[Node]:
    return parse(path.read_text(encoding="utf-8", errors="replace"))


def _last_index(nodes: list[Node], key: str) -> int:
    for i in range(len(nodes) - 1, -1, -1):
        if nodes[i].key == key:
            return i
    return -1


def merge(base: list[Node], over: list[Node]) -> list[Node]:

    out: list[Node] = []
    seen: set[str] = set()

    def merge_node(n: Node) -> None:
        if n.key.startswith("-"):
            out.append(Node(n.key, n.value, list(n.children)))
            return
        if n.key not in seen:
            seen.add(n.key)
            out.append(Node(n.key, n.value, list(n.children)))
            return
        prev = _last_index(out, n.key)


        if _last_index(out, "-" + n.key) > prev:
            out.append(Node(n.key, n.value, list(n.children)))
            return
        o = out[prev]
        out[prev] = Node(n.key, n.value if n.value != "" else o.value, merge(o.children, n.children))

    for n in base:
        merge_node(n)
    for n in over:
        merge_node(n)
    return out


def resolve_removals(nodes: list[Node]) -> list[Node]:

    out: list[Node] = []
    for n in nodes:
        if n.key.startswith("-"):
            key = n.key[1:]
            out = [o for o in out if o.key != key]
            continue
        out.append(Node(n.key, n.value, resolve_removals(n.children)))
    return out


class Rules:


    def __init__(self, files: list[Path], extra_texts: list[str] | None = None):
        self.raw: dict[str, Node] = {}

        sources = [parse_file(f) for f in files] + [parse(t) for t in (extra_texts or [])]
        for src in sources:
            for n in src:
                key = n.key.lower()

                if key.startswith("-"):
                    self.raw.pop(key[1:], None)
                    continue
                if key in self.raw:
                    self.raw[key] = Node(key, n.value, merge(self.raw[key].children, n.children))
                else:
                    self.raw[key] = Node(key, n.value, n.children)
        self._resolved: dict[str, Node] = {}

    def names(self) -> list[str]:
        return [k for k in self.raw if not k.startswith("^")]

    def inherits_from(self, name: str, templates: set[str], depth: int = 0) -> bool:

        if depth > 8:
            return False
        raw = self.raw.get(name.lower())
        if raw is None:
            return False
        for c in raw.children:
            if c.key == "Inherits" or c.key.startswith("Inherits@"):
                base = c.value.lower()
                if base in templates or self.inherits_from(base, templates, depth + 1):
                    return True
        return False

    def resolve(self, name: str) -> Node | None:
        name = name.lower()
        if name in self._resolved:
            return self._resolved[name]
        raw = self.raw.get(name)
        if raw is None:
            return None


        children: list[Node] = []
        for c in raw.children:
            if c.key == "Inherits" or c.key.startswith("Inherits@"):
                base = self.resolve(c.value)
                if base is not None:
                    children = merge(children, base.children)
            elif c.key.startswith("-"):
                key = c.key[1:]
                children = [o for o in children if o.key != key]
            else:
                children = merge(children, [c])
        node = Node(name, raw.value, resolve_removals(children))
        self._resolved[name] = node
        return node
