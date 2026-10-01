#!/usr/bin/env python3


import argparse
import asyncio
import base64
import json
import os
import subprocess
import sys
import time

try:
    from websockets.asyncio.client import connect as ws_connect
except ImportError:
    from websockets.legacy.client import connect as ws_connect

HERE = os.path.dirname(os.path.abspath(__file__))
FINGERPRINT = {"app": "0.9", "pack": 6, "sim": "1", "state_version": 12,
               "rules_hash": "abc123", "rules_format": 4}

OK, FAIL = [], []


def hinweis_ratelimit(msg):

    if isinstance(msg, dict) and msg.get("code") == "ratelimit":
        print("  HINWEIS: der Vermittler begrenzt `create` auf 5 je Minute und IP.")
        print("           Eine Minute warten oder mit --schnell einen Raum weniger anlegen.")


def letzte_lobby(msgs):

    out = None
    for m in msgs:
        if isinstance(m, dict) and m.get("t") == "lobby":
            out = m
    return out


def pruefe(bedingung, text, detail=""):
    if bedingung:
        OK.append(text)
        print("  ok   %s" % text)
    else:
        FAIL.append("%s%s" % (text, (" — " + str(detail)) if detail else ""))
        print("  FEHL %s%s" % (text, (" — " + str(detail)) if detail else ""))
    return bool(bedingung)


class Peer:


    def __init__(self, name):
        self.name = name
        self.ws = None
        self.queue = asyncio.Queue()
        self.task = None
        self.closed = False
        self.seat = None
        self.client_id = None
        self.session = None
        self._letztes_create = None
        self._create_gewartet = False

    async def open(self, url):
        self.ws = await ws_connect(url, max_size=2 ** 20)
        self.task = asyncio.ensure_future(self._pump())
        wel = await self.expect("welcome")
        self.client_id = wel.get("client_id")
        return wel

    async def _pump(self):
        try:
            async for raw in self.ws:
                msg = json.loads(raw)
                if isinstance(msg, dict) and msg.get("t") == "session":


                    self.session = msg
                    self.seat = msg.get("seat")
                    continue
                await self.queue.put(msg)
        except Exception:
            pass
        finally:
            self.closed = True
            await self.queue.put(None)

    async def send(self, **msg):
        if msg.get("t") == "create":
            self._letztes_create = msg
        await self.ws.send(json.dumps(msg))

    async def next(self, timeout=5.0):
        try:
            msg = await asyncio.wait_for(self.queue.get(), timeout)
        except asyncio.TimeoutError:
            return None
        return msg

    async def expect(self, t, timeout=5.0, skip=("lobby",)):

        ende = time.monotonic() + timeout
        while True:
            rest = ende - time.monotonic()
            if rest <= 0:
                return None
            msg = await self.next(rest)
            if msg is None:
                return None
            if msg.get("t") == t:
                return msg
            if msg.get("t") in skip:
                continue
            if (t == "created" and msg.get("t") == "error" and msg.get("code") == "ratelimit"
                    and getattr(self, "_letztes_create", None) and not self._create_gewartet):


                self._create_gewartet = True
                print("  HINWEIS: create-Rate-Limit des Vermittlers, warte 61 s und wiederhole …")
                await asyncio.sleep(61)
                await self.send(**self._letztes_create)
                ende = time.monotonic() + timeout
                continue
            return msg

    async def drain(self, dauer=0.35):

        out, ende = [], time.monotonic() + dauer
        while True:
            rest = ende - time.monotonic()
            if rest <= 0:
                break
            msg = await self.next(rest)
            if msg is None:
                break
            out.append(msg)
        return out

    async def hello(self, url, name):
        await self.open(url)
        await self.send(t="hello", proto=1, name=name, **FINGERPRINT)

    async def close(self):
        try:
            await self.ws.close()
        except Exception:
            pass
        if self.task:
            self.task.cancel()

    async def kill(self):

        try:
            tr = getattr(self.ws, "transport", None)
            if tr is not None:
                tr.abort()
            else:
                await self.ws.close()
        except Exception:
            pass
        if self.task:
            self.task.cancel()


def aufstellung(code, seats):
    return {
        "map": "keep-off-the-grass-2", "map_sha256": "f" * 8, "seed": 1234567,
        "tick_ms": 40, "net_frame_ticks": 2, "order_latency": 3, "sync_every": 10,
        "credits": 5000, "starting_units": "none", "crates": True,
        "explored_map": False, "fog": True, "conquest_victory": True,
        "seats": [{"seat": s, "sim": s, "kind": "human", "faction": "soviet",
                   "team": s % 2, "color": s, "spawn": s, "spawn_cell": [10 + s, 20],
                   "start_units": [{"type": "mcv", "cell": [10 + s, 20], "facing": -1}]}
                  for s in seats],
        "alliances": [], "visibility_players": list(seats),
    }


