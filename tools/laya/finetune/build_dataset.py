#!/usr/bin/env python3

import argparse
import glob
import hashlib
import json
import os
import random
import sys
from typing import Any, Dict, List, Optional

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from kommandeur_format import build_questions, summary_to_text


SIM_QUESTIONS: List[Dict[str, Any]] = [
    {"id": "doctrine", "type": "choice",
     "options": ["land_push", "air_dominance", "naval_dominance", "eco_turtle"],
     "descriptions": ["Win on the ground: tanks and infantry push into the enemy base.",
                      "Win in the air: build aircraft and strike where the enemy has little anti-air.",
                      "Win at sea: build a fleet, control the water and shell the coast.",
                      "Dig in and grow the economy first, attack later."]},
    {"id": "economy", "type": "choice", "options": ["more_refineries", "ok", "save_money"],
     "descriptions": ["Income is too low: build more refineries and harvesters.",
                      "The economy is fine: keep spending as usual.",
                      "Keep a cash reserve instead of spending everything."]},
    {"id": "stance", "type": "choice", "options": ["attack", "hold", "defend", "retreat"],
     "descriptions": ["Our army is stronger: send attack waves now.",
                      "Keep the current pace: gather and attack when ready.",
                      "The base is in danger: keep units at home and build defenses.",
                      "We are losing badly: pull back and rebuild the army."]},
    {"id": "keep_using_air", "type": "noul", "options": ["yes", "no"],
     "descriptions": ["Keep using aircraft for attacks.",
                      "Stop air attacks: losses against enemy anti-air are too high."]},
    {"id": "base_threat", "type": "score", "options": ["none", "low", "medium", "high", "critical"],
     "descriptions": ["No enemy near the base.", "A few enemies near the base.", "The base is under attack.",
                      "The base is under heavy attack.", "The base is about to fall."]},


    {"id": "counter", "type": "choice",
     "instructions": "Which threat should the commander counter first?",
     "options": ["none", "anti_air", "anti_siege_sortie", "spread_defense", "anti_infiltration", "anti_naval"],
     "descriptions": ["No special threat: keep the normal plan.",
                      "Enemy aircraft hit the base: build anti-air where they strike.",
                      "Enemy artillery outranges our towers: send fast units out to kill it.",
                      "Attacks come from several sides: spread towers around the base.",
                      "Commandos, engineers or spies may sneak in: guard the open side of the base.",
                      "The enemy attacks from the sea: build ships and coastal defense."]},
    {"id": "defense_sector", "type": "choice",
     "instructions": "Where around the base should the next defenses go?",
     "options": ["none", "n", "ne", "e", "se", "s", "sw", "w", "nw"],
     "descriptions": ["No preference: place defenses as usual."] +
                     ["Build new defenses %s of the base center." % d for d in
                      ("north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west")]},
    {"id": "economy_fix", "type": "choice",
     "instructions": "Which economy problem should be fixed first?",
     "options": ["none", "silo", "refinery", "harvester"],
     "descriptions": ["The economy needs no fix.", "Storage is full and ore is wasted: build a silo.",
                      "Income is too low: build another refinery.", "Harvesters were lost: build a new harvester."]},
    {"id": "special_op", "type": "choice",
     "instructions": "Which special operation should the commander launch?",
     "options": ["none", "commando_raid", "engineer_capture", "spy_infiltrate", "superweapon_now"],
     "descriptions": ["No special operation now.", "Send a commando into a weakly guarded enemy building.",
                      "Send an engineer to capture an enemy building.", "Send a spy into an enemy building.",
                      "Fire the ready superweapon at the enemy base now."]},
]
SIM_QMAP = {q["id"]: q for q in SIM_QUESTIONS}


