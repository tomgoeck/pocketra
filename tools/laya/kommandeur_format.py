
from __future__ import annotations

import json
from typing import Any, Dict, List

INSTRUCTIONS = {
    "doctrine": "Which overall strategy should this AI commander follow for the next minute?",
    "economy": "What should the commander do with the economy right now?",
    "stance": "Which stance should the commander's army take right now?",
    "keep_using_air": "Should the commander keep building and using aircraft?",
    "base_threat": "How strongly is the commander's own base threatened right now?",
    "counter": "Which threat should the commander counter first?",
    "defense_sector": "Where around the base should the next defenses go?",
    "economy_fix": "Which economy problem should be fixed first?",
    "special_op": "Which special operation should the commander launch?",
}

TEXT_KEYS = [
    ("map", "Map"), ("doctrine", "Current doctrine"), ("doctrine_age_s", "Doctrine age in seconds"),
    ("credits", "Money"), ("income", "Income"), ("refineries", "Refineries"), ("power", "Power"),
    ("army", "Own army"), ("enemy", "Enemy seen"), ("air_losses_60s", "Aircraft lost in last 60 s"),
    ("kills_60s", "Enemy units killed in last 60 s"), ("base_damage_60s", "Damage to own base in last 60 s"),
]


STANDARD_QUESTIONS: List[Dict[str, Any]] = [
    {"id": "doctrine", "type": "choice",
     "options": ["land_push", "air_dominance", "naval_dominance", "eco_turtle", "amphibious"],
     "descriptions": ["mass tanks and infantry and attack over land",
                      "build aircraft and strike from the air",
                      "build a navy and attack from the sea",
                      "defend the base and grow the economy first",
                      "carry tanks and infantry in landing craft to the enemy island"]},
    {"id": "economy", "type": "choice", "options": ["more_refineries", "ok", "save_money"],
     "descriptions": ["income is too low, build more refineries and harvesters",
                      "the economy is fine, keep the current balance",
                      "stop extra spending and keep a cash reserve"]},
    {"id": "stance", "type": "choice", "options": ["attack", "hold", "defend", "retreat"],
     "descriptions": ["send the army against the enemy base",
                      "keep the army at the rally point, ready to strike",
                      "pull the army back to guard the own base",
                      "withdraw damaged units and avoid fights"]},
    {"id": "keep_using_air", "type": "noul", "options": ["false", "true"],
     "descriptions": ["stop building aircraft, they die too fast or are not useful here",
                      "keep building and using aircraft"]},
    {"id": "base_threat", "type": "score", "options": ["none", "low", "medium", "high"],
     "descriptions": ["no enemy near the base",
                      "a few enemy scouts or small raids",
                      "a real attack on outlying buildings",
                      "a strong attack on the core of the base"]},
]

EXAMPLE_SUMMARY: Dict[str, Any] = {
    "map": "islands, no land path between the bases",
    "doctrine": "land_push", "doctrine_age_s": "240",
    "credits": "high", "income": "medium", "refineries": "medium", "power": "ok",
    "army": {"land": "medium", "air": "low", "naval": "none"},
    "enemy": {"land": "low", "air": "none", "naval": "medium", "anti_air": "low", "attacking": "no"},
    "air_losses_60s": "none", "kills_60s": "low", "base_damage_60s": "none",
}


def _value_text(v: Any) -> str:
    if isinstance(v, dict):
        return ", ".join("%s %s" % (str(k).replace("_", " "), _value_text(x)) for k, x in v.items())
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return str(v)


def summary_to_text(summary: Dict[str, Any]) -> str:
    parts, seen = [], set()
    for key, name in TEXT_KEYS:
        if key in summary:
            parts.append("%s: %s." % (name, _value_text(summary[key])))
            seen.add(key)
    for key in sorted(k for k in summary if k not in seen):
        parts.append("%s: %s." % (str(key).replace("_", " "), _value_text(summary[key])))
    return "Real-time strategy battle, AI commander report. " + " ".join(parts)


def build_questions(questions: List[Dict[str, Any]]) -> Dict[str, Any]:
    qs: Dict[str, Any] = {}
    for q in questions:
        qid, opts, descs = str(q["id"]), q.get("options", []), q.get("descriptions", [])
        ins = q.get("instructions") or INSTRUCTIONS.get(qid, "Answer the question '%s' for this game state." % qid)
        d: Dict[str, Any] = {"type": q["type"], "instructions": ins}
        if q["type"] == "choice":
            d["criteria"] = {str(o): (str(descs[i]) if i < len(descs) else "") for i, o in enumerate(opts)}
        elif q["type"] == "score":
            d["criteria"] = [str(o) + ((": " + str(descs[i])) if i < len(descs) and descs[i] else "")
                             for i, o in enumerate(opts)]
        elif q["type"] == "noul":
            if len(descs) >= 2:

                flip = len(opts) >= 2 and str(opts[0]).lower() in ("yes", "true")
                d["criteria"] = {"false": str(descs[1] if flip else descs[0]),
                                 "true": str(descs[0] if flip else descs[1])}
        else:
            raise ValueError("unknown question type %r" % q["type"])
        qs[qid] = d
    return qs


def build_request(summary: Dict[str, Any], questions: List[Dict[str, Any]], fmt: str = "text") -> Dict[str, Any]:
    return {"state": summary_to_text(summary) if fmt == "text" else summary,
            "questions": build_questions(questions)}


if __name__ == "__main__":
    print(json.dumps({"summary": EXAMPLE_SUMMARY, "questions": STANDARD_QUESTIONS,
                      "request": build_request(EXAMPLE_SUMMARY, STANDARD_QUESTIONS)},
                     ensure_ascii=False, indent=1))
