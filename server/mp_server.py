#!/usr/bin/env python3


import argparse
import asyncio
import json
import re
import secrets
import sys
import time
from collections import deque

try:
    from websockets.asyncio.server import serve as ws_serve
except ImportError:
    from websockets.legacy.server import serve as ws_serve
try:
    from websockets.exceptions import ConnectionClosed
except ImportError:
    ConnectionClosed = OSError

PROTO = 1
SERVER_NAME = "pocketra-mp/1"

CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
CODE_LEN = 6
MAX_PLAYERS_CAP = 8
MAX_ROOMS_DEFAULT = 50

MAX_MSG_BYTES = 16 * 1024
MAX_LEAD = 40
NAME_MAX = 24
CHAT_MAX = 200


VOICE_MAX = 4096
VOICE_BURST, VOICE_WINDOW = 150, 5.0
VOICE_WARN_EVERY = 1.0
VOICE_SPURT_GAP = 2.0
VOICE_CODEC = "adpcm8"
VOICE_B64 = re.compile(r"[A-Za-z0-9+/=]*\Z")

CHAT_BURST, CHAT_WINDOW = 5, 5.0
LIST_BURST, LIST_WINDOW = 1, 2.0
LIST_MAX = 30
MSG_BURST, MSG_WINDOW = 60, 5.0
ORDER_BURST, ORDER_WINDOW = 600, 5.0
CREATE_PER_MIN = 5
JOIN_PER_MIN = 20
BAD_CODE_LIMIT = 3
BAN_S = 60.0

LOBBY_IDLE_S = 30 * 60.0
GAME_IDLE_S = 5 * 60.0
WATCHDOG_S = 0.1


RESUME_S_DEFAULT = 180.0
TOKEN_BYTES = 12

FACTION_MAX = 16
TEAM_MAX = 8
COLOR_MAX = 15
SPAWN_MAX = 7

CLIENT_TYPES = {"hello", "create", "join", "map", "slot", "bot", "kick", "ready",
                "start", "order", "chat", "voice", "ping", "leave", "list", "visibility",
                "resume", "watch"}


def log(event, **kw):
    parts = [time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime()), event]
    for k, v in kw.items():
        if v is None:
            continue
        s = str(v)
        if len(s) > 120:
            s = s[:117] + "..."
        if " " in s:
            s = '"' + s.replace('"', "'") + '"'
        parts.append("%s=%s" % (k, s))
    print(" ".join(parts), flush=True)


def now():
    return time.monotonic()


def ts_ms():
    return int(time.time() * 1000)


def clean_text(s, limit):
    if not isinstance(s, str):
        return ""
    s = "".join(ch for ch in s if ch >= " " and ch != "\x7f")
    s = s.replace("<", "(").replace(">", ")")
    return s.strip()[:limit]


def clamp_int(v, lo, hi, default=0):
    if isinstance(v, bool) or not isinstance(v, int):
        return default
    return lo if v < lo else (hi if v > hi else v)


class Bucket:


    def __init__(self, burst, window):
        self.burst, self.window, self.hits = burst, window, deque()

    def allow(self, t=None):
        t = now() if t is None else t
        while self.hits and t - self.hits[0] > self.window:
            self.hits.popleft()
        if len(self.hits) >= self.burst:
            return False
        self.hits.append(t)
        return True


class Client:
    _next = 0

    def __init__(self, ws, ip):
        Client._next += 1
        self.id = "c%d" % Client._next
        self.ws = ws
        self.ip = ip
        self.hello = None
        self.name = "Spieler"
        self.room = None
        self.seat = None
        self.rtt = 0
        self.chat_bucket = Bucket(CHAT_BURST, CHAT_WINDOW)
        self.voice_bucket = Bucket(VOICE_BURST, VOICE_WINDOW)
        self.voice_warn = 0.0
        self.voice_last = 0.0
        self.msg_bucket = Bucket(MSG_BURST, MSG_WINDOW)
        self.order_bucket = Bucket(ORDER_BURST, ORDER_WINDOW)
        self.list_bucket = Bucket(LIST_BURST, LIST_WINDOW)
        self.alive = True

        self.left = False

        self.watch_room = None
        self.watch_seat = None

    async def send(self, obj):
        if not self.alive:
            return
        try:
            await self.ws.send(json.dumps(obj, separators=(",", ":")))
        except (ConnectionClosed, OSError, RuntimeError):
            self.alive = False

    async def error(self, code, text, field=None):
        msg = {"t": "error", "code": code, "text": text}
        if field:
            msg["field"] = field
        await self.send(msg)