SUMMARY_ORDER = {"army": ["land", "air", "naval"],
                 "enemy": ["land", "air", "naval", "anti_air", "attacking"],
                 "enemy_class": ["siege", "armor", "infantry", "air", "naval", "subs", "commando", "engineer", "spy"],
                 "damage_60s": ["air", "land", "naval", "siege"],
                 "own_defense": ["ground", "anti_air"],
                 "superweapon": ["own", "enemy"],
                 "own_special": ["commando", "engineer", "spy"]}


def sim_order(summary: Dict[str, Any]) -> Dict[str, Any]:
    out = dict(summary)
    for key, order in SUMMARY_ORDER.items():
        v = out.get(key)
        if isinstance(v, dict):
            out[key] = {k: v[k] for k in order if k in v}
            out[key].update({k: x for k, x in v.items() if k not in out[key]})
    return out


def resolve_questions(r: Dict[str, Any], field: str):

    qs = r.get("questions") or []
    answer = dict(r.get(field) or {})
    if not qs or isinstance(qs[0], dict):
        return qs, answer
    out = []
    for qid in qs:
        base = SIM_QMAP.get(str(qid))
        if base is None:
            continue
        q = {k: (list(v) if isinstance(v, list) else v) for k, v in base.items()}
        v = answer.get(q["id"])
        if q["type"] == "choice" and isinstance(v, dict):
            for extra in v:
                if extra not in q["options"]:
                    q["options"].append(extra)
                    q["descriptions"].append("")
        elif q["type"] in ("noul", "score") and isinstance(v, (int, float)) and not isinstance(v, bool):
            answer[q["id"]] = float(v) / 1000.0
        out.append(q)
    return out, answer


def smooth(dist: List[float], eps: float) -> List[float]:
    s = sum(dist)
    dist = [d / s for d in dist] if s > 0 else [1.0 / len(dist)] * len(dist)
    k = len(dist)
    return [(1 - eps) * d + eps / k for d in dist]


def gold_for(q: Dict[str, Any], value: Any, eps: float) -> Optional[Dict[str, Any]]:
    opts = [str(o) for o in q.get("options", [])]
    t = q["type"]
    if t == "choice":
        if isinstance(value, dict):
            dist = [max(0.0, float(value.get(o, 0.0))) for o in opts]
            if sum(dist) <= 0:
                return None
            dist = smooth(dist, 0.0)
        elif str(value) in opts:
            dist = smooth([1.0 if o == str(value) else 0.0 for o in opts], eps)
        else:
            return None
        probs = dict(zip(opts, dist))
        return {"label": max(probs, key=probs.get), "probabilities": probs}
    if t == "noul":
        if isinstance(value, bool):
            p = 1 - eps / 2 if value else eps / 2
        elif isinstance(value, (int, float)):
            p = min(1.0, max(0.0, float(value)))
        elif str(value).lower() in ("true", "false"):
            p = 1 - eps / 2 if str(value).lower() == "true" else eps / 2
        else:
            return None
        return {"label": "true" if p >= 0.5 else "false", "noul": p,
                "probabilities": {"false": 1 - p, "true": p}}
    if t == "score":
        k = len(opts)
        if k < 2:
            return None
        if isinstance(value, dict):
            dist = [float(value.get(o, value.get(str(i), 0.0))) for i, o in enumerate(opts)]
            dist = smooth(dist, 0.0)
        else:
            if isinstance(value, (int, float)) and not isinstance(value, bool):
                x = min(1.0, max(0.0, float(value))) * (k - 1)
            elif str(value) in opts:
                x = float(opts.index(str(value)))
            else:
                return None
            lo = int(x)
            dist = [0.0] * k
            dist[lo] = 1.0 - (x - lo)
            if lo + 1 < k:
                dist[lo + 1] = x - lo
            dist = smooth(dist, eps)
        probs = {str(i): p for i, p in enumerate(dist)}
        exp = sum(i * p for i, p in enumerate(dist))
        return {"label": int(max(range(k), key=lambda i: dist[i])), "score": exp, "probabilities": probs}
    return None


