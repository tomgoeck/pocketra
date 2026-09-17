#!/usr/bin/env python3

import json
import re
import sys

LINE = re.compile(r"MP-FRAME\s+(\d+)\s+tick\s+(\d+)\s+hash\s+(\S+)")


def read(path):

    out = {}
    with open(path, "r", errors="replace") as f:
        for line in f:
            m = LINE.search(line)
            if m:
                out[int(m.group(1))] = (int(m.group(2)), m.group(3))
                continue
            s = line.strip()
            if not s.startswith("{"):
                continue
            try:
                d = json.loads(s)
            except ValueError:
                continue
            if d.get("t") == "frame" and d.get("hash"):
                out[int(d["f"])] = (int(d.get("tick", -1)), str(d["hash"]))
    return out


def main(argv):
    if len(argv) != 3:
        print(__doc__)
        return 2
    a, b = read(argv[1]), read(argv[2])
    if not a or not b:
        print("FEHLER: keine Rahmenzeilen gefunden (%d / %d)" % (len(a), len(b)))
        return 1
    shared = sorted(set(a) & set(b))
    if not shared:
        print("FEHLER: keine gemeinsamen Rahmen (A %d…%d, B %d…%d)"
              % (min(a), max(a), min(b), max(b)))
        return 1
    for f in shared:
        ta, ha = a[f]
        tb, hb = b[f]
        if ha != hb or ta != tb:
            print("ABWEICHUNG bei Rahmen %d: A tick %d hash %s | B tick %d hash %s"
                  % (f, ta, ha, tb, hb))
            return 1
    print("desync-frei: %d gemeinsame Rahmen bis %d (Tick %d), Hash %s"
          % (len(shared), shared[-1], a[shared[-1]][0], a[shared[-1]][1]))
    only_a = sorted(set(a) - set(b))
    only_b = sorted(set(b) - set(a))
    if only_a or only_b:
        print("nur A: %s   nur B: %s" % (only_a[:5], only_b[:5]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