class Room:
    def __init__(self, code, host, data, hub):
        self.code = code
        self.hub = hub


        self.host = host
        self.map = clean_text(data.get("map"), 64)
        self.map_name = clean_text(data.get("map_name"), 64)
        self.map_sha256 = clean_text(data.get("map_sha256"), 64)


        self.public = bool(data.get("public"))
        self.seats_total = clamp_int(data.get("seats"), 1, MAX_PLAYERS_CAP, 2)
        self.settings = data.get("settings") if isinstance(data.get("settings"), dict) else {}
        self.fingerprint = fingerprint_of(host.hello)
        self.state = "lobby"
        self.seats = {}
        self.created_at = now()
        self.last_traffic = now()

        self.frames = {}
        self.next_frame = None
        self.frame_since = now()
        self.warned_at = 0.0
        self.gone = set()


        self.host_seat_num = 0
        self.watchers = set()


    def free_seat(self):
        for s in range(self.seats_total):
            if s not in self.seats:
                return s
        return None

    def humans(self):
        return [e for e in self.seats.values() if e["kind"] == "human"]

    def clients(self):
        return [e["client"] for e in self.humans()
                if e["client"] is not None and e["client"].alive]

    def live_seats(self):
        return set(s for s, e in self.seats.items()
                   if e["kind"] == "human" and s not in self.gone)

    def spawn_taken(self, spawn, except_seat=None):

        if spawn < 0:
            return False
        for seat, e in self.seats.items():
            if seat != except_seat and e["spawn"] == spawn:
                return True
        return False

    def add_human(self, client):
        seat = self.free_seat()
        if seat is None:
            return None
        self.seats[seat] = {
            "kind": "human", "seat": seat, "client": client, "name": client.name,
            "faction": "soviet" if seat % 2 else "allies", "team": 0,
            "color": seat, "spawn": -1, "ready": False,

            "token": secrets.token_urlsafe(TOKEN_BYTES), "absent_since": None,
        }
        client.room, client.seat = self, seat
        return seat


    def detach(self, seat):

        e = self.seats.get(seat)
        if e is None or e["kind"] != "human":
            return None
        if e["client"] is not None:
            e["client"].room, e["client"].seat = None, None
        e["client"] = None
        e["absent_since"] = now()
        e["ready"] = seat == self.host_seat()
        return e

    def seat_by_token(self, token):
        if not token:
            return None
        for seat, e in self.seats.items():
            if e["kind"] == "human" and e.get("token") == token:
                return seat
        return None

    def watched(self, seat):
        return any(w.alive and w.watch_seat == seat for w in self.watchers)

    def absent_left(self, seat, resume_s, t=None):

        e = self.seats.get(seat)
        if e is None or e["kind"] != "human" or e["client"] is not None:
            return None
        if self.watched(seat):
            return resume_s
        return resume_s - ((now() if t is None else t) - (e["absent_since"] or 0.0))

    def resumable(self, resume_s, t=None):
        for seat, e in self.seats.items():
            if e["kind"] == "human" and e["client"] is None:
                rest = self.absent_left(seat, resume_s, t)
                if rest is not None and rest > 0:
                    return True
        return False

    def occupied(self, resume_s, t=None):

        return bool(self.clients()) or bool(self.watchers) or self.resumable(resume_s, t)

    def is_host(self, client):
        return (client.room is self and client.seat is not None
                and client.seat == self.host_seat())

    def fix_host_seat(self):

        if self.host_seat_num not in self.seats:
            self.host_seat_num = self.host_seat()

    def add_bot(self, data):
        seat = self.free_seat()
        if seat is None:
            return None
        self.seats[seat] = {
            "kind": "bot", "seat": seat,
            "level": clean_text(data.get("level"), 16) or "normal",


            "strategy": clean_text(data.get("strategy"), 16) or "normal",
            "name": "KI %d" % (seat + 1),
            "faction": clean_text(data.get("faction"), FACTION_MAX) or "allies",
            "team": clamp_int(data.get("team"), 0, TEAM_MAX, 0),
            "color": seat, "spawn": -1, "ready": True,
        }
        return seat

    def remove_seat(self, seat):
        e = self.seats.pop(seat, None)
        if e and e["kind"] == "human" and e["client"] is not None:
            e["client"].room, e["client"].seat = None, None
        for w in [w for w in self.watchers if w.watch_seat == seat]:
            self.watchers.discard(w)
            w.watch_room, w.watch_seat = None, None
        return e


    def host_seat(self):
        if self.host_seat_num in self.seats:
            return self.host_seat_num
        humans = sorted(s for s, e in self.seats.items() if e["kind"] == "human")
        return humans[0] if humans else 0

    def lobby_msg(self):
        clients = []
        for seat in sorted(self.seats):
            e = self.seats[seat]
            row = {"client_id": None, "seat": seat, "kind": e["kind"], "name": e["name"],
                   "faction": e["faction"], "team": e["team"], "color": e["color"],
                   "spawn": e["spawn"], "ready": e["ready"], "ping": 0}
            if e["kind"] == "bot":
                row["level"] = e["level"]
                row["strategy"] = e.get("strategy", "normal")
            elif e["client"] is None:

                row["absent"] = True
            else:
                row["client_id"] = e["client"].id
                row["ping"] = e["client"].rtt
            clients.append(row)
        return {"t": "lobby", "code": self.code, "host_seat": self.host_seat(),
                "map": self.map, "map_name": self.map_name, "map_sha256": self.map_sha256,
                "seats_total": self.seats_total, "settings": self.settings,
                "public": self.public, "clients": clients}

    def list_row(self):

        host = self.seats.get(self.host_seat(), {})
        return {"code": self.code, "map": self.map, "map_name": self.map_name,
                "seats_used": len(self.seats), "seats_total": self.seats_total,
                "started": self.state != "lobby",
                "host_name": host.get("name", ""),
                "public": self.public}

    async def broadcast(self, msg, skip=None):
        for c in self.clients():
            if c is not skip:
                await c.send(msg)

    async def to_watchers(self, msg):

        for w in list(self.watchers):
            if w.alive:
                await w.send(msg)
            else:
                self.watchers.discard(w)

    async def push_lobby(self):
        msg = self.lobby_msg()
        await self.broadcast(msg)
        await self.to_watchers(msg)


    async def take_order(self, client, data):
        seat = client.seat
        frame = data.get("frame")
        if not isinstance(frame, int) or isinstance(frame, bool) or frame < 0:
            await client.error("badstate", "Rahmennummer fehlt", "frame")
            return
        cmds = data.get("cmds")
        if not isinstance(cmds, list):
            await client.error("badstate", "cmds muss eine Liste sein", "cmds")
            return
        for c in cmds:
            if not isinstance(c, list) or not all(
                    isinstance(x, int) and not isinstance(x, bool) for x in c):
                await client.error("badstate", "Befehl ist kein Ganzzahlfeld", "cmds")
                return
        if self.next_frame is None:
            self.next_frame = frame
            self.frame_since = now()
        if frame < self.next_frame:
            log("stale_frame", room=self.code, seat=seat, frame=frame, want=self.next_frame)
            return
        if frame > self.next_frame + MAX_LEAD:
            await client.error("badstate", "zu weit voraus (%d Rahmen)" % MAX_LEAD, "frame")
            log("lead_kick", room=self.code, seat=seat, frame=frame, want=self.next_frame)
            self.hub.close_later(client)
            return
        slot = self.frames.setdefault(frame, {})
        if seat in slot:
            log("dup_frame", room=self.code, seat=seat, frame=frame)
            return
        packet = {"seat": seat, "cmds": cmds}
        h = data.get("hash")
        if isinstance(h, str) and h:
            packet["hash"] = h[:32]
        slot[seat] = packet
        await self.try_emit()

    async def try_emit(self):
        while self.state == "play" and self.next_frame is not None:
            f = self.next_frame
            need = self.live_seats()
            have = self.frames.get(f, {})
            if not need or not need.issubset(have.keys()):
                return
            packets = [have[s] for s in sorted(need)]
            self.frames.pop(f, None)
            self.next_frame = f + 1
            self.frame_since = now()
            self.warned_at = 0.0
            await self.broadcast({"t": "frame", "frame": f, "packets": packets})
            hashes = {str(p["seat"]): p["hash"] for p in packets if "hash" in p}
            if len(hashes) > 1 and len(set(hashes.values())) > 1:
                log("desync", room=self.code, frame=f, hashes=json.dumps(hashes))
                await self.broadcast({"t": "desync", "frame": f, "hashes": hashes})
                self.state = "over"
                return

    async def watchdog(self):
        t = now()
        if self.state != "play" or self.next_frame is None:
            return
        f = self.next_frame
        need = self.live_seats()
        missing = sorted(need - set(self.frames.get(f, {}).keys()))
        if not missing:
            return
        waited = t - self.frame_since
        if waited > self.hub.drop_s:
            for seat in missing:
                self.gone.add(seat)
                e = self.seats.get(seat)
                weg = (e is None or e["kind"] != "human" or e["client"] is None
                       or not e["client"].alive)
                reason = "gone" if weg else "timeout"
                log("peer_left", room=self.code, seat=seat, frame=f, reason=reason)
                msg = {"t": "peer_left", "seat": seat, "frame": f, "reason": reason}
                await self.broadcast(msg)
                await self.to_watchers(msg)
                if e and e["kind"] == "human" and e["client"] is not None:
                    self.hub.close_later(e["client"])
            if not self.live_seats():
                self.state = "over"
                log("room_empty_play", room=self.code)
            else:
                await self.try_emit()
            return
        if waited > self.hub.waiting_s and t - self.warned_at > 1.0:
            self.warned_at = t
            await self.broadcast({"t": "waiting", "frame": f, "seats": missing})


