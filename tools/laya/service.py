#!/usr/bin/env python3


import asyncio
import json
import os
import sys
import time
from contextlib import asynccontextmanager
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Dict, List

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from laya_core import LayaModel, QuestionError, default_model_dir

MAX_BODY_BYTES = 256 * 1024
MAX_QUESTIONS = 16
MAX_STATE_CHARS = 8000


def env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except ValueError:
        return default


class Batcher:


    def __init__(self, model: LayaModel, window_ms: int, max_rows: int, keepwarm_s: int = 0):
        self.model = model
        self.keepwarm = keepwarm_s


        _, _, self.warm_rows = model.encode_request("warm up", {"w": {"type": "noul", "instructions": "ok?"}})
        self.window = window_ms / 1000.0
        self.max_rows = max_rows
        self.queue: asyncio.Queue = asyncio.Queue()
        self.pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="laya-infer")
        self.task = None
        self.stats = {"requests": 0, "runs": 0, "rows": 0, "errors": 0}

    def start(self) -> None:
        self.task = asyncio.get_running_loop().create_task(self._loop())

    async def submit(self, state, questions) -> Dict[str, Any]:

        ids, internal, rows = self.model.encode_request(state, questions)
        fut = asyncio.get_running_loop().create_future()
        await self.queue.put((time.perf_counter(), ids, internal, rows, fut))
        return await fut

    async def _loop(self) -> None:
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(self.pool, self.model.run_rows, self.warm_rows)
        while True:
            try:
                first = await asyncio.wait_for(self.queue.get(), self.keepwarm) if self.keepwarm > 0 \
                    else await self.queue.get()
            except asyncio.TimeoutError:
                await loop.run_in_executor(self.pool, self.model.run_rows, self.warm_rows)
                continue
            batch = [first]
            nrows = len(first[3])
            deadline = first[0] + self.window
            while nrows < self.max_rows:
                timeout = deadline - time.perf_counter()
                try:
                    item = self.queue.get_nowait() if timeout <= 0 else \
                        await asyncio.wait_for(self.queue.get(), timeout)
                except (asyncio.TimeoutError, asyncio.QueueEmpty):
                    break
                batch.append(item)
                nrows += len(item[3])
            rows = [r for item in batch for r in item[3]]
            t0 = time.perf_counter()
            try:
                logits, act = await loop.run_in_executor(self.pool, self.model.run_rows, rows)
            except Exception as exc:
                self.stats["errors"] += 1
                for item in batch:
                    if not item[4].done():
                        item[4].set_exception(exc)
                continue
            t1 = time.perf_counter()
            self.stats["runs"] += 1
            self.stats["rows"] += len(rows)
            self.stats["requests"] += len(batch)
            offset = 0
            for arrived, ids, internal, item_rows, fut in batch:
                answers = self.model.decode(logits, act, item_rows, ids, internal, offset)
                offset += len(item_rows)
                if not fut.done():
                    fut.set_result({
                        "answers": answers,
                        "usage": {"input_tokens": int(sum(len(r["ids"]) for r in item_rows)),
                                  "output_tokens": 0},
                        "timing": {"queue_ms": round((t0 - arrived) * 1000, 1),
                                   "infer_ms": round((t1 - t0) * 1000, 1),
                                   "batch_requests": len(batch), "batch_rows": len(rows)},
                    })


def create_app():
    from fastapi import FastAPI, HTTPException, Request
    from fastapi.middleware.cors import CORSMiddleware
    from fastapi.responses import JSONResponse

    model_dir = os.environ.get("LAYA_MODEL_DIR") or default_model_dir()
    state: Dict[str, Any] = {}

    @asynccontextmanager
    async def lifespan(_app):
        t0 = time.perf_counter()
        model = LayaModel(model_dir, threads=env_int("LAYA_THREADS", 0))
        state["load_s"] = round(time.perf_counter() - t0, 2)
        state["model"] = model
        state["batcher"] = Batcher(model, env_int("LAYA_BATCH_WINDOW_MS", 75),
                                   env_int("LAYA_MAX_BATCH_ROWS", 64), env_int("LAYA_KEEPWARM_S", 15))
        state["batcher"].start()
        print("LAYA-DIENST bereit modell=%s ladezeit_s=%s" % (model_dir, state["load_s"]), flush=True)
        yield

    app = FastAPI(title="PocketRA Laya-Dienst", lifespan=lifespan)
    origins = [o.strip() for o in os.environ.get("LAYA_CORS_ORIGINS", "*").split(",") if o.strip()]
    app.add_middleware(CORSMiddleware, allow_origins=origins, allow_methods=["GET", "POST", "OPTIONS"],
                       allow_headers=["Content-Type"], max_age=600,

                       allow_private_network=True)

    @app.get("/health")
    def health():
        import psutil
        import resource
        b = state.get("batcher")
        return {"ok": "model" in state, "model_dir": model_dir, "load_s": state.get("load_s"),
                "rss_mb": round(psutil.Process().memory_info().rss / 1e6, 1),

                "peak_rss_mb": round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
                                     / (1e6 if sys.platform == "darwin" else 1e3), 1),
                "stats": b.stats if b else None}

    @app.post("/decide")
    async def decide(request: Request):
        raw = await request.body()
        if len(raw) > MAX_BODY_BYTES:
            raise HTTPException(413, "request body too large")
        try:
            body = json.loads(raw)
        except (ValueError, RecursionError):
            raise HTTPException(400, "request body must be valid JSON")
        if not isinstance(body, dict) or body.get("state") is None or not isinstance(body.get("questions"), dict):
            raise HTTPException(400, "body must be {state, questions}")
        st, qs = body["state"], body["questions"]
        if len(qs) > MAX_QUESTIONS:
            raise HTTPException(413, "too many questions")
        if len(st if isinstance(st, str) else json.dumps(st)) > MAX_STATE_CHARS:
            raise HTTPException(413, "state too large")
        t0 = time.perf_counter()
        try:
            result = await state["batcher"].submit(st, qs)
        except QuestionError as e:
            raise HTTPException(422, str(e))
        except Exception:
            raise HTTPException(500, "inference failed")
        result["model"] = os.path.basename(model_dir.rstrip("/"))
        result["latency_ms"] = round((time.perf_counter() - t0) * 1000, 1)
        return JSONResponse(result, headers={"X-Inference-Time-Ms": str(result["timing"]["infer_ms"])})

    return app


def main() -> None:
    import uvicorn
    uvicorn.run(create_app(), host=os.environ.get("LAYA_HOST", "127.0.0.1"),
                port=env_int("LAYA_PORT", 8765), log_level=os.environ.get("LAYA_LOG_LEVEL", "warning"),
                access_log=False)


if __name__ == "__main__":
    main()
