# Laya-Dienst für den KI-Kommandeur (Phase 3)

Lokaler HTTP-Dienst, der das Entscheidungsmodell Laya (Convai Innovations, Apache-2.0,
github.com/NandhaKishorM/laya) für den Kommandeur der Gefechts-KI befragt. Plan und
Bewertung: `docs/KI-LAYA.md` (Zweig `feature/ki-laya`). Nur für Mac, Windows und Server;
im Mehrspieler wird der Client nie aufgerufen (regelt ProtoWorld).

Modell: multilinguale Fassung (mmBERT-base, 322M Parameter) als INT8-ONNX aus
`soyelmismo/laya-multilingual-onnx` (Revision `0966c4f`, 325 MB plus 34 MB Tokenizer).
Laufzeit: onnxruntime und `tokenizers`, **kein PyTorch**.

## Ausprobieren am Mac

```
tools/laya/start.sh     # legt bei Bedarf venv und Modell an, startet den Dienst, dann das Spiel
tools/laya/stop.sh      # Dienst beenden
```

`start.sh` wartet, bis `POST /decide` antwortet (Log `build/laya/service.log`), und startet dann
`build/macos-dist/PocketRA.app` oder, ohne exportierte App, Godot mit `--path game`, jeweils mit
`--commander-url http://127.0.0.1:8765/decide`. `--godot` nimmt immer den Quellbaum, `--nur-dienst`
startet nur den Dienst. Statt des Startparameters geht auch die Einstellung im Spiel: Optionen,
„KI-Kommandeur: Laya-Dienst" auf an (Adresse darunter, `user://settings.cfg [commander]`). Im
Gefecht zeigt ein Panel links oben je KI-Gegner Quelle (Laya/Regel), Doktrin, Haltung, Latenz und
Rückfälle; im Pausenmenü „Kommandeur anzeigen". Einzelheiten: `docs/KI-LAYA.md` §10.

## Dateien

| Datei | Zweck |
|---|---|
| `download_model.py` | Gewichte nach `build/laya/multilingual-int8/` im Haupt-Checkout, SHA-256 geprüft (`--variant fp32` für 1,29 GB FP32) |
| `laya_core.py` | Prompt-Layout, Tokenisierung, ONNX-Lauf, Temperatur, Confidence. Portiert aus `laya/common.py` und `laya/onnx_agent.py` |
| `service.py` | FastAPI: `POST /decide`, `GET /health`, Micro-Batching, CORS |
| `start.sh`, `stop.sh` | Dienst samt venv und Modell starten und das Spiel mit Kommandeur-Client öffnen; Dienst beenden |
| `kommandeur_format.py` | Anfragetext aus Zusammenfassung und Fragen, Gegenstück zu `game/scripts/ai/commander_client.gd` |
| `beispiel_anfrage.json` | Beispiel (Zusammenfassung, Fragen, fertige Anfrage); der Godot-Test vergleicht damit |
| `proben.py` | fünf handgebaute Lagen gegen den laufenden Dienst |
| `bench.py` | Last mit fester Ankunftsrate: p50/p95, Durchsatz, Speicher |
| `finetune/` | Phase 5 vorbereitet: `build_dataset.py`, `train.md` |

## Start

```
python3.13 -m venv build/.venv_laya
build/.venv_laya/bin/pip install -r tools/laya/requirements.txt
build/.venv_laya/bin/python tools/laya/download_model.py
build/.venv_laya/bin/python tools/laya/service.py        # http://127.0.0.1:8765
```

Umgebung: `LAYA_MODEL_DIR`, `LAYA_HOST` (127.0.0.1), `LAYA_PORT` (8765),
`LAYA_BATCH_WINDOW_MS` (75), `LAYA_MAX_BATCH_ROWS` (64), `LAYA_THREADS` (0 = ORT-Vorgabe),
`LAYA_KEEPWARM_S` (15), `LAYA_CORS_ORIGINS` (`*`).

Docker (nur CPU, Gewichte als Volume):
`docker build -t pocketra-laya tools/laya` und
`docker run --rm -p 8765:8765 -v "$PWD/build/laya/multilingual-int8:/models:ro" pocketra-laya`.

Die venv nicht gleichzeitig mit der TTS-venv betreiben (RAM).

## Format

Anfrage wie Layas eigener Dienst (`laya/serve.py`): `{"state": <Text oder JSON>,
"questions": {id: {"type": "choice"|"score"|"noul", "instructions": "...", "criteria": ...}}}`.
`choice`: `{option: beschreibung}`, `score`: Liste der Stufen mit Beschreibung,
`noul`: optional `{"false": ..., "true": ...}`. Antwort wie `ONNXAgent.predict`:
`answers[id]` mit `probabilities`, `choice`/`score`/`noul`, `confidence`, `answer_confidence`,
dazu `usage`, `latency_ms` und `timing` (Warten, Rechnen, Stapelgröße).