def fingerprint_of(hello):
    hello = hello or {}
    return {k: hello.get(k) for k in
            ("app", "pack", "sim", "state_version", "rules_hash", "rules_format")}


class Hub:
    def __init__(self, args):
        self.rooms = {}
        self.max_rooms = args.max_rooms
        self.create_per_min = args.create_per_min
        self.waiting_s = args.waiting_ms / 1000.0
        self.drop_s = args.drop_s
        self.resume_s = args.resume_s
        self.ip = {}
        self.clients = set()


    def ip_state(self, ip):
        st = self.ip.get(ip)
        if st is None:
            st = {"create": Bucket(self.create_per_min, 60.0),
                  "join": Bucket(JOIN_PER_MIN, 60.0),
                  "bad": Bucket(BAD_CODE_LIMIT, BAN_S),
                  "ban_until": 0.0}
            self.ip[ip] = st
        return st

    def banned(self, ip):
        return self.ip_state(ip)["ban_until"] > now()

    def note_bad_code(self, ip):
        st = self.ip_state(ip)
        if not st["bad"].allow():
            st["ban_until"] = now() + BAN_S
            return True
        return False

    def close_later(self, client):
        client.alive = False
        asyncio.get_event_loop().create_task(self._close(client))

    async def _close(self, client):
        try:
            await client.ws.close()
        except Exception:
            pass


    def new_code(self):
        for _ in range(200):
            code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LEN))
            if code not in self.rooms:
                return code
        return None

    def drop_room(self, room, why):
        if self.rooms.pop(room.code, None) is not None:
            log("room_closed", room=room.code, reason=why, state=room.state)

    async def sweep(self):
        while True:
            await asyncio.sleep(WATCHDOG_S)
            t = now()
            for room in list(self.rooms.values()):
                try:
                    await room.watchdog()
                except Exception as exc:
                    log("watchdog_error", room=room.code, err=repr(exc))
                await self.expire_absent(room, t)
                if not room.occupied(self.resume_s, t):
                    self.drop_room(room, "leer")
                elif room.state == "lobby" and t - room.created_at > LOBBY_IDLE_S:
                    await room.broadcast({"t": "error", "code": "badstate",
                                          "text": "Lobby zu lange ohne Start"})
                    self.drop_room(room, "lobby_zeit")
                elif room.state != "lobby" and t - room.last_traffic > GAME_IDLE_S:
                    self.drop_room(room, "partie_still")

    async def expire_absent(self, room, t):

        weg = [seat for seat, e in room.seats.items()
               if e["kind"] == "human" and e["client"] is None
               and not room.watched(seat)
               and t - (e["absent_since"] or 0.0) > self.resume_s]
        if not weg:
            return
        for seat in weg:
            room.remove_seat(seat)
            log("resume_expired", room=room.code, seat=seat)
        room.fix_host_seat()
        if room.seats and room.clients():
            await room.push_lobby()


    async def handle(self, ws, path=None):
        ip = "?"
        try:
            addr = getattr(ws, "remote_address", None)
            if addr:
                ip = addr[0]
        except Exception:
            pass
        client = Client(ws, ip)
        self.clients.add(client)
        log("connect", client=client.id, ip=ip)
        if self.banned(ip):
            await client.error("ratelimit", "vorübergehend gesperrt")
            self.clients.discard(client)
            log("banned", client=client.id, ip=ip)
            return
        await client.send({"t": "welcome", "client_id": client.id,
                           "server": SERVER_NAME, "proto": PROTO})
        try:
            async for raw in ws:
                if isinstance(raw, bytes):
                    await client.error("badstate", "nur Text-Rahmen")
                    continue
                if len(raw.encode("utf-8", "ignore")) > MAX_MSG_BYTES:
                    await client.error("badstate", "Nachricht größer als 16 KB")
                    log("oversize", client=client.id, bytes=len(raw))
                    continue
                try:
                    data = json.loads(raw)
                except ValueError:
                    await client.error("badstate", "kein gültiges JSON")
                    continue
                if not isinstance(data, dict):
                    await client.error("badstate", "Nachricht ist kein Objekt")
                    continue


                typ = data.get("t")
                if typ == "order":
                    bucket = client.order_bucket
                elif typ == "voice":
                    bucket = client.voice_bucket
                else:
                    bucket = client.msg_bucket
                if not bucket.allow():
                    if typ == "voice":


                        t_now = now()
                        if t_now - client.voice_warn > VOICE_WARN_EVERY:
                            client.voice_warn = t_now
                            await client.error("ratelimit", "zu viele Sprachpakete")
                            log("ratelimit_voice", client=client.id, ip=ip)
                        continue
                    await client.error("ratelimit", "zu viele Nachrichten")
                    log("ratelimit_msg", client=client.id, ip=ip, typ=typ)
                    break
                if not await self.dispatch(client, data):
                    break
                if not client.alive:
                    break
        except (ConnectionClosed, OSError):
            pass
        except Exception as exc:
            log("handler_error", client=client.id, err=repr(exc))
        finally:
            await self.gone(client)

    async def gone(self, client):
        client.alive = False
        self.clients.discard(client)
        if client.watch_room is not None:
            watched = client.watch_room
            watched.watchers.discard(client)
            client.watch_room, client.watch_seat = None, None
            log("unwatch", client=client.id, room=watched.code)
        room = client.room
        log("disconnect", client=client.id, room=room.code if room else None,
            seat=client.seat, left=client.left or None)
        if room is None:
            return
        seat = client.seat
        if room.state == "lobby":
            if client.left:

                room.remove_seat(seat)
                room.fix_host_seat()
            else:


                room.detach(seat)
                log("seat_absent", room=room.code, seat=seat, resume_s=self.resume_s)
            if not room.occupied(self.resume_s):
                self.drop_room(room, "leer")
            else:
                await room.push_lobby()
        else:
            client.room, client.seat = None, None

            if not room.clients() and not room.watchers:
                self.drop_room(room, "leer")


    async def dispatch(self, client, data):
        t = data.get("t")
        if t not in CLIENT_TYPES:
            await client.error("badstate", "unbekannter Typ", "t")
            return True
        if client.room:
            client.room.last_traffic = now()
        if t == "hello":
            return await self.on_hello(client, data)
        if client.hello is None:
            await client.error("badstate", "hello fehlt")
            return True
        fn = getattr(self, "on_" + t)
        return await fn(client, data)

    async def on_hello(self, client, data):
        if client.hello is not None:
            await client.error("badstate", "hello nur einmal")
            return True
        if data.get("proto") != PROTO:
            await client.error("mismatch", "Protokollfassung %s statt %d"
                               % (data.get("proto"), PROTO), "proto")
            return False
        client.hello = {k: data.get(k) for k in
                        ("app", "pack", "sim", "state_version", "rules_hash",
                         "rules_format", "name")}
        client.name = clean_text(data.get("name"), NAME_MAX) or "Spieler"
        log("hello", client=client.id, name=client.name, app=data.get("app"),
            pack=data.get("pack"), rules=data.get("rules_hash"))
        return True

    async def on_create(self, client, data):
        if client.room:
            await client.error("badstate", "schon in einem Raum")
            return True
        if not self.ip_state(client.ip)["create"].allow():
            await client.error("ratelimit", "zu viele Räume in kurzer Zeit")
            log("ratelimit_create", client=client.id, ip=client.ip)
            return True
        if len(self.rooms) >= self.max_rooms:
            await client.error("full", "der Vermittler ist voll")
            return True
        code = self.new_code()
        if code is None:
            await client.error("full", "kein freier Spielcode")
            return True
        room = Room(code, client, data, self)
        self.rooms[code] = room
        seat = room.add_human(client)
        room.host_seat_num = seat
        room.seats[seat]["ready"] = True
        log("create", room=code, client=client.id, map=room.map,
            seats=room.seats_total, public=room.public)
        await client.send({"t": "created", "code": code, "host": True,
                           "seats": room.seats_total})
        await self.send_session(client, room, seat)
        await room.push_lobby()
        return True

    async def send_session(self, client, room, seat):

        await client.send({"t": "session", "code": room.code, "seat": seat,
                           "token": room.seats[seat]["token"],
                           "resume_s": int(self.resume_s),
                           "host": seat == room.host_seat()})

    async def on_join(self, client, data):
        if client.room:
            await client.error("badstate", "schon in einem Raum")
            return True
        if not self.ip_state(client.ip)["join"].allow():
            await client.error("ratelimit", "zu viele Beitritte in kurzer Zeit")
            return True
        code = clean_text(data.get("code"), 8).upper()
        room = self.rooms.get(code)
        if room is None:
            if self.note_bad_code(client.ip):
                await client.error("ratelimit", "zu viele falsche Codes — 60 s Pause")
                log("ban", ip=client.ip, client=client.id)
                return False
            await client.error("nocode", "Spielcode unbekannt", "code")
            log("join_nocode", client=client.id, code=code)
            return True
        if room.state != "lobby":
            await client.error("badstate", "die Partie läuft bereits")
            return True
        want = fingerprint_of(client.hello)
        if want != room.fingerprint:
            bad = [k for k in want if want[k] != room.fingerprint[k]]
            await client.error("mismatch", "Stand weicht ab: " + ", ".join(bad),
                               bad[0] if bad else None)
            log("join_mismatch", client=client.id, room=code, fields=",".join(bad))
            return True
        want_map = clean_text(data.get("map_sha256"), 64)
        if room.map_sha256 and want_map and want_map != room.map_sha256:
            await client.error("mismatch", "andere Karte", "map_sha256")
            return True
        seat = room.add_human(client)
        if seat is None:
            await client.error("full", "der Raum ist voll")
            log("join_full", client=client.id, room=code)
            return True
        log("join", room=code, client=client.id, seat=seat, name=client.name)
        await self.send_session(client, room, seat)
        await room.push_lobby()
        return True

    async def on_resume(self, client, data):

        if client.room is not None or client.watch_room is not None:
            await client.error("badstate", "schon in einem Raum")
            return True
        room, seat = self._find_seat(client, data)
        if room is None:
            await client.error(seat, "Platz nicht mehr reserviert", "token")
            return True
        if room.state != "lobby":

            await client.error("badstate", "die Partie läuft bereits")
            return True
        e = room.seats[seat]
        if e["client"] is not None and e["client"] is not client:
            self.close_later(e["client"])
        e["client"] = client
        e["absent_since"] = None
        e["name"] = client.name or e["name"]
        e["ready"] = seat == room.host_seat()
        client.room, client.seat = room, seat
        log("resume", room=room.code, client=client.id, seat=seat, name=client.name)
        await self.send_session(client, room, seat)
        await room.push_lobby()
        return True

    async def on_watch(self, client, data):

        if client.room is not None:
            await client.error("badstate", "diese Verbindung sitzt auf einem Platz")
            return True
        if client.watch_room is not None:
            await client.error("badstate", "beobachtet schon einen Raum")
            return True
        room, seat = self._find_seat(client, data)
        if room is None:
            await client.error(seat, "Platz nicht mehr reserviert", "token")
            return True
        client.watch_room, client.watch_seat = room, seat
        room.watchers.add(client)
        log("watch", room=room.code, client=client.id, seat=seat)
        await client.send({"t": "watching", "code": room.code, "seat": seat})
        await client.send(room.lobby_msg())
        return True

    def _find_seat(self, client, data):

        code = clean_text(data.get("code"), 8).upper()
        room = self.rooms.get(code)
        if room is None:
            return None, "nocode"
        seat = room.seat_by_token(data.get("token") if isinstance(data.get("token"), str) else "")
        if seat is None:
            if self.note_bad_code(client.ip):
                log("ban", ip=client.ip, client=client.id)
            log("resume_notoken", client=client.id, room=code)
            return None, "notallowed"
        return room, seat

    async def on_list(self, client, data):

        if not client.list_bucket.allow():
            await client.error("ratelimit", "Raumliste hoechstens alle zwei Sekunden")
            return True
        rooms = [r for r in self.rooms.values()
                 if r.public and r.state != "over" and r.occupied(self.resume_s)]

        rooms.sort(key=lambda r: (r.state != "lobby", -r.created_at))
        await client.send({"t": "rooms", "rooms": [r.list_row() for r in rooms[:LIST_MAX]]})
        return True

    async def on_visibility(self, client, data):

        room = self._need_room(client)
        if room is None:
            await client.error("badstate", "nicht in einer Lobby")
            return True
        if not room.is_host(client):
            await client.error("nothost", "nur der Gastgeber schaltet die Sichtbarkeit um")
            return True
        room.public = bool(data.get("public"))
        log("visibility", room=room.code, public=room.public)
        await room.push_lobby()
        return True

    def _need_room(self, client, lobby_only=True):
        room = client.room
        if room is None:
            return None
        if lobby_only and room.state != "lobby":
            return None
        return room

    async def on_map(self, client, data):

        room = self._need_room(client)
        if room is None:
            await client.error("badstate", "nicht in einer Lobby")
            return True
        if not room.is_host(client):
            await client.error("nothost", "nur der Gastgeber wechselt die Karte")
            return True
        new_map = clean_text(data.get("map"), 64)
        if not new_map:
            await client.error("badstate", "Karte fehlt", "map")
            return True
        room.map = new_map
        room.map_name = clean_text(data.get("map_name"), 64)
        room.map_sha256 = clean_text(data.get("map_sha256"), 64)
        room.seats_total = clamp_int(data.get("seats"), 1, MAX_PLAYERS_CAP, room.seats_total)
        if isinstance(data.get("settings"), dict):
            room.settings = data["settings"]

        for seat in sorted(room.seats):
            if seat < room.seats_total:
                continue
            e = room.remove_seat(seat)
            if e and e["kind"] == "human" and e["client"] is not None:
                await e["client"].error("full", "die neue Karte hat weniger Plätze")
                self.close_later(e["client"])
        room.fix_host_seat()

        host_seat = room.host_seat()
        for seat, e in room.seats.items():
            e["spawn"] = -1
            if e["kind"] == "human":
                e["ready"] = seat == host_seat
        log("map", room=room.code, map=room.map, seats=room.seats_total)
        await room.push_lobby()
        return True

    async def on_slot(self, client, data):

        room = self._need_room(client)
        if room is None:
            await client.error("badstate", "nicht in einer Lobby")
            return True
        seat = data.get("seat")
        if isinstance(seat, int) and not isinstance(seat, bool) and seat != client.seat:
            if client is not room.host:
                await client.error("nothost", "nur der Gastgeber ändert fremde Plätze", "seat")
                return True
            e = room.seats.get(seat)
            if e is None:
                await client.error("badstate", "Platz gibt es nicht", "seat")
                return True
        else:
            seat = client.seat
            e = room.seats.get(seat)
        if e is None:
            await client.error("badstate", "kein Platz", "seat")
            return True
        if "faction" in data:
            e["faction"] = clean_text(data.get("faction"), FACTION_MAX) or e["faction"]
        if "team" in data:
            e["team"] = clamp_int(data.get("team"), 0, TEAM_MAX, e["team"])
        if "color" in data:
            e["color"] = clamp_int(data.get("color"), 0, COLOR_MAX, e["color"])
        if "strategy" in data and e["kind"] == "bot":
            e["strategy"] = clean_text(data.get("strategy"), 16) or e.get("strategy", "normal")
        if "spawn" in data:
            want = clamp_int(data.get("spawn"), -1, SPAWN_MAX, e["spawn"])
            if want != e["spawn"] and room.spawn_taken(want, seat):
                await client.error("spawnoccupied", "Startpunkt ist belegt", "spawn")
                await room.push_lobby()
                return True
            e["spawn"] = want
        log("slot", room=room.code, seat=seat, team=e["team"], spawn=e["spawn"],
            faction=e["faction"])
        await room.push_lobby()
        return True

    async def on_bot(self, client, data):
        room = self._need_room(client)
        if room is None:
            await client.error("badstate", "nicht in einer Lobby")
            return True
        if not room.is_host(client):
            await client.error("nothost", "nur der Gastgeber")
            return True
        act = clean_text(data.get("op"), 8)
        if act == "add":
            seat = room.add_bot(data)
            if seat is None:
                await client.error("full", "kein freier Platz")
                return True
            log("bot_add", room=room.code, seat=seat, level=room.seats[seat]["level"])
        elif act == "remove":
            seat = data.get("seat")
            e = room.seats.get(seat) if isinstance(seat, int) else None
            if e is None or e["kind"] != "bot":
                await client.error("badstate", "kein KI-Platz", "seat")
                return True
            room.remove_seat(seat)
            log("bot_remove", room=room.code, seat=seat)
        else:
            await client.error("badstate", "op muss add oder remove sein", "op")
            return True
        await room.push_lobby()
        return True

    async def on_kick(self, client, data):
        room = self._need_room(client)
        if room is None:
            await client.error("badstate", "nicht in einer Lobby")
            return True
        if not room.is_host(client):
            await client.error("nothost", "nur der Gastgeber")
            return True
        seat = data.get("seat")
        e = room.seats.get(seat) if isinstance(seat, int) else None
        if e is None or seat == client.seat:
            await client.error("badstate", "Platz nicht wegwerfbar", "seat")
            return True
        room.remove_seat(seat)
        if e["kind"] == "human":
            await e["client"].error("notallowed", "vom Gastgeber entfernt")
            self.close_later(e["client"])
        log("kick", room=room.code, seat=seat)
        await room.push_lobby()
        return True

    async def on_ready(self, client, data):
        room = self._need_room(client)
        if room is None:
            await client.error("badstate", "nicht in einer Lobby")
            return True
        room.seats[client.seat]["ready"] = bool(data.get("on"))
        await room.push_lobby()
        return True

    async def on_start(self, client, data):
        room = self._need_room(client)
        if room is None:
            await client.error("badstate", "nicht in einer Lobby")
            return True
        if not room.is_host(client):
            await client.error("nothost", "nur der Gastgeber startet")
            return True
        setup = data.get("setup")
        if not isinstance(setup, dict) or not isinstance(setup.get("seats"), list):
            await client.error("badstate", "Aufstellung fehlt", "setup")
            return True
        if len(room.humans()) < 1:
            await client.error("badstate", "kein Spieler")
            return True
        for e in room.humans():
            if e["client"] is None:
                await client.error("badstate", "ein Platz verbindet gerade neu")
                return True
            if not e["ready"]:
                await client.error("badstate", "nicht alle sind bereit")
                return True
        by_seat = {}
        for entry in setup["seats"]:
            if not isinstance(entry, dict) or not isinstance(entry.get("seat"), int):
                await client.error("badstate", "Platz ohne Nummer", "setup")
                return True
            by_seat[entry["seat"]] = entry
        for seat, e in room.seats.items():
            if seat not in by_seat:
                await client.error("badstate", "Platz %d fehlt in der Aufstellung" % seat,
                                   "setup")
                return True
            if e["kind"] == "human":
                by_seat[seat]["client_id"] = e["client"].id
                by_seat[seat]["kind"] = "human"
                by_seat[seat].setdefault("name", e["name"])


            if by_seat[seat].get("team") != e["team"]:
                log("start_team_fix", room=room.code, seat=seat,
                    was=by_seat[seat].get("team"), now=e["team"])
            by_seat[seat]["team"] = e["team"]
            by_seat[seat]["color"] = e["color"]
            if e["spawn"] >= 0 and by_seat[seat].get("spawn") != e["spawn"]:
                log("start_spawn_diff", room=room.code, seat=seat,
                    want=e["spawn"], got=by_seat[seat].get("spawn"))
        setup["code"] = room.code
        room.state = "play"
        room.frames.clear()
        room.next_frame = None
        room.frame_since = now()
        room.gone.clear()
        log("start", room=room.code, seats=len(room.seats),
            humans=len(room.humans()), map=room.map)
        await room.broadcast({"t": "start", "setup": setup})
        await room.to_watchers({"t": "start", "setup": {"code": room.code,
                                                        "map": room.map,
                                                        "map_name": room.map_name}})
        return True

    async def on_order(self, client, data):
        room = client.room
        if room is None or room.state != "play":
            await client.error("badstate", "keine laufende Partie")
            return True
        await room.take_order(client, data)
        return True

    async def on_chat(self, client, data):
        room = client.room
        if room is None:
            await client.error("badstate", "nicht in einem Raum")
            return True
        if not client.chat_bucket.allow():
            await client.error("ratelimit", "zu viele Nachrichten")
            log("ratelimit_chat", client=client.id, room=room.code)
            return True
        text = clean_text(data.get("text"), CHAT_MAX)
        if not text:
            return True
        scope = "team" if data.get("scope") == "team" else "all"
        e = room.seats.get(client.seat)
        msg = {"t": "chat", "seat": client.seat, "name": client.name,
               "color": e["color"] if e else 0, "scope": scope, "text": text,
               "t_server": ts_ms()}
        team = e["team"] if e else 0
        for other in room.clients():
            if scope == "team":
                oe = room.seats.get(other.seat)
                if oe is None or oe["team"] != team:
                    continue
            await other.send(msg)
        for w in list(room.watchers):
            we = room.seats.get(w.watch_seat)
            if scope == "team" and (we is None or we["team"] != team):
                continue
            if w.watch_seat != client.seat:
                await w.send(msg)

        log("chat", room=room.code, seat=client.seat, scope=scope, len=len(text))
        return True

    async def on_voice(self, client, data):

        room = client.room
        if room is None:
            await client.error("badstate", "nicht in einem Raum")
            return True
        payload = data.get("data")
        if not isinstance(payload, str) or not payload:
            return True
        if len(payload) > VOICE_MAX:
            await client.error("badstate",
                               "Sprachpaket größer als %d Zeichen" % VOICE_MAX, "data")
            log("voice_oversize", client=client.id, room=room.code, chars=len(payload))
            return True
        if VOICE_B64.match(payload) is None:
            await client.error("badstate", "Sprachpaket ist kein Base64", "data")
            return True
        scope = "team" if data.get("scope") == "team" else "all"
        e = room.seats.get(client.seat)
        msg = {"t": "voice", "seat": client.seat, "name": client.name,
               "color": e["color"] if e else 0, "scope": scope,
               "codec": clean_text(data.get("codec"), 16) or VOICE_CODEC,
               "seq": clamp_int(data.get("seq"), 0, 1 << 30, 0), "data": payload}
        if data.get("end"):
            msg["end"] = True
        team = e["team"] if e else 0
        empfaenger = 0
        for other in room.clients():
            if other is client:
                continue
            if scope == "team":
                oe = room.seats.get(other.seat)
                if oe is None or oe["team"] != team:
                    continue
            await other.send(msg)
            empfaenger += 1


        t_now = now()
        if t_now - client.voice_last > VOICE_SPURT_GAP:
            log("voice", room=room.code, seat=client.seat, scope=scope, to=empfaenger)
        client.voice_last = t_now
        return True

    async def on_ping(self, client, data):
        rtt = data.get("rtt")
        if isinstance(rtt, int) and not isinstance(rtt, bool):
            client.rtt = clamp_int(rtt, 0, 60000, 0)
        await client.send({"t": "pong", "id": data.get("id"), "t_server": ts_ms()})
        return True

    async def on_leave(self, client, data):

        client.left = True
        log("leave", client=client.id, room=client.room.code if client.room else None)
        return False


