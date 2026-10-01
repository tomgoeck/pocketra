
from __future__ import annotations

import json
import math
import os
import threading
from typing import Any, Dict, List, Optional, Tuple, Union

import numpy as np


ATTRIBUTION = ("Portions ported from Laya (https://github.com/NandhaKishorM/laya), "
               "by Convai Innovations, Apache License 2.0: laya/common.py, laya/onnx_agent.py.")

QTYPES = {"choice": 0, "score": 1, "noul": 2}
QTYPE_NAMES = {v: k for k, v in QTYPES.items()}
TEMP_MIN = 0.5
TEMP_MAX = 5.0
OPTION_TOKEN_CAP = 48


class QuestionError(ValueError):
    pass


def serialize_state(state: Union[str, dict, list]) -> str:
    if isinstance(state, str):
        return state
    return json.dumps(state, ensure_ascii=False)


def render_criterion(value) -> str:
    if isinstance(value, str):
        return value
    return json.dumps(value, ensure_ascii=False, separators=(", ", ": "), default=str)


def render_options(q: Dict) -> List[str]:

    t, crit = q["t"], q.get("crit")
    if t == "choice":
        return [str(k) if v is None or v == "" else "%s: %s" % (k, render_criterion(v))
                for k, v in crit.items()]
    if t == "score":
        return ["level %d: %s" % (i, render_criterion(c)) for i, c in enumerate(crit)]
    crit = crit or {}
    false_crit, true_crit = crit.get("false"), crit.get("true")
    return [
        "false: " + (render_criterion(false_crit) if false_crit not in (None, "")
                     else "no, the statement does not hold"),
        "true: " + (render_criterion(true_crit) if true_crit not in (None, "")
                    else "yes, the statement holds"),
    ]


def clamp_temperature(t, lo: float = TEMP_MIN, hi: float = TEMP_MAX) -> float:
    try:
        t = float(t)
    except (TypeError, ValueError):
        return 1.0
    if t != t or t in (float("inf"), float("-inf")):
        return 1.0
    return min(hi, max(lo, t))


def temp_bucket(qtype: int, k: int) -> str:
    size = "2" if k <= 2 else "3-5" if k <= 5 else "6-10" if k <= 10 else "11+"
    return "%s:%s" % (QTYPE_NAMES[int(qtype)], size)


def answer_confidence(p: np.ndarray, k: int) -> float:
    if k < 1:
        return 1.0
    return float(np.clip(np.max(p[:k]), 0.0, 1.0))


def confidence_from_probs(p: np.ndarray, k: int) -> float:
    if k < 2:
        return 1.0
    p = p[:k]
    ent = -(p * np.log(np.clip(p, 1e-12, 1.0))).sum()
    return float(np.clip(1.0 - ent / math.log(k), 0.0, 1.0))


def to_internal(qid: str, qdef: Any) -> Dict:

    if not isinstance(qdef, dict):
        raise QuestionError("question %r: definition must be an object" % qid)
    t = qdef.get("type")
    if t not in QTYPES:
        raise QuestionError("question %r: unknown type %r; use choice, score or noul" % (qid, t))
    if "instructions" not in qdef:
        raise QuestionError("question %r: no 'instructions'" % qid)
    crit = qdef.get("criteria")
    if t == "choice":
        if isinstance(crit, list):
            if len(set(map(str, crit))) != len(crit):
                raise QuestionError("question %r: duplicate choice labels" % qid)
            crit = {str(c): None for c in crit}
        if not isinstance(crit, dict) or not crit:
            raise QuestionError("question %r: choice needs 'criteria' as label -> description" % qid)
    elif t == "score":
        if not isinstance(crit, list) or not crit or any(c is None for c in crit):
            raise QuestionError("question %r: score needs 'criteria' as a list of level descriptions" % qid)
    else:
        if crit is not None and not isinstance(crit, dict):
            raise QuestionError("question %r: noul 'criteria' must be {true: ..., false: ...}" % qid)
        crit = {str(k).lower(): v for k, v in (crit or {}).items()}
    ins = qdef["instructions"]
    if not isinstance(ins, str):
        ins = json.dumps(ins, ensure_ascii=False)
    return {"t": t, "ins": ins, "crit": crit}