Jede Frage ist eine eigene Sequenz: `[CLS] <typ> question: <anweisung> [SEP] [MASK] opt0
[MASK] opt1 … [SEP] <state> [SEP]`, die Logits an den `[MASK]`-Positionen gehen durch die
Temperatur des Checkpoints (hier 1,0) und eine Softmax. Der Port ist gegen den Referenzcode
geprüft: gleiche Token, gleiche Marker, gleiche Antworten wie `laya.ONNXAgent`.

State: der Client schickt kompakten englischen Text (122 Token für das Beispiel, JSON 149).
Das Laya-Repo nennt kein besseres Format; in den Handproben lagen beide gleich (s. u.), Text
ist kürzer. `state_format = "json"` schaltet um.

**Reihenfolge der Optionen gehört zum Prompt.** Godots `JSON.stringify` sortiert die Schlüssel
von selbst; mit sortierten Optionen kam für dieselbe Lage `land_push` 0,89 statt 0,77 heraus.
Der Client schickt deshalb unsortiert, und der Test prüft die Reihenfolge mit.

## Messung (2026-09-29, Apple M4 Pro, 14 Kerne, 24 GB)

Nebenlast während aller Messungen: 7 bis 25 Godot-Turnierläufe einer anderen Sitzung und ein
fremder Python-Prozess mit 100 % CPU, Last 8 bis 16. Die Zahlen sind eher pessimistisch.

| | Wert |
|---|---|
| Ladezeit (Datei im Cache) | 0,7 s, im Docker-Container 1,0 s |
| Speicher nach dem Laden | 1,26 GB RSS (Tokenizer allein 0,43 GB, ORT-Sitzung 0,72 GB) |
| Speicherspitze | 1,29 GB bei 4 Anfragen/s; 2,0 bis 2,7 GB bei Überlast (Stapel bis 64 Zeilen) |
| Rechenzeit je Frage | 40 bis 50 ms (185 Token je Zeile), Stapeln spart auf der CPU nichts |
| 2 Anfragen/s, 60 s | p50 284 ms, p95 304 ms, alle unter 1 s |
| 4 Anfragen/s, 60 s | p50 283 ms, p95 295 ms, alle unter 1 s |
| 6 Anfragen/s, 60 s | Überlast: Durchsatz 3,9/s, p95 32,5 s |
| **20 Anfragen/s, 60 s** | **Ziel verfehlt:** Durchsatz 3,99/s, p50 118 s, p95 234 s, 0,2 % unter 1 s |

Eine Anfrage hat fünf Fragen, also fünf Zeilen. Die Obergrenze liegt bei rund 20 Zeilen/s
oder 4 Anfragen/s. Das Ziel „p95 unter 500 ms" gilt bis etwa 4 Anfragen/s; 20 Anfragen/s
bräuchten rund fünfmal so viel Rechenleistung (mehr Kerne oder GPU, nicht gemessen). Im Spiel
fragen höchstens 7 KIs alle 4 bis 16 s, also unter 2 Anfragen/s.

Warmhalten: Ohne Last lagert macOS die Gewichte aus; die erste Anfrage nach einer Pause brauchte
über 1 s und lief ins Zeitlimit des Clients. Der Dienst rechnet deshalb alle 15 s eine Kurzzeile.

## Handproben (zero-shot, ehrlich)

`proben.py`, fünf Lagen, neun Erwartungen: **3 von 9 getroffen, in beiden Formaten.** Das
Modell antwortet praktisch lagenunabhängig: `land_push` (0,77 bis 0,97) auch auf der Inselkarte
ohne Landweg, `attack` auch bei schwerem Angriff auf die eigene Basis, `keep_using_air` 0,96 bis
0,99 auch bei hohen Luftverlusten und starker Flak, `base_threat` immer um 0,5, `economy` „ok"
auch ohne Geld. Die drei Treffer sind Zufall der Vorliebe. Ein Drehen der Optionsreihenfolge
ändert das nicht (kein reiner Positionseffekt). Gegenprobe mit dem PyTorch-Original: dieselben
Antworten (25 Fragen, größte Abweichung 0,18, eine Kippe bei einem Beinahe-Gleichstand); die
Schwäche liegt also am Modell, nicht an INT8 oder am Port. Das passt zu den „Honest limits" im
Laya-README („not a zero-shot decision engine"). Brauchbar wird es erst mit Fine-Tuning (Phase 5).

INT8 ist nicht plattformgleich: im Linux-Container (arm64) kam für das Beispiel `land_push`
0,68 statt 0,77 am Mac. Für den Gleichschritt spielt das keine Rolle, weil nur die fertige
Direktive als Befehl läuft.

## Browser

Der Dienst setzt CORS-Kopfzeilen (Standard `*`) und beantwortet Chromes Vorabfrage
für Private Network Access. Versorgt wird die Browser-Fassung aber erst in Phase 4 (Inferenz im Gerät); eine
Seite auf pocketra.net erreicht keinen Dienst auf dem Rechner des Spielers ohne dessen Zutun.