async def teil_lobby(url):
    print("\n[1] Lobby, Beitritt, full, Chat, Start")
    a, b, c = Peer("A"), Peer("B"), Peer("C")
    await a.hello(url, "Tom")
    await a.send(t="create", map="keep-off-the-grass-2", map_sha256="f" * 8,
                 seats=2, settings={"credits": 5000, "fog": True})
    created = await a.expect("created")
    hinweis_ratelimit(created)
    pruefe(created and created.get("t") == "created", "created kommt", created)
    code = (created or {}).get("code", "")
    pruefe(len(code) == 6 and all(ch in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" for ch in code),
           "Spielcode: 6 Zeichen ohne Verwechsler", code)
    pruefe((created or {}).get("seats") == 2, "created nennt die Platzzahl", created)
    lob = await a.expect("lobby", skip=())
    pruefe(lob and lob.get("host_seat") == 0 and lob.get("seats_total") == 2,
           "lobby: host_seat und seats_total", lob)
    pruefe(lob and lob["clients"][0].get("kind") == "human"
           and "client_id" in lob["clients"][0] and "ping" in lob["clients"][0],
           "lobby-Zeile hat kind/client_id/ping", lob)

    await b.hello(url, "Jan")
    await b.send(t="join", code=code, map_sha256="f" * 8)
    lb = await b.expect("lobby", skip=())
    pruefe(lb and len(lb.get("clients", [])) == 2, "zweiter Client sitzt in der Lobby", lb)
    b.seat = 1
    la = await a.expect("lobby", skip=())
    pruefe(la and len(la.get("clients", [])) == 2, "Host bekommt die neue Lobby", la)

    await c.hello(url, "Zaungast")
    await c.send(t="join", code=code, map_sha256="f" * 8)
    err = await c.expect("error", skip=())
    pruefe(err and err.get("code") == "full", "dritter Client wird mit `full` abgewiesen", err)
    await c.close()


    d = Peer("D")
    await d.hello(url, "Irrgast")
    await d.send(t="join", code="ZZZZZZ", map_sha256="f" * 8)
    err = await d.expect("error", skip=())
    pruefe(err and err.get("code") == "nocode", "unbekannter Code → nocode", err)
    await d.close()


    await b.send(t="map", map="pool-party", map_sha256="e" * 8, seats=4)
    err = await b.expect("error", skip=())
    pruefe(err and err.get("code") == "nothost", "map vom Nicht-Host → nothost", err)
    await a.drain(0.2)
    await b.drain(0.2)
    await a.send(t="map", map="pool-party", map_sha256="e" * 8, seats=4)
    lm = letzte_lobby(await a.drain(0.4))
    pruefe(lm and lm.get("map") == "pool-party" and lm.get("map_sha256") == "e" * 8
           and lm.get("seats_total") == 4, "map: neue Karte und Platzzahl in der lobby", lm)
    pruefe(lm and all(k.get("spawn") == -1 for k in lm.get("clients", [])),
           "map: Startpunkte zurückgesetzt", lm)
    pruefe(lm and [k.get("ready") for k in lm.get("clients", [])] == [True, False],
           "map: Bereitschaft zurückgesetzt (nur der Gastgeber bleibt bereit)", lm)
    lmb = letzte_lobby(await b.drain(0.3))
    pruefe(lmb and lmb.get("map") == "pool-party", "map: der Gast bekommt die neue Lobby", lmb)


    e = Peer("Ada")
    await e.hello(url, "Ada")
    await e.send(t="join", code=code, map_sha256="e" * 8)
    le = letzte_lobby(await e.drain(0.4))
    pruefe(le and len(le.get("clients", [])) == 3, "auf der größeren Karte passt ein dritter", le)
    await a.send(t="bot", op="add", level="hard", faction="soviet", team=2)
    lb2 = letzte_lobby(await a.drain(0.4))
    pruefe(lb2 and len(lb2.get("clients", [])) == 4, "vierter Platz mit KI belegt", lb2)
    await b.drain(0.2)
    await e.drain(0.2)


    await a.send(t="map", map="keep-off-the-grass-2", map_sha256="f" * 8, seats=2)
    errE = await e.expect("error", skip=())
    pruefe(errE and errE.get("code") == "full",
           "map: der Platz jenseits der neuen Platzzahl bekommt `full`", errE)
    ls = letzte_lobby(await a.drain(0.5))
    pruefe(ls and ls.get("seats_total") == 2 and len(ls.get("clients", [])) == 2
           and ls.get("map") == "keep-off-the-grass-2",
           "map: Plätze neu gedeckelt, KI-Platz weg", ls)
    await e.close()
    await a.drain(0.2)
    await b.drain(0.2)


    await a.send(t="chat", text="Hallo zusammen", scope="all")
    ca = await a.expect("chat")
    cb = await b.expect("chat")
    pruefe(ca and cb and ca.get("text") == "Hallo zusammen"
           and ca.get("seat") == 0 and ca.get("scope") == "all"
           and "t_server" in ca and ca.get("name") == "Tom",
           "Chat `all` erreicht beide, Stempel vom Vermittler", ca)
    pruefe(cb and cb.get("text") == "Hallo zusammen", "Chat kommt beim zweiten an", cb)
    await b.send(t="chat", text="#attack", scope="all")
    ka = await a.expect("chat")
    pruefe(ka and ka.get("text") == "#attack" and ka.get("seat") == 1,
           "Kurzruf #attack läuft als normaler Text durch", ka)


    await a.send(t="ready", on=True)
    await b.send(t="ready", on=True)
    await asyncio.sleep(0.2)
    await a.drain(0.2)
    await b.drain(0.2)
    await b.send(t="start", setup=aufstellung(code, [0, 1]))
    err = await b.expect("error", skip=())
    pruefe(err and err.get("code") == "nothost", "start vom Nicht-Host → nothost", err)
    await a.send(t="start", setup=aufstellung(code, [0, 1]))
    sa = await a.expect("start")
    sb = await b.expect("start")
    pruefe(sa and sb and sa.get("setup", {}).get("code") == code,
           "start erreicht beide mit der Aufstellung", sa)
    seats = (sa or {}).get("setup", {}).get("seats", [])
    pruefe(len(seats) == 2 and all(s.get("client_id") for s in seats),
           "Vermittler stempelt client_id in die Aufstellung", seats)
    return a, b, code


async def teil_rahmen(a, b, rahmen=200):
    print("\n[2] %d Netzrahmen mit leeren und gefüllten Paketen" % rahmen)
    erwartet_a, erwartet_b = [], []
    fehler = []
    for f in range(rahmen):
        for peer, seat in ((a, 0), (b, 1)):
            cmds = []
            if f % 3 == 0:
                cmds = [[0, 20 + f % 7, 30, 0, 0, 1, 100 + seat]]
            if f % 7 == 0:
                cmds.append([30, 5, 0, 0, 0, 0])
            msg = {"t": "order", "frame": f, "cmds": cmds}
            if f % 10 == 0:
                msg["hash"] = "%016x" % (0x5EED + f)
            await peer.send(**msg)


        await asyncio.sleep(0.002)

    async def sammeln(peer):
        got = []
        while len(got) < rahmen:
            msg = await peer.next(6.0)
            if msg is None:
                break
            if msg.get("t") == "frame":
                got.append(msg)
            elif msg.get("t") in ("waiting",):
                continue
            else:
                fehler.append((peer.name, msg))
        return got

    ga, gb = await asyncio.gather(sammeln(a), sammeln(b))
    pruefe(len(ga) == rahmen and len(gb) == rahmen,
           "beide bekommen %d gebündelte `frame`-Nachrichten" % rahmen,
           "A=%d B=%d" % (len(ga), len(gb)))
    pruefe([m["frame"] for m in ga] == list(range(rahmen)),
           "Rahmen kommen lückenlos in Reihenfolge",
           [m["frame"] for m in ga][:5])
    pruefe(all(len(m["packets"]) == 2 for m in ga),
           "jeder Rahmen bündelt beide Plätze")
    pruefe(all([p["seat"] for p in m["packets"]] == [0, 1] for m in ga),
           "Pakete nach Sitznummer sortiert")
    m0 = next((m for m in ga if m["frame"] == 0), None)
    pruefe(m0 and all("hash" in p for p in m0["packets"]),
           "Sync-Hashes werden mitgereicht", m0)
    m1 = next((m for m in ga if m["frame"] == 1), None)
    pruefe(m1 and all("hash" not in p for p in m1["packets"]),
           "Rahmen ohne Hash bleibt ohne", m1)
    m3 = next((m for m in ga if m["frame"] == 3), None)
    pruefe(m3 and m3["packets"][0]["cmds"] and m3["packets"][0]["cmds"][0][0] == 0,
           "gefüllte Befehlsfelder kommen unverändert an", m3)
    m2 = next((m for m in ga if m["frame"] == 2), None)
    pruefe(m2 and m2["packets"][0]["cmds"] == [], "leere Pakete bleiben leer", m2)
    pruefe(not fehler, "keine unerwarteten Nachrichten während der Rahmen", fehler[:2])
    pruefe(all(a_["packets"] == b_["packets"] for a_, b_ in zip(ga, gb)),
           "beide Clients sehen dieselben Bündel")


async def raum_starten(url, namen, seats_total, teams=None):

    peers = []
    for i, n in enumerate(namen):
        p = Peer(n)
        await p.hello(url, n)
        peers.append(p)
    await peers[0].send(t="create", map="keep-off-the-grass-2", map_sha256="f" * 8,
                        seats=seats_total, settings={})
    created = await peers[0].expect("created")
    if created is None or created.get("t") != "created":
        hinweis_ratelimit(created)
        raise RuntimeError("kein created: %r" % (created,))
    code = created["code"]
    for i, p in enumerate(peers[1:], start=1):
        await p.send(t="join", code=code, map_sha256="f" * 8)
        await p.expect("lobby", skip=())
        p.seat = i
    peers[0].seat = 0
    if teams:
        for p, team in zip(peers, teams):
            await p.send(t="slot", team=team)
    for p in peers:
        await p.send(t="ready", on=True)
    await asyncio.sleep(0.3)
    for p in peers:
        await p.drain(0.25)
    await peers[0].send(t="start", setup=aufstellung(code, list(range(len(peers)))))
    for p in peers:
        st = await p.expect("start")
        if not st or st.get("t") != "start":
            raise RuntimeError("%s bekam kein start: %r" % (p.name, st))
    return peers, code


async def teil_desync(url):
    print("\n[3] Desync: abweichender Sync-Hash")
    (a, b), code = await raum_starten(url, ["Tom", "Jan"], 2)
    for f in range(3):
        ha = "%016x" % (0xABC + f)
        hb = ha if f < 2 else "%016x" % 0xDEAD
        await a.send(t="order", frame=f, cmds=[], hash=ha)
        await b.send(t="order", frame=f, cmds=[], hash=hb)
    msgs = await a.drain(1.0)
    typen = [m.get("t") for m in msgs]
    des = next((m for m in msgs if m.get("t") == "desync"), None)
    pruefe(des is not None, "Vermittler meldet `desync`", typen)
    pruefe(des and des.get("frame") == 2, "Desync nennt den richtigen Rahmen", des)
    pruefe(des and set(des.get("hashes", {}).keys()) == {"0", "1"},
           "Desync listet die Hashes je Platz", des)
    pruefe(typen.index("desync") > typen.index("frame") if "desync" in typen else False,
           "der Rahmen kommt vor der Desync-Meldung", typen)
    await a.close()
    await b.close()


async def teil_abbruch(url, drop_erwartet):
    print("\n[4] Abbruch eines Clients: waiting → peer_left (bis %.0f s)" % drop_erwartet)
    (a, b), code = await raum_starten(url, ["Tom", "Jan"], 2)
    await a.send(t="order", frame=0, cmds=[])
    await b.send(t="order", frame=0, cmds=[])
    fr = await a.expect("frame")
    pruefe(fr and fr.get("t") == "frame", "Rahmen 0 läuft noch", fr)
    await b.kill()
    await a.send(t="order", frame=1, cmds=[])
    wait = None
    left = None
    ende = time.monotonic() + drop_erwartet + 6.0
    while time.monotonic() < ende:
        msg = await a.next(max(0.2, ende - time.monotonic()))
        if msg is None:
            break
        if msg.get("t") == "waiting" and wait is None:
            wait = msg
        elif msg.get("t") == "peer_left":
            left = msg
            break
    pruefe(wait is not None and wait.get("seats") == [1],
           "`waiting` nennt den fehlenden Platz", wait)
    pruefe(left is not None and left.get("seat") == 1 and left.get("frame") == 1,
           "`peer_left` nach Ablauf der Frist", left)
    pruefe(left is not None and "reason" in left, "`peer_left` nennt einen Grund", left)
    await a.close()


async def teil_ratelimit(url):
    print("\n[5] Chat-Rate-Limit (5 Nachrichten / 5 s)")
    a = Peer("Tom")
    await a.hello(url, "Tom")
    await a.send(t="create", map="m", map_sha256="f" * 8, seats=2, settings={})
    await a.expect("created")
    await a.drain(0.2)
    for i in range(8):
        await a.send(t="chat", text="spam %d" % i, scope="all")
    msgs = await a.drain(0.8)
    chats = [m for m in msgs if m.get("t") == "chat"]
    errs = [m for m in msgs if m.get("t") == "error" and m.get("code") == "ratelimit"]
    pruefe(len(chats) == 5, "nur fünf Zeilen kommen durch", len(chats))
    pruefe(len(errs) >= 1, "danach `error{code:ratelimit}`", errs[:1])
    pruefe(not a.closed, "die Verbindung bleibt bestehen")
    await a.send(t="ping", id=7, rtt=42)
    pong = await a.expect("pong")
    pruefe(pong and pong.get("id") == 7 and "t_server" in pong,
           "pong nach dem Rate-Limit", pong)
    await a.close()


async def teil_vier(url):
    print("\n[6] Vier Clients auf einem Sechs-Platz-Raum, Teamchat-Filter")
    peers = []
    for n in ("Tom", "Jan", "Ole", "Mia"):
        p = Peer(n)
        await p.hello(url, n)
        peers.append(p)
    a, b, c, d = peers
    await a.send(t="create", map="keep-off-the-grass-2", map_sha256="f" * 8,
                 seats=6, settings={})
    created = await a.expect("created")
    if created is None or created.get("t") != "created":
        hinweis_ratelimit(created)
        raise RuntimeError("kein created: %r" % (created,))
    code = created["code"]
    pruefe(created.get("seats") == 6, "Raum mit sechs Plätzen", created)
    for i, p in enumerate(peers[1:], start=1):
        await p.send(t="join", code=code, map_sha256="f" * 8)
        await p.expect("lobby", skip=())
        p.seat = i
    a.seat = 0

    for p, team in zip(peers, (1, 1, 2, 2)):
        await p.send(t="slot", team=team, faction="soviet", color=p.seat)
    await asyncio.sleep(0.3)
    for p in peers:
        await p.drain(0.25)


    await a.send(t="bot", op="add", level="normal", faction="allies", team=3)
    lob = await a.expect("lobby", skip=())
    bots = [x for x in (lob or {}).get("clients", []) if x.get("kind") == "bot"]
    pruefe(len(bots) == 1 and bots[0]["seat"] == 4,
           "Host setzt eine KI auf den freien Platz", bots)
    await b.send(t="bot", op="add", level="normal")
    err = await b.expect("error", skip=("lobby",))
    pruefe(err and err.get("code") == "nothost", "KI vom Nicht-Host → nothost", err)
    await a.send(t="bot", op="remove", seat=4)
    await a.expect("lobby", skip=())
    for p in peers:
        await p.drain(0.25)


    await c.send(t="chat", text="#help Süden", scope="team")
    ic = await c.expect("chat", timeout=1.5)
    idd = await d.expect("chat", timeout=1.5)
    pruefe(ic and ic.get("scope") == "team" and ic.get("seat") == 2,
           "Teamzeile erreicht den Absender", ic)
    pruefe(idd and idd.get("text") == "#help Süden", "Teamzeile erreicht den Teamkameraden", idd)
    fremd_a = await a.drain(0.5)
    fremd_b = await b.drain(0.5)
    pruefe(not [m for m in fremd_a if m.get("t") == "chat"],
           "fremdes Team sieht die Teamzeile nicht", fremd_a[:2])
    pruefe(not [m for m in fremd_b if m.get("t") == "chat"],
           "auch der zweite Gegner sieht sie nicht", fremd_b[:2])

    await a.send(t="chat", text="an alle", scope="quatsch")
    alle = [await p.expect("chat", timeout=1.5) for p in peers]
    pruefe(all(m and m.get("scope") == "all" for m in alle),
           "unbekannter scope wird zu `all`", alle[:1])


    for p in peers:
        await p.send(t="ready", on=True)
    await asyncio.sleep(0.3)
    for p in peers:
        await p.drain(0.25)
    await a.send(t="start", setup=aufstellung(code, [0, 1, 2, 3]))
    starts = [await p.expect("start") for p in peers]
    pruefe(all(s and s.get("t") == "start" for s in starts), "alle vier starten", starts[:1])
    for f in range(20):
        for p in peers:
            await p.send(t="order", frame=f, cmds=[[4, 0, 0, 0, 0, 1, 7 + p.seat]])
    frames = []
    while len(frames) < 20:
        msg = await a.next(5.0)
        if msg is None:
            break
        if msg.get("t") == "frame":
            frames.append(msg)
    pruefe(len(frames) == 20 and all(len(m["packets"]) == 4 for m in frames),
           "Bündel mit vier Paketen", len(frames))
    pruefe([m["frame"] for m in frames] == list(range(20)), "Rahmen in Reihenfolge")
    for p in peers:
        await p.close()


async def teil_raumliste(url):
    print("\n[7] Raumliste: oeffentlich/privat, `list`, `visibility`, Rate-Limit")
    a, b, g = Peer("Wirt"), Peer("Heimlich"), Peer("Gast")
    await a.hello(url, "Wirt")
    await b.hello(url, "Heimlich")
    await g.hello(url, "Gast")

    await a.send(t="create", map="keep-off-the-grass-2", map_name="Keep Off The Grass 2",
                 map_sha256="f" * 8, seats=4, settings={}, public=True)
    ca = await a.expect("created")
    hinweis_ratelimit(ca)
    code_pub = (ca or {}).get("code", "")
    lob = await a.expect("lobby", skip=())
    pruefe(lob and lob.get("public") is True, "lobby nennt den Raum oeffentlich", lob)
    pruefe(lob and lob.get("map_name") == "Keep Off The Grass 2",
           "lobby traegt den Kartennamen", lob)

    await b.send(t="create", map="pool-party", map_sha256="e" * 8, seats=2, settings={})
    cb = await b.expect("created")
    hinweis_ratelimit(cb)
    code_priv = (cb or {}).get("code", "")
    lpb = await b.expect("lobby", skip=())
    pruefe(lpb and lpb.get("public") is False, "ohne `public` ist der Raum privat", lpb)

    await g.send(t="list")
    rooms_msg = await g.expect("rooms", skip=())
    rooms = (rooms_msg or {}).get("rooms", [])
    codes = [r.get("code") for r in rooms]
    pruefe(rooms_msg and rooms_msg.get("t") == "rooms", "`list` beantwortet mit `rooms`", rooms_msg)
    pruefe(code_pub in codes, "der oeffentliche Raum steht in der Liste", codes)
    pruefe(code_priv not in codes, "der private Raum steht NICHT in der Liste", codes)
    zeile = next((r for r in rooms if r.get("code") == code_pub), {})
    pruefe(zeile.get("map") == "keep-off-the-grass-2"
           and zeile.get("map_name") == "Keep Off The Grass 2"
           and zeile.get("seats_used") == 1 and zeile.get("seats_total") == 4
           and zeile.get("started") is False and zeile.get("host_name") == "Wirt"
           and zeile.get("public") is True,
           "Zeile: Karte, Plaetze, Zustand, Gastgeber", zeile)
    pruefe(not [k for k in zeile if k in ("ip", "settings", "clients")],
           "Zeile ohne IP, Einstellungen und Mitspielerliste", list(zeile))


    await g.send(t="list")
    err = await g.expect("error", skip=())
    pruefe(err and err.get("code") == "ratelimit", "zweites `list` sofort danach → ratelimit", err)
    pruefe(not g.closed, "die Verbindung bleibt nach dem Rate-Limit bestehen")
    await asyncio.sleep(2.1)
    await g.send(t="list")
    r2 = await g.expect("rooms", skip=())
    pruefe(r2 and r2.get("t") == "rooms", "nach zwei Sekunden geht `list` wieder", r2)


    await g.send(t="join", code=code_pub, map_sha256="f" * 8)
    lg = letzte_lobby(await g.drain(0.4))
    pruefe(lg and len(lg.get("clients", [])) == 2, "Beitritt ueber den Code aus der Liste", lg)
    await a.drain(0.3)


    await g.send(t="visibility", public=False)
    err = await g.expect("error", skip=("lobby",))
    pruefe(err and err.get("code") == "nothost", "visibility vom Nicht-Host → nothost", err)
    await a.send(t="visibility", public=False)
    lv = letzte_lobby(await a.drain(0.4))
    pruefe(lv and lv.get("public") is False, "visibility: lobby.public wird false", lv)
    lvg = letzte_lobby(await g.drain(0.3))
    pruefe(lvg and lvg.get("public") is False, "der Gast bekommt die neue Sichtbarkeit", lvg)

    h = Peer("Sucher")
    await h.hello(url, "Sucher")
    await h.send(t="list")
    r3 = await h.expect("rooms", skip=())
    pruefe(code_pub not in [r.get("code") for r in (r3 or {}).get("rooms", [])],
           "nach dem Umschalten ist der Raum verborgen", r3)


    await a.send(t="visibility", public=True)
    await a.drain(0.3)
    await g.drain(0.3)
    await a.send(t="ready", on=True)
    await g.send(t="ready", on=True)
    await asyncio.sleep(0.25)
    await a.drain(0.25)
    await g.drain(0.25)
    await a.send(t="start", setup=aufstellung(code_pub, [0, 1]))
    st = await a.expect("start")
    pruefe(st and st.get("t") == "start", "Partie startet", st)
    await g.drain(0.3)
    await asyncio.sleep(2.1)
    await h.send(t="list")
    r4 = await h.expect("rooms", skip=())
    zeile2 = next((r for r in (r4 or {}).get("rooms", []) if r.get("code") == code_pub), {})
    pruefe(zeile2.get("started") is True, "laufende Partie steht mit `started` in der Liste", zeile2)
    pruefe(zeile2.get("seats_used") == 2, "belegte Plaetze stimmen", zeile2)

    for p in (a, b, g, h):
        await p.close()


async def teil_teams(url):

    print("\n[5] Teams und Startpunkte")
    a, b = Peer("A"), Peer("B")
    await a.hello(url, "Tom")
    await a.send(t="create", map="pool-party", map_sha256="d" * 8, seats=4,
                 settings={"credits": 5000})
    created = await a.expect("created")
    hinweis_ratelimit(created)
    code = (created or {}).get("code", "")
    pruefe(bool(code), "Raum für den Teamtest angelegt", created)
    await a.expect("lobby", skip=())
    await b.hello(url, "Jan")
    await b.send(t="join", code=code, map_sha256="d" * 8)
    lb = await b.expect("lobby", skip=())
    pruefe(lb and len(lb.get("clients", [])) == 2, "zwei Spieler in der Lobby", lb)
    await a.drain(0.2)


    await a.send(t="slot", faction="allies", team=1, color=0, spawn=-1)
    await b.send(t="slot", faction="soviet", team=1, color=1, spawn=-1)
    await asyncio.sleep(0.25)
    la = letzte_lobby(await a.drain(0.4))
    lb = letzte_lobby(await b.drain(0.4))
    teams_a = [k.get("team") for k in (la or {}).get("clients", [])]
    teams_b = [k.get("team") for k in (lb or {}).get("clients", [])]
    pruefe(teams_a == [1, 1], "Gastgeber sieht beide Teams", teams_a)
    pruefe(teams_b == [1, 1], "Gast sieht beide Teams", teams_b)


    await a.send(t="slot", spawn=2)
    await asyncio.sleep(0.2)
    lb = letzte_lobby(await b.drain(0.4))
    pruefe(lb and [k.get("spawn") for k in lb.get("clients", [])] == [2, -1],
           "Startpunkt des Gastgebers erreicht den Gast", lb)
    await a.drain(0.2)
    await b.send(t="slot", spawn=2)
    err = await b.expect("error", skip=())
    pruefe(err and err.get("code") == "spawnoccupied",
           "belegter Startpunkt wird abgewiesen", err)
    lb = letzte_lobby(await b.drain(0.4))
    pruefe(lb and [k.get("spawn") for k in lb.get("clients", [])] == [2, -1],
           "abgewiesener Wunsch ändert nichts", lb)
    await a.drain(0.3)
    await b.send(t="slot", spawn=3)
    await asyncio.sleep(0.2)
    la = letzte_lobby(await a.drain(0.4))
    pruefe(la and [k.get("spawn") for k in la.get("clients", [])] == [2, 3],
           "freier Startpunkt geht durch und erreicht alle", la)
    await b.drain(0.2)

    await a.send(t="slot", spawn=-1)
    await asyncio.sleep(0.2)
    await a.drain(0.3)
    await b.drain(0.3)
    await b.send(t="slot", spawn=2)
    await asyncio.sleep(0.2)
    la = letzte_lobby(await a.drain(0.4))
    pruefe(la and [k.get("spawn") for k in la.get("clients", [])] == [-1, 2],
           "freigegebener Startpunkt ist wieder wählbar", la)
    await b.drain(0.2)


    await a.send(t="bot", op="add", level="normal", faction="allies", team=0)
    await asyncio.sleep(0.2)
    await a.drain(0.3)
    await b.drain(0.3)
    await b.send(t="slot", seat=2, team=2)
    err = await b.expect("error", skip=())
    pruefe(err and err.get("code") == "nothost", "fremder Platz nur für den Gastgeber", err)
    await a.send(t="slot", seat=2, team=1)
    await asyncio.sleep(0.2)
    lb = letzte_lobby(await b.drain(0.4))
    pruefe(lb and [k.get("team") for k in lb.get("clients", [])] == [1, 1, 1],
           "Gastgeber setzt das Team des KI-Platzes, alle sehen es", lb)
    await a.drain(0.2)


    await a.send(t="slot", seat=2, spawn=3)
    await asyncio.sleep(0.2)
    lb = letzte_lobby(await b.drain(0.4))
    pruefe(lb and [k.get("spawn") for k in lb.get("clients", [])] == [-1, 2, 3],
           "Gastgeber setzt den Startpunkt des KI-Platzes, alle sehen ihn", lb)
    await a.drain(0.2)
    await a.send(t="slot", seat=2, spawn=2)
    err = await a.expect("error", skip=())
    pruefe(err and err.get("code") == "spawnoccupied",
           "belegter Startpunkt wird auch fuer einen KI-Platz abgewiesen", err)
    lb = letzte_lobby(await a.drain(0.4))
    pruefe(lb and [k.get("spawn") for k in lb.get("clients", [])] == [-1, 2, 3],
           "abgewiesener KI-Wunsch aendert nichts", lb)
    await b.drain(0.3)
    await a.send(t="slot", seat=2, spawn=-1)
    await asyncio.sleep(0.2)
    await a.drain(0.3)
    await b.drain(0.3)


    await a.send(t="ready", on=True)
    await b.send(t="ready", on=True)
    await asyncio.sleep(0.25)
    await a.drain(0.3)
    await b.drain(0.3)
    setup = aufstellung(code, [0, 1, 2])
    for e in setup["seats"]:
        e["team"] = 0
    await a.send(t="start", setup=setup)
    sa = await a.expect("start")
    sb = await b.expect("start")
    got = [e.get("team") for e in (sa or {}).get("setup", {}).get("seats", [])]
    pruefe(got == [1, 1, 1], "Vermittler stempelt die gültigen Teams in die Aufstellung", got)
    pruefe(sb and [e.get("team") for e in sb.get("setup", {}).get("seats", [])] == [1, 1, 1],
           "beide Seiten bekommen dieselbe Aufstellung", sb)
    await a.close()
    await b.close()


async def liste(url, name="Sucher"):

    p = Peer(name)
    await p.hello(url, name)
    await p.send(t="list")
    msg = await p.expect("rooms", skip=("lobby",))
    await p.close()
    return (msg or {}).get("rooms", [])


def zeile(rooms, code):
    for r in rooms:
        if r.get("code") == code:
            return r
    return None


async def teil_wiederverbinden(url, resume_s):

    print("\n[8] Hintergrund: session, resume, watch (Frist %.0f s)" % resume_s)
    a, b = Peer("Tom"), Peer("Jan")
    await a.hello(url, "Tom")
    await a.send(t="create", map="keep-off-the-grass-2", map_sha256="f" * 8, seats=2,
                 settings={"credits": 5000}, public=True)
    created = await a.expect("created")
    hinweis_ratelimit(created)
    code = (created or {}).get("code", "")
    await a.drain(0.3)
    pruefe(a.session is not None and a.session.get("seat") == 0
           and len(str(a.session.get("token", ""))) >= 12,
           "create: `session` bringt Platz und Geheimnis", a.session)
    pruefe(a.session is not None and a.session.get("host") is True
           and int(a.session.get("resume_s", 0)) > 0,
           "session nennt Gastgeberrolle und Frist", a.session)
    token_a = (a.session or {}).get("token", "")

    await b.hello(url, "Jan")
    await b.send(t="join", code=code, map_sha256="f" * 8)
    await b.drain(0.4)
    pruefe(b.session is not None and b.session.get("seat") == 1
           and b.session.get("token") not in (None, "", token_a),
           "join: eigenes `session` mit eigenem Geheimnis", b.session)

    vorher = zeile(await liste(url), code)
    pruefe(vorher is not None and vorher.get("seats_used") == 2,
           "Raum steht mit zwei Plaetzen in der Liste", vorher)


    await a.kill()
    await asyncio.sleep(0.6)
    lb = letzte_lobby(await b.drain(0.4))
    pruefe(lb is not None, "der Gast bekommt eine neue lobby", lb)
    reihe0 = None
    for k in (lb or {}).get("clients", []):
        if k.get("seat") == 0:
            reihe0 = k
    pruefe(reihe0 is not None and reihe0.get("absent") is True,
           "Platz des Gastgebers bleibt reserviert und ist als `absent` gekennzeichnet", reihe0)
    pruefe(lb is not None and lb.get("host_seat") == 0,
           "die Gastgeberrolle wandert nicht weiter", lb)
    danach = zeile(await liste(url), code)
    pruefe(danach is not None and danach.get("seats_used") == 2,
           "der Raum bleibt in der Raumliste stehen", danach)


    x = Peer("Dieb")
    await x.hello(url, "Dieb")
    await x.send(t="resume", code=code, token="dasistfalsch")
    err = await x.expect("error", skip=("lobby",))
    pruefe(err and err.get("code") == "notallowed", "falsches Geheimnis → notallowed", err)
    await x.close()


    a2 = Peer("Tom2")
    await a2.hello(url, "Tom")
    await a2.send(t="resume", code=code, token=token_a)
    await a2.drain(0.5)
    pruefe(a2.session is not None and a2.session.get("seat") == 0
           and a2.session.get("code") == code,
           "resume setzt denselben Spieler auf denselben Platz", a2.session)
    lb2 = letzte_lobby(await b.drain(0.4))
    pruefe(lb2 is not None and all(not k.get("absent") for k in lb2.get("clients", []))
           and len(lb2.get("clients", [])) == 2,
           "nach dem resume ist kein Platz mehr `absent`", lb2)
    await a2.send(t="visibility", public=False)
    lv = letzte_lobby(await a2.drain(0.4))
    pruefe(lv is not None and lv.get("public") is False,
           "der Zurueckgekehrte ist wieder Gastgeber (visibility ohne nothost)", lv)


    await b.send(t="leave")
    await asyncio.sleep(0.4)
    ll = letzte_lobby(await a2.drain(0.4))
    pruefe(ll is not None and len(ll.get("clients", [])) == 1,
           "`leave` gibt den Platz sofort frei (kein reservierter Platz)", ll)
    await b.close()


    w = Peer("Dienst")
    await w.hello(url, "Dienst")
    await w.send(t="watch", code=code, token=token_a)
    obs = await w.expect("watching", skip=())
    pruefe(obs and obs.get("seat") == 0, "watch: Beobachter haengt am eigenen Platz", obs)
    lw = await w.expect("lobby", skip=())
    pruefe(lw is not None and lw.get("code") == code,
           "watch: der Beobachter bekommt die lobby", lw)
    await a2.kill()
    await asyncio.sleep(resume_s + 1.0)
    steht = zeile(await liste(url), code)
    pruefe(steht is None or steht.get("public") is False,
           "privater Raum taucht nicht in der Liste auf", steht)
    a3 = Peer("Tom3")
    await a3.hello(url, "Tom")
    await a3.send(t="resume", code=code, token=token_a)
    await a3.drain(0.5)
    pruefe(a3.session is not None and a3.session.get("seat") == 0,
           "der Beobachter hat Raum und Platz ueber die Frist gehalten", a3.session)

    c2 = Peer("Ada")
    await c2.hello(url, "Ada")
    await c2.send(t="join", code=code, map_sha256="f" * 8)
    await c2.drain(0.4)
    await w.drain(0.3)
    await c2.send(t="chat", text="Bin da!", scope="all")
    ch = await w.expect("chat", skip=("lobby",))
    pruefe(ch and ch.get("text") == "Bin da!" and ch.get("seat") == 1,
           "watch: Chat eines Mitspielers erreicht den Beobachter", ch)
    await w.close()
    await c2.close()
    await a3.close()


    if resume_s <= 5.0:
        d = Peer("Kurz")
        await d.hello(url, "Kurz")
        await d.send(t="create", map="keep-off-the-grass-2", map_sha256="f" * 8, seats=2,
                     settings={}, public=True)
        cr = await d.expect("created")
        hinweis_ratelimit(cr)
        code2 = (cr or {}).get("code", "")
        await d.drain(0.3)
        token_d = (d.session or {}).get("token", "")
        await d.kill()
        await asyncio.sleep(resume_s + 1.0)
        e2 = Peer("Kurz2")
        await e2.hello(url, "Kurz")
        await e2.send(t="resume", code=code2, token=token_d)
        err2 = await e2.expect("error", skip=("lobby",))
        pruefe(err2 and err2.get("code") == "nocode",
               "nach Ablauf der Frist ist der Raum verschwunden", err2)
        await e2.close()
    else:
        print("  --   Ablauf der Frist uebersprungen (Vermittler haelt %.0f s)" % resume_s)


def sprachpaket(bytes_roh=244):

    return base64.b64encode(bytes(range(256)) * (bytes_roh // 256 + 1))[:((bytes_roh + 2) // 3) * 4].decode()


async def teil_sprechfunk(url):
    print("\n[8] Sprechfunk: Team-Kanal, offener Kanal, Groesse, Rate-Limit, kein Befehlsstrom")
    peers = []
    for n in ("Tom", "Jan", "Ole", "Mia"):
        p = Peer(n)
        await p.hello(url, n)
        peers.append(p)
    a, b, c, d = peers
    await a.send(t="create", map="keep-off-the-grass-2", map_sha256="f" * 8, seats=4, settings={})
    created = await a.expect("created")
    if created is None or created.get("t") != "created":
        hinweis_ratelimit(created)
        raise RuntimeError("kein created: %r" % (created,))
    code = created["code"]
    a.seat = 0
    for i, p in enumerate(peers[1:], start=1):
        await p.send(t="join", code=code, map_sha256="f" * 8)
        await p.expect("lobby", skip=())
        p.seat = i

    for p, team in zip(peers, (1, 1, 2, 2)):
        await p.send(t="slot", team=team, faction="soviet", color=p.seat)
    await asyncio.sleep(0.3)
    for p in peers:
        await p.drain(0.25)

    nutz = sprachpaket()

    await a.send(t="voice", scope="team", seq=1, data=nutz)
    vb = await b.expect("voice", timeout=1.5)
    pruefe(vb and vb.get("t") == "voice" and vb.get("seat") == 0 and vb.get("name") == "Tom"
           and vb.get("scope") == "team" and vb.get("data") == nutz and vb.get("seq") == 1
           and vb.get("codec") == "adpcm8" and "color" in vb,
           "Team-Kanal: Paket erreicht den Teamkameraden, mit Stempel des Vermittlers", vb)
    rest_c = await c.drain(0.4)
    rest_d = await d.drain(0.4)
    pruefe(not [m for m in rest_c if m.get("t") == "voice"],
           "Team-Kanal: das andere Team hoert nichts", rest_c[:2])
    pruefe(not [m for m in rest_d if m.get("t") == "voice"],
           "Team-Kanal: auch der zweite Gegner hoert nichts", rest_d[:2])
    rest_a = await a.drain(0.3)
    pruefe(not [m for m in rest_a if m.get("t") == "voice"],
           "der Absender bekommt sein eigenes Paket nicht zurueck", rest_a[:2])
    pruefe(vb is not None and "text" not in vb, "Sprachpaket traegt keinen Chattext", vb)


    await a.send(t="voice", scope="all", seq=2, data=nutz)
    offen = [await p.expect("voice", timeout=1.5) for p in (b, c, d)]
    pruefe(all(m and m.get("scope") == "all" and m.get("seq") == 2 for m in offen),
           "offener Kanal erreicht alle im Raum (auch die Gegner)", offen[:1])

    await b.send(t="voice", scope="quatsch", data=nutz)
    fallback = [await p.expect("voice", timeout=1.5) for p in (a, c, d)]
    pruefe(all(m and m.get("scope") == "all" for m in fallback),
           "unbekannter scope wird zu `all`", fallback[:1])

    await a.send(t="voice", scope="all", seq=3, data=nutz, end=True)
    ve = await b.expect("voice", timeout=1.5)
    pruefe(ve and ve.get("end") is True, "`end` wird durchgereicht", ve)


    await a.send(t="voice", scope="all", data="A" * 5000)
    err = await a.expect("error", timeout=1.5)
    pruefe(err and err.get("code") == "badstate" and err.get("field") == "data",
           "zu grosses Sprachpaket → badstate", err)
    pruefe(not a.closed, "die Verbindung bleibt nach dem zu grossen Paket bestehen")
    await a.send(t="voice", scope="all", data="nicht base64 !!!")
    err = await a.expect("error", timeout=1.5)
    pruefe(err and err.get("code") == "badstate", "Sprachpaket ohne Base64 → badstate", err)
    keins = await b.drain(0.4)
    pruefe(not [m for m in keins if m.get("t") == "voice"],
           "verworfene Pakete werden nicht weitergereicht", keins[:2])


    for p in peers:
        await p.send(t="ready", on=True)
    await asyncio.sleep(0.3)
    for p in peers:
        await p.drain(0.25)
    await a.send(t="start", setup=aufstellung(code, [0, 1, 2, 3]))
    starts = [await p.expect("start") for p in peers]
    pruefe(all(s and s.get("t") == "start" for s in starts), "Partie startet", starts[:1])
    for f in range(20):
        for p in peers:
            await p.send(t="order", frame=f, cmds=[[4, 0, 0, 0, 0, 1, 7 + p.seat]])
        await a.send(t="voice", scope="all", seq=10 + f, data=nutz)
        await asyncio.sleep(0.002)
    frames, stimmen, sonstiges = [], [], []
    while len(frames) < 20:
        msg = await b.next(6.0)
        if msg is None:
            break
        if msg.get("t") == "frame":
            frames.append(msg)
        elif msg.get("t") == "voice":
            stimmen.append(msg)
        elif msg.get("t") != "waiting":
            sonstiges.append(msg)
    pruefe(len(frames) == 20 and [m["frame"] for m in frames] == list(range(20)),
           "der Gleichschritt laeuft waehrend des Sprechfunks unveraendert weiter", len(frames))
    pruefe(all(len(m["packets"]) == 4 for m in frames), "jeder Rahmen buendelt weiter vier Plaetze")
    pruefe(all(set(p.keys()) <= {"seat", "cmds", "hash"} for m in frames for p in m["packets"]),
           "kein Sprachpaket im Befehlsstrom (Pakete tragen nur seat/cmds/hash)",
           [p for m in frames for p in m["packets"] if set(p.keys()) - {"seat", "cmds", "hash"}][:1])
    pruefe(all(m["packets"][i]["cmds"] == [[4, 0, 0, 0, 0, 1, 7 + i]]
               for m in frames for i in range(4)),
           "die Befehlsfelder kommen unveraendert an")
    pruefe(len(stimmen) >= 15, "die Sprachpakete kommen daneben eigenstaendig an", len(stimmen))
    pruefe(not sonstiges, "keine unerwarteten Nachrichten waehrend Rahmen + Sprechfunk",
           sonstiges[:2])
    for p in peers:
        await p.close()


    e = Peer("Vielredner")
    await e.hello(url, "Vielredner")
    await e.send(t="create", map="m", map_sha256="f" * 8, seats=2, settings={})
    ce = await e.expect("created")
    hinweis_ratelimit(ce)
    f2 = Peer("Zuhoerer")
    await f2.hello(url, "Zuhoerer")
    await f2.send(t="join", code=(ce or {}).get("code", ""), map_sha256="f" * 8)
    await f2.expect("lobby", skip=())
    await e.drain(0.25)
    await f2.drain(0.25)
    for i in range(260):
        await e.send(t="voice", scope="all", seq=i, data=nutz)
    msgs_e = await e.drain(1.2)
    msgs_f = await f2.drain(1.0)
    durch = [m for m in msgs_f if m.get("t") == "voice"]
    errs = [m for m in msgs_e if m.get("t") == "error" and m.get("code") == "ratelimit"]
    pruefe(0 < len(durch) <= 150, "hoechstens 150 Sprachpakete je 5 s kommen durch", len(durch))
    pruefe(len(errs) >= 1, "danach `error{code:ratelimit}`", errs[:1])
    pruefe(len(errs) <= 3, "die ratelimit-Meldung wird gedrosselt (nicht je Paket)", len(errs))
    pruefe(not e.closed, "die Verbindung bleibt beim Sprechfunk-Rate-Limit bestehen")
    await e.send(t="ping", id=9)
    pong = await e.expect("pong", timeout=2.0)
    pruefe(pong and pong.get("id") == 9, "nach dem Rate-Limit antwortet der Vermittler weiter", pong)
    await e.close()
    await f2.close()


async def lauf(url, schnell, drop_erwartet, resume_s):
    a, b, code = await teil_lobby(url)
    await teil_rahmen(a, b)
    await a.close()
    await b.close()
    await teil_desync(url)
    await teil_ratelimit(url)
    await teil_vier(url)
    await teil_raumliste(url)
    await teil_teams(url)
    await teil_wiederverbinden(url, resume_s)
    await teil_sprechfunk(url)
    if schnell:
        print("\n[4] Abbruchtest übersprungen (--schnell)")
    else:
        await teil_abbruch(url, drop_erwartet)


def main(argv=None):
    p = argparse.ArgumentParser(description="Prüfclients für den Mehrspieler-Vermittler")
    p.add_argument("--url", default=None,
                   help="ws://…/mp; ohne Angabe wird ein eigener Vermittler gestartet")
    p.add_argument("--port", type=int, default=8799, help="Port des eigenen Vermittlers")
    p.add_argument("--schnell", action="store_true", help="Abbruchtest weglassen")
    p.add_argument("--drop-s", type=float, default=None,
                   help="erwartete Frist bis `peer_left` (Vorgabe: 3 s lokal, 20 s fremd)")
    p.add_argument("--resume-s", type=float, default=None,
                   help="Frist des Vermittlers fuer reservierte Plaetze (Vorgabe: 2 s lokal, 180 s fremd)")
    args = p.parse_args(argv)

    proc = None
    url = args.url
    drop = args.drop_s
    resume = args.resume_s
    if url is None:
        cmd = [sys.executable, os.path.join(HERE, "mp_server.py"),
               "--host", "127.0.0.1", "--port", str(args.port),
               "--waiting-ms", "300", "--drop-s", "3", "--resume-s", "2",
               "--create-per-min", "40"]
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True)
        url = "ws://127.0.0.1:%d/mp" % args.port
        if drop is None:
            drop = 3.0
        if resume is None:
            resume = 2.0
        time.sleep(1.0)
        print("eigener Vermittler auf %s (PID %d)" % (url, proc.pid))
    else:
        if drop is None:
            drop = 20.0
        if resume is None:
            resume = 180.0

    print("Prüfe %s" % url)
    t0 = time.monotonic()
    try:
        asyncio.run(lauf(url, args.schnell, drop, resume))
    except Exception as exc:
        FAIL.append("Ausnahme: %r" % (exc,))
        import traceback
        traceback.print_exc()
    finally:
        if proc:
            proc.terminate()
            try:
                out = proc.communicate(timeout=5)[0]
            except subprocess.TimeoutExpired:
                proc.kill()
                out = ""
            if FAIL and out:
                print("\n--- Protokoll des Vermittlers ---")
                print(out)

    print("\n%d geprüft, %d Fehler, %.1f s" % (len(OK) + len(FAIL), len(FAIL),
                                               time.monotonic() - t0))
    for f in FAIL:
        print("  FEHL %s" % f)
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
