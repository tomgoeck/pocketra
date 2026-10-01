#!/usr/bin/env python3

import argparse
import json
import sys
import os

import httpx

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kommandeur_format import EXAMPLE_SUMMARY, STANDARD_QUESTIONS, build_request

BASE = {"doctrine": "land_push", "doctrine_age_s": "120", "power": "ok"}


PROBES = [
    ("Inselkarte ohne Landweg", EXAMPLE_SUMMARY,
     {"doctrine": {"naval_dominance", "air_dominance"}}),
    ("Luftverluste hoch, Flak stark", dict(BASE, map="large land map, all bases connected by land",
        credits="medium", income="medium", refineries="medium",
        army={"land": "medium", "air": "low", "naval": "none"},
        enemy={"land": "medium", "air": "none", "naval": "none", "anti_air": "strong", "attacking": "no"},
        air_losses_60s="high", kills_60s="none", base_damage_60s="none"),
     {"doctrine": {"land_push", "eco_turtle"}, "keep_using_air": "<0.5"}),
    ("Basis unter schwerem Angriff", dict(BASE, map="land map", credits="low", income="low", refineries="low",
        army={"land": "low", "air": "none", "naval": "none"},
        enemy={"land": "strong", "air": "low", "naval": "none", "anti_air": "low", "attacking": "yes, at our base"},
        air_losses_60s="none", kills_60s="low", base_damage_60s="high"),
     {"stance": {"defend", "retreat"}, "base_threat": ">=0.66"}),
    ("Pleite, eine Raffinerie", dict(BASE, map="land map", credits="none", income="low", refineries="low",
        army={"land": "low", "air": "none", "naval": "none"},
        enemy={"land": "low", "air": "none", "naval": "none", "anti_air": "low", "attacking": "no"},
        air_losses_60s="none", kills_60s="none", base_damage_60s="none"),
     {"economy": {"more_refineries"}, "base_threat": "<=0.34"}),
    ("Eigene Armee stark, Gegner schwach", dict(BASE, map="land map", credits="high", income="high",
        refineries="high", army={"land": "strong", "air": "medium", "naval": "none"},
        enemy={"land": "low", "air": "none", "naval": "none", "anti_air": "low", "attacking": "no"},
        air_losses_60s="none", kills_60s="high", base_damage_60s="none"),
     {"stance": {"attack"}, "doctrine": {"land_push", "air_dominance"}}),
]


def sim_summary(**kw):

    d = {"tick": 6000, "map_type": "land", "water_permille": 0, "landmasses": 1, "enemy_starts": 1,
         "land_connected": 1, "ore_fields": 6, "credits": "medium", "income": "flat", "income_60s": 400,
         "refineries": "medium", "power": "ok",
         "army": {"land": "medium", "air": "none", "naval": "none"},
         "enemy": {"land": "medium", "air": "none", "naval": "none", "anti_air": "low", "attacking": False},
         "air_losses_60s": "none", "land_losses_60s": "none", "kills_60s": "none", "base_damage_60s": "none",
         "base_threat": 0, "doctrine": "land_push", "doctrine_age_s": 120, "opening_done": True}
    for k, v in kw.items():
        if isinstance(v, dict) and isinstance(d.get(k), dict):
            d[k] = dict(d[k], **v)
        else:
            d[k] = v
    return d


SIM_PROBES = [
    ("Inselkarte ohne Landweg", sim_summary(map_type="islands", water_permille=650, landmasses=17,
        enemy_starts=1, land_connected=0, credits="high", income="flat",
        army={"land": "medium", "air": "low", "naval": "none"},
        enemy={"land": "low", "naval": "medium", "anti_air": "low"}, kills_60s="low"),
     PROBES[0][2]),
    ("Luftverluste hoch, Flak stark", sim_summary(army={"land": "medium", "air": "low"},
        enemy={"land": "medium", "anti_air": "strong"}, air_losses_60s="high"),
     PROBES[1][2]),
    ("Basis unter schwerem Angriff", sim_summary(credits="low", income="falling", refineries="low",
        army={"land": "low"}, enemy={"land": "strong", "air": "low", "attacking": True},
        land_losses_60s="high", kills_60s="low", base_damage_60s="high", base_threat=850),
     PROBES[2][2]),
    ("Pleite, eine Raffinerie", sim_summary(credits="none", income="falling", income_60s=0, refineries="low",
        army={"land": "low"}, enemy={"land": "low"}),
     PROBES[3][2]),
    ("Eigene Armee stark, Gegner schwach", sim_summary(credits="high", income="rising", income_60s=1500,
        refineries="high", army={"land": "strong", "air": "medium"}, enemy={"land": "low"}, kills_60s="high"),
     PROBES[4][2]),
]


def check(ans, want) -> bool:
    if isinstance(want, set):
        return max(ans, key=ans.get) in want
    op = want[:2] if want[1] == "=" else want[0]
    x = float(want[len(op):])
    return {"<": ans < x, ">": ans > x, "<=": ans <= x, ">=": ans >= x}[op]


def flatten(answers, q):
    a = answers[q["id"]]
    if q["type"] == "choice":
        return a["probabilities"]
    if q["type"] == "noul":
        return a["noul"]
    return a["score"] / (len(q["options"]) - 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8765/decide")
    ap.add_argument("--sim", action="store_true", help="Fragen und Zusammenfassung im Sim-Format (Text)")
    args = ap.parse_args()
    questions, probes, formats = STANDARD_QUESTIONS, PROBES, ("text", "json")
    if args.sim:
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "finetune"))
        from build_dataset import SIM_QUESTIONS
        questions, probes, formats = SIM_QUESTIONS, SIM_PROBES, ("text",)
    qmap = {q["id"]: q for q in questions}
    score = {f: [0, 0] for f in formats}
    for name, summary, want in probes:
        print("\n## " + name)
        for fmt in formats:
            r = httpx.post(args.url, json=build_request(summary, questions, fmt), timeout=30).json()
            line = []
            for q in questions:
                v = flatten(r["answers"], q)
                if isinstance(v, dict):
                    top = max(v, key=v.get)
                    line.append("%s=%s(%.2f)" % (q["id"], top, v[top]))
                else:
                    line.append("%s=%.2f" % (q["id"], v))
            hits = []
            for qid, w in want.items():
                ok = check(flatten(r["answers"], qmap[qid]), w)
                hits.append("%s:%s" % (qid, "ok" if ok else "FALSCH"))
                score[fmt][0] += ok
                score[fmt][1] += 1
            print("  %-4s tokens=%-4d %s\n       Erwartung: %s" % (fmt, r["usage"]["input_tokens"],
                                                                   "  ".join(line), " ".join(hits)))
    for fmt, (ok, n) in score.items():
        print("\n%s%s: %d von %d Erwartungen getroffen" % ("sim-" if args.sim else "", fmt, ok, n))


if __name__ == "__main__":
    main()