def read_match(path: str):
    rows, end = [], None
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("KOMMANDEUR "):
                line = line[len("KOMMANDEUR "):]
            elif line.startswith("KOMMANDEUR-SPIELER "):
                line = line[len("KOMMANDEUR-SPIELER "):]
            if not line:
                continue
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if "winner" in d and "summary" not in d:
                end = d
            else:
                rows.append(d)
    return rows, end


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--logs", default="build/ai_log", help="Ordner mit *.jsonl")
    ap.add_argument("--out", default="build/laya/dataset")
    ap.add_argument("--field", default="decision", help="decision oder directive")
    ap.add_argument("--eps", type=float, default=0.1, help="Label-Glaettung fuer harte Wahl")
    ap.add_argument("--test-share", type=float, default=0.1, help="Anteil Partien fuer test.jsonl")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--no-dedupe", action="store_true")
    ap.add_argument("--who", default="winner", choices=["winner", "survivors", "all"],
                    help="Entscheidungen welcher Bots: Sieger, am Ende lebende Bots oder alle")
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(args.logs, "*.jsonl")))
    if not files:
        raise SystemExit("keine Protokolle in %s" % args.logs)
    random.Random(args.seed).shuffle(files)
    n_test = int(round(len(files) * args.test_share)) if len(files) > 1 else 0
    split = {f: ("test" if i < n_test else "train") for i, f in enumerate(files)}

    os.makedirs(args.out, exist_ok=True)
    outs = {s: open(os.path.join(args.out, s + ".jsonl"), "w") for s in ("train", "test")}
    stats = {"matches": len(files), "no_winner": 0, "rows_seen": 0, "rows_winner": 0, "rows_by_split": {"train": 0, "test": 0}, "written": 0,
             "duplicates": 0, "bad_answers": 0, "sources": {}}
    seen = set()
    for path in files:
        rows, end = read_match(path)
        stats["rows_seen"] += len(rows)
        has_winner = bool(end) and end.get("winner") not in (None, -1)
        if not has_winner:
            stats["no_winner"] += 1
        if args.who == "winner":
            if not has_winner:
                continue
            keep = {int(end["winner"])}
        elif args.who == "survivors":
            alive = (end or {}).get("alive") or {}
            keep = {int(p) for p, n in alive.items() if int(n) > 0}
        else:
            keep = None
        for i, r in enumerate(rows):
            if keep is not None and int(r.get("player", -1)) not in keep:
                continue
            stats["rows_winner"] += 1
            qs, answer = resolve_questions(r, args.field)
            gold = {}
            for q in qs:
                g = gold_for(q, answer.get(q["id"]), args.eps)
                if g is None:
                    stats["bad_answers"] += 1
                    continue
                gold[q["id"]] = g
            if not gold:
                continue
            kept = [q for q in qs if q["id"] in gold]
            state = summary_to_text(sim_order(r["summary"]))
            questions = build_questions(kept)
            key = hashlib.sha1(json.dumps([state, gold], sort_keys=True).encode()).hexdigest()
            if key in seen and not args.no_dedupe:
                stats["duplicates"] += 1
                continue
            seen.add(key)
            src = str(r.get("source", "?"))
            stats["sources"][src] = stats["sources"].get(src, 0) + 1
            row = {"id": "%s#%d" % (os.path.basename(path), i), "match": os.path.basename(path),
                   "workflow": "pocketra_commander_%s" % r.get("map_type", "unknown"),
                   "state": json.dumps(state, ensure_ascii=False),
                   "questions": json.dumps(questions, ensure_ascii=False),
                   "gold": json.dumps(gold, ensure_ascii=False)}
            outs[split[path]].write(json.dumps(row, ensure_ascii=False) + "\n")
            stats["written"] += 1
            stats["rows_by_split"][split[path]] += 1
    for f in outs.values():
        f.close()
    print(json.dumps(stats, indent=1))


if __name__ == "__main__":
    main()