async def main_async(args):
    hub = Hub(args)
    sweeper = asyncio.ensure_future(hub.sweep())

    async def handler(ws, path=None):
        await hub.handle(ws, path)

    log("listen", host=args.host, port=args.port, max_rooms=args.max_rooms,
        waiting_ms=args.waiting_ms, drop_s=args.drop_s, resume_s=args.resume_s,
        create_per_min=args.create_per_min)
    async with ws_serve(handler, args.host, args.port,
                        max_size=MAX_MSG_BYTES * 4, ping_interval=20,
                        ping_timeout=20, compression=None):
        try:
            await asyncio.Future()
        finally:
            sweeper.cancel()


def main(argv=None):
    p = argparse.ArgumentParser(description="Mehrspieler-Vermittler für PocketRA")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=8787)
    p.add_argument("--max-rooms", type=int, default=MAX_ROOMS_DEFAULT)
    p.add_argument("--waiting-ms", type=int, default=500,
                   help="ohne Paket: nach so vielen ms `waiting` melden")
    p.add_argument("--drop-s", type=float, default=20.0,
                   help="ohne Paket: nach so vielen Sekunden `peer_left`")
    p.add_argument("--resume-s", type=float, default=RESUME_S_DEFAULT,
                   help="Lobby: so lange bleibt ein Platz nach einem Abbruch reserviert")
    p.add_argument("--create-per-min", type=int, default=CREATE_PER_MIN,
                   help="Raeume je Minute und IP (Pruefschalter fuer mp_smoke.py)")
    args = p.parse_args(argv)
    try:
        asyncio.run(main_async(args))
    except KeyboardInterrupt:
        log("stop")
    return 0


if __name__ == "__main__":
    sys.exit(main())
