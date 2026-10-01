# Laya für den Kommandeur nachtrainieren (Phase 5, vorbereitet, nicht ausgeführt)

Grundlage: `docs/finetune.md` und das Notebook
`notebooks/laya_finetune_typed_decisions_2xT4_kaggle.ipynb` im Laya-Repo
(github.com/NandhaKishorM/laya, Stand 9d95567). Zero-shot beantwortet Laya unsere Lagen praktisch
konstant (siehe `../README.md`, Handproben); laut `docs/finetune.md` liegt „most of the value"
im Fine-Tuning (typed-decisions: 0,36 zero-shot, 0,766 nachtrainiert).

## 1. Daten sammeln

Voraussetzung sind Phase 1 und 2 (Regel-Kommandeur, Zeile `KOMMANDEUR {json}` je Entscheidung,
`tools/ai_tournament.py` sammelt je Partie eine `.jsonl` nach `build/ai_log/`). Dann:

```
python3 tools/laya/finetune/build_dataset.py --logs build/ai_log --out build/laya/dataset
```

Nur Entscheidungen des Siegers, weiche Ziele je Option, 10 % der Partien als `test.jsonl`.
Zeilenformat wie `LocalLLaMA/typed-decisions` (`id`, `workflow`, `state`, `questions`, `gold`,
die letzten drei als JSON-Strings), damit Zelle 6 des Notebooks unverändert liest.

Menge: `docs/finetune.md` nennt ~30k Fragen für einen echten Lauf. Bei fünf Fragen je
Entscheidung und rund 30 Sieger-Entscheidungen je Partie (Takt 200 Ticks, 24000 Ticks) sind das
etwa 200 Partien, nach dem Entfernen doppelter Lagen eher mehr. Achtung „the loop is only as good
as the targets": der Lehrer ist hier der Regel-Kommandeur des Siegers. Laya lernt also höchstens
so gut wie die Regel, außer man nimmt Entscheidungen verschiedener Regel-Fassungen oder
Handkorrekturen dazu.

## 2. Notebook anpassen (Kaggle, GPU T4 x2, Internet an)

1. **Multilingualen Checkpoint laden.** Das Notebook nimmt den englischen Wurzelordner
   (`snapshot_download("convaiinnovations/laya")`). Für uns: `model_dir =
   os.path.join(snapshot_download("convaiinnovations/laya"), "multilingual")`; von dort kommen
   `tokenizer/`, `encoder/`, `model.safetensors` und `rl_agent_config.json` (mmBERT-base,
   `max_len` 1024, `head_max_len` 256, genau die Werte, die `train_ddp.py` setzt). Ohne diesen
   Schritt tokenisiert Zelle 6 mit dem falschen Tokenizer.
2. **Eigene Daten statt `load_dataset`.** In Zelle 6 `ds_train` durch unsere `train.jsonl`
   ersetzen (als Kaggle-Datensatz hochladen, `datasets.load_dataset("json", data_files=...)`),
   in Zelle 12 `ds_test` durch `test.jsonl`. Der Rest bleibt, `build_training_item` liest `gold`
   genau so, wie `build_dataset.py` es schreibt.
3. **Rest unverändert:** `train_ddp.py` mit `torchrun --nproc_per_node=2`, 4 Epochen, effektiver
   Stapel 64, Lernrate Encoder 2,5e-5, Kopf 1e-4, fp16, Gradient Checkpointing. Die
   Kalibrierung (je Fragetyp eine Temperatur auf einem vorab abgetrennten Anteil, höchstens 400
   Stück) ist Teil des Laufs und darf nicht fehlen; `temperature_by_options` wird dabei entfernt.
4. Auswerten mit Zelle 12 bis 18 (Genauigkeit, Brier, ECE) auf `test.jsonl`.

Hardware und Dauer laut `docs/finetune.md`: 2x T4 (Kaggle, kostenlos) etwa 4 bis 6 Minuten für
6.000 Entscheidungen, etwa 4 bis 5 Stunden für 4 Epochen über ~30k Fragen. Ein Beispiel mit
einer einzelnen 16-GB-GPU steht in `docs/finetune_browser_agent.md`. Das Notebook braucht CUDA
und NCCL; auf dem Mac (MPS) läuft es so nicht, das ist nicht geprüft.

## 3. Zurück in den Dienst

```
python scripts/export_onnx.py --model <OUTPUT_DIR> --output build/laya/kommandeur/laya.onnx --quantize
```

`scripts/export_onnx.py` (im Laya-Repo, braucht PyTorch) schreibt `laya.onnx` und `laya.int8.onnx` (dynamische
INT8-Quantisierung aller MatMul, je Ausgabekanal). Danach in `build/laya/kommandeur/` ablegen:
`model.onnx` (die INT8-Datei), `tokenizer/` und `rl_agent_config.json` aus `<OUTPUT_DIR>` (mit
den neuen Temperaturen). Start mit `LAYA_MODEL_DIR=build/laya/kommandeur`. Vorher mit
`proben.py` und dem Godot-Test prüfen.

## 4. Abnahme

Laut `docs/KI-LAYA.md` Phase 5: Regel gegen Laya über 50 Partien (`tools/ai_tournament.py`),
Ergebnis in einen Bericht. Auswertung immer auf Partien, die nicht im Training waren.