def default_model_dir() -> str:

    here = os.path.dirname(os.path.abspath(__file__))
    try:
        import subprocess
        common = subprocess.check_output(
            ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
            cwd=here, text=True, stderr=subprocess.DEVNULL).strip()
        root = os.path.dirname(common)
    except Exception:
        root = os.path.dirname(os.path.dirname(here))
    return os.path.join(root, "build", "laya", "multilingual-int8")


class LayaModel:


    def __init__(self, model_dir: str, threads: int = 0):
        import onnxruntime as ort
        from tokenizers import Tokenizer

        self.model_dir = model_dir
        with open(os.path.join(model_dir, "rl_agent_config.json")) as f:
            self.cfg = json.load(f)
        tok_dir = os.path.join(model_dir, "tokenizer")
        self.tok = Tokenizer.from_file(os.path.join(tok_dir, "tokenizer.json"))
        self.tok.no_truncation()
        self.tok.no_padding()
        with open(os.path.join(tok_dir, "tokenizer_config.json")) as f:
            tcfg = json.load(f)

        def special(name: str) -> Tuple[str, int]:
            text = tcfg[name]
            if isinstance(text, dict):
                text = text.get("content")
            tid = self.tok.token_to_id(text)
            if tid is None:
                raise RuntimeError("tokenizer: %s %r fehlt im Vokabular" % (name, text))
            return text, tid

        self.mask_text, self.mask_id = special("mask_token")
        _, self.cls_id = special("cls_token")
        _, self.sep_id = special("sep_token")
        _, self.pad_id = special("pad_token")
        self._tok_lock = threading.Lock()
        self._cache: Dict[Tuple[str, int], Tuple[int, ...]] = {}

        so = ort.SessionOptions()
        so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        if threads > 0:
            so.intra_op_num_threads = threads
        self.session = ort.InferenceSession(os.path.join(model_dir, "model.onnx"),
                                            sess_options=so, providers=["CPUExecutionProvider"])
        self.max_len = int(self.cfg.get("max_len", 512))
        self.head_max_len = int(self.cfg.get("head_max_len", 192))
        self.temperature = [clamp_temperature(t) for t in self.cfg.get("temperature", [1.0, 1.0, 1.0])]
        self.temperature_by_options = {k: clamp_temperature(v)
                                       for k, v in (self.cfg.get("temperature_by_options") or {}).items()}


    def encode(self, text: str) -> List[int]:
        with self._tok_lock:
            return list(self.tok.encode(text, add_special_tokens=False).ids)

    def _encode_cached(self, text: str, cap: int = 0) -> List[int]:

        key = (text, cap)
        hit = self._cache.get(key)
        if hit is None:
            ids = self.encode(text)
            hit = tuple(ids[:cap] if cap else ids)
            if len(self._cache) > 4096:
                self._cache.clear()
            self._cache[key] = hit
        return list(hit)

    def build_sequence(self, q: Dict, state_ids: List[int], max_len: int, head_max_len: int):

        opts = render_options(q)
        ins = str(q["ins"]).replace(self.mask_text, " ")
        head_ids = self._encode_cached("%s question: %s" % (q["t"], ins))
        opt_ids = [[self.mask_id] + self._encode_cached(" " + o.replace(self.mask_text, " "),
                                                         OPTION_TOKEN_CAP) for o in opts]
        opt_budget = head_max_len - sum(len(o) for o in opt_ids)
        if opt_budget < 16:
            per = max(4, (head_max_len - 16) // max(1, len(opt_ids)))
            opt_ids = [o[:per] for o in opt_ids]
            opt_budget = head_max_len - sum(len(o) for o in opt_ids)
        head_ids = head_ids[: max(8, opt_budget)]
        ids = [self.cls_id] + head_ids + [self.sep_id]
        markers = []
        for o in opt_ids:
            markers.append(len(ids))
            ids.extend(o)
        ids.append(self.sep_id)
        room = max(0, max_len - len(ids) - 1)
        ids = ids + state_ids[:room] + [self.sep_id]
        ids, markers = ids[:max_len], [m for m in markers if m < max_len]
        if len(markers) != len(opts):
            raise QuestionError("options and question text need more than max_len=%d tokens" % max_len)
        return ids, markers

    def encode_request(self, state, questions: Dict[str, Any]) -> Tuple[List[str], Dict, List[Dict]]:

        if not isinstance(questions, dict) or not questions:
            raise QuestionError("'questions' must be a non-empty object")
        ids = list(questions.keys())
        internal = {qid: to_internal(qid, questions[qid]) for qid in ids}
        state_ids = self.encode(serialize_state(state).replace(self.mask_text, " "))
        rows = []
        for qid in ids:
            q = internal[qid]
            seq, markers = self.build_sequence(q, state_ids, self.max_len, self.head_max_len)
            rows.append({"ids": seq, "markers": markers, "qtype": QTYPES[q["t"]]})
        return ids, internal, rows


    def run_rows(self, rows: List[Dict]) -> Tuple[np.ndarray, np.ndarray]:

        n = len(rows)
        L = max(len(r["ids"]) for r in rows)
        kmax = max(len(r["markers"]) for r in rows)
        input_ids = np.full((n, L), self.pad_id, dtype=np.int64)
        att = np.zeros((n, L), dtype=np.int64)
        mpos = np.zeros((n, kmax), dtype=np.int64)
        mmask = np.zeros((n, kmax), dtype=bool)
        for i, r in enumerate(rows):
            input_ids[i, :len(r["ids"])] = r["ids"]
            att[i, :len(r["ids"])] = 1
            k = len(r["markers"])
            mpos[i, :k] = r["markers"]
            mmask[i, :k] = True
        qtype = np.array([r["qtype"] for r in rows], dtype=np.int64)
        logits, act_logits = self.session.run(["logits", "act_logits"], {
            "input_ids": input_ids, "attention_mask": att,
            "marker_pos": mpos, "marker_mask": mmask, "qtype": qtype})
        act = np.exp(act_logits - act_logits.max(axis=-1, keepdims=True))
        act = act / act.sum(axis=-1, keepdims=True)
        return logits, act

    def decode(self, logits, act, rows, ids, internal, offset: int) -> Dict[str, Any]:

        answers = {}
        for r, qid in enumerate(ids):
            q = internal[qid]
            k = len(rows[r]["markers"])
            qt = QTYPES[q["t"]]
            t_scale = self.temperature_by_options.get(temp_bucket(qt, k), self.temperature[qt])
            z = logits[offset + r, :k].astype(np.float64) / t_scale
            p = np.exp(z - z.max())
            p = p / p.sum()
            conf = round(confidence_from_probs(p, k), 4)
            ans_conf = round(answer_confidence(p, k), 4)
            ext = {"act_probability": round(float(act[offset + r, 0]), 4)}
            if q["t"] == "choice":
                keys = list(q["crit"].keys())
                answers[qid] = {"type": "choice", "choice": keys[int(p.argmax())],
                                "probabilities": {kk: round(float(v), 4) for kk, v in zip(keys, p)},
                                "confidence": conf, "answer_confidence": ans_conf, "action": ext}
            elif q["t"] == "score":
                answers[qid] = {"type": "score", "score": round(float((np.arange(k) * p).sum()), 4),
                                "legend": {str(i): c for i, c in enumerate(q["crit"])},
                                "probabilities": {str(i): round(float(v), 4) for i, v in enumerate(p)},
                                "confidence": conf, "answer_confidence": ans_conf, "action": ext}
            else:
                answers[qid] = {"type": "noul", "noul": round(float(p[1]), 4),
                                "confidence": round(max(float(p[1]), 1.0 - float(p[1])), 4),
                                "answer_confidence": ans_conf, "action": ext}
        return answers

    def predict(self, state, questions: Dict[str, Any]) -> Dict[str, Any]:

        ids, internal, rows = self.encode_request(state, questions)
        logits, act = self.run_rows(rows)
        return {"answers": self.decode(logits, act, rows, ids, internal, 0),
                "usage": {"input_tokens": int(sum(len(r["ids"]) for r in rows)), "output_tokens": 0}}
