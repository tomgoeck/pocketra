# Aktualisierungspaket auf iOS — Apples Richtlinie 2.5.2

**Stand 2026-09-09. Umgesetzt ist: auf iOS aus, überall sonst an. Der Schalter liegt bereit, die
Entscheidung liegt bei Tom.**

Auf Android und Windows ist unser Aktualisierungspaket (`update.pck`, s. README „Aktualisierung")
der ganze Sinn der Übung: Freunde bekommen Änderungen beim nächsten App-Start, ohne eine neue APK zu
installieren. Auf iPhone und iPad ist derselbe Mechanismus ein Prüfrisiko. Dieses Papier sagt warum,
wie groß es ist, welche Wege es gibt und was eingebaut ist.

## 1. Was in dem Paket steckt

`tools/update_pack.sh` exportiert das Preset „Update-Paket" bzw. „… schlank". Drin sind
**Skripte** (GDScript, als `.gdc`/Ressourcen), Szenen, `assets/maps` und `data/**` —
ausdrücklich **nicht** die native Extension (`bin/**`, die wechselt nur mit der App). Der
weitaus größte Teil dessen, was ein Paket ändert, ist also Programmlogik: Regeln, HUD, KI,
Menüführung. Genau deshalb ist es so nützlich — und genau deshalb ist es der Fall, den Apple meint.

## 2. Der Wortlaut

**App Review Guidelines, 2.5.2** (abgerufen 2026-09-09,
<https://developer.apple.com/app-store/review/guidelines/>):

> Apps should be self-contained in their bundles, and may not read or write data outside the
> designated container area, nor may they **download, install, or execute code which introduces or
> changes features or functionality of the app**, including other apps. Educational apps designed to
> teach, develop, or allow students to test executable code may, in limited circumstances, download
> code provided that such code is not used for other purposes. Such apps must make the source code
> provided by the app completely viewable and editable by the user.

Zwei Irrtümer, die man dazu oft liest, und die wir nicht wiederholen sollten:

* **Die „WebKit/JavaScriptCore-Ausnahme" steht nicht in den Guidelines.** Auf der
  Guidelines-Seite kommen `JavaScriptCore`, `interpreted code`, `primary purpose` und
  `advertised purpose` **gar nicht vor**; `WebKit` nur in 2.5.6 (Browser-Engines). Die bekannte
  Klausel stammt aus dem **Apple Developer Program License Agreement, §3.3.2** — einem anderen
  Vertrag — und wurde im Juni 2017 entschärft.
* **Interpretierter Code ist im ADPLA nicht pauschal verboten.** Die dortige Fassung lautet
  sinngemäß: eine App darf keinen *ausführbaren* Code nachladen; *interpretierter* Code darf
  nachgeladen werden, solange er (a) nicht den *primary purpose* der App ändert und keine
  Funktionen bringt, die mit dem bei der Einreichung angegebenen Zweck unvereinbar sind, (b) keinen
  Laden für weiteren Code aufmacht und (c) Signierung/Sandkasten nicht umgeht.

  *Einschränkung, ehrlich gesagt:* dieser §3.3.2-Wortlaut ist über eine SEC-Archivfassung des ADPLA
  belegt, nicht über die Live-Seite (die ließ sich nicht zuverlässig auslesen). Für eine belastbare
  Auslegung gehört die im Entwicklerkonto hinterlegte PDF gegengelesen.

**Nach diesen beiden Texten zusammen** ist unser Paket ein **Grenzfall, kein klarer Verstoß**: Es
ist interpretierter Code (GDScript), es macht keinen Laden auf, es umgeht nichts, und ein
Balancing- oder HUD-Patch für dasselbe Echtzeitstrategiespiel ändert dessen *primary purpose*
nicht. Der strengere Guidelines-Satz („introduces or changes **features or functionality**")
verbietet allerdings genau das, was ein Paket tut, sobald es mehr ist als Zahlen.

## 3. Warum das Risiko trotzdem real ist: der Prüfer kann nicht hineinsehen

Der praktisch belegte Ablehnungsgrund ist nicht die Rechtsfrage, sondern die **Undurchsichtigkeit**.
Ein `.pck` ist für den Prüfer eine Blackbox — wie ein Unity-AssetBundle. Dokumentierter Fall aus dem
Unity-Forum: eine App wurde unter ausdrücklicher Nennung von 2.5.2 abgelehnt, obwohl das Bundle nur
Mediendaten enthielt; Apples Begründung war, man sei *„unable to confirm that the downloaded assets
are strictly game media files"*, verbunden mit der Empfehlung, alles ins Binary zu backen.
(<https://discussions.unity.com/questions/1588614/downloading-asset-bundle-leads-to-app-rejection-by.html>)

Zu **Godot-`.pck` im App Store** ließ sich weder ein Ablehnungs- noch ein Freigabefall finden. Das
ist keine Entwarnung, sondern eine Lücke — es heißt nur, dass niemand öffentlich darüber geschrieben
hat.

## 4. TestFlight ist kein Freibrief

Apple macht im Text **keinen** Unterschied zwischen TestFlight und Store; die Guidelines gelten für
beides. In der Praxis ist die Beta App Review deutlich oberflächlicher und schaut auf Abstürze und
Inhalte, nicht auf Architektur. Die verbreitete Erfahrung lautet: *„Getting through TestFlight review
has no bearing on getting through the eventual App Store review."*
(<https://christianselig.com/2020/06/testflight-review/>) Dazu kommt: **interne** Tester (bis 100
Mitglieder des eigenen Teams) bekommen einen Build ganz **ohne** Beta App Review — der heutige
PocketRA-Weg läuft also an jeder Prüfung vorbei.

Praktische Folge: Das Paket würde auf Toms iPad und bei internen Testern still funktionieren und
erst dann auffallen, wenn PocketRA je an externe Tester oder in den Store geht. Das ist der
unangenehmste Fehlerzeitpunkt — spät, und dann steckt viel Arbeit im Mechanismus.

*Einschränkung:* ein dokumentierter Fall, in dem 2.5.2 **im TestFlight-Review** ausgelöst hat, ließ
sich nicht finden.

## 5. Wo die Grenze zwischen Daten und Code verläuft

Nach Wortlaut verbietet 2.5.2 nur **Code**. Bilder, Kartengeometrie, Übersetzungstexte und
Balancing-Tabellen sind keine. Apple bietet mit On-Demand Resources und dem Background-Assets-Framework
selbst offizielle Wege, große Datenmengen nachzuladen — Daten können also nicht gemeint sein.

Entscheidend ist nicht die Dateiendung, sondern **was die App damit tut**: Eine JSON-Tabelle, die
unsere Sim als Zahlen liest, ist Daten. Eine JSON-Datei, deren Inhalt wir an einen Interpreter
reichen, ist Code — auch wenn sie `.json` heißt. Für uns heißt das konkret:

| Inhalt eines Pakets | Einordnung |
|---|---|
| `data/rules.json`, `data/*.json` (Regeln, Balance) | **Daten** — unbedenklich |
| `assets/maps/**` (Karten) | **Daten** — unbedenklich |
| `i18n/*.translation` (Übersetzungen) | **Daten** — unbedenklich |
| `scripts/**`, `scenes/**` (GDScript, Szenen) | **Code** — das ist der Streitpunkt |

Der ganze Streit hängt also an genau einer Zeile im Preset: ob `scripts/` und `scenes/` mit ins
Paket gehen.

## 6. Die drei Wege

**A. Paket auf iOS ganz aus, alles über TestFlight/Xcode.** *(umgesetzt, Vorgabe)*
Kein Risiko, keine Arbeit, kein Zweifelsfall. Preis: jede Änderung braucht einen Xcode-Lauf und
einen neuen Build; iOS-Nutzer hinken hinterher. Bei heute genau einem iPad ist das kein Preis.

**B. Nur Daten nachladen, Skripte nie.** *(der interessante Mittelweg, nicht umgesetzt)*
Ein zweites Preset „Update-Paket iOS" ohne `scripts/**` und `scenes/**`, ein zweites Feld
`pack_url_ios` in `version.json`, und `min_extension` bekommt einen Zwilling für die
Datenformat-Version. Damit bekämen iOS-Geräte weiterhin Karten, Regeln und Übersetzungen. Das ist
nach Wortlaut sauber — es lädt keinen Code — und würde auch einer Rückfrage standhalten, weil sich
der Inhalt benennen lässt. Der Aufwand ist nicht klein: die Sim muss dann damit rechnen, dass Daten
neuer sein können als der Code, der sie liest. Solange PocketRA nicht in den Store soll, lohnt das
nicht.

**C. Alles lassen wie auf Android.** Nur vertretbar, solange die App den Store nie sieht und nur an
interne Tester geht. Wer diesen Weg wählt, sollte es bewusst tun und wissen, dass die spätere
Store-Einreichung dann eine Umbauarbeit ist, keine Formsache.

## 7. Empfehlung

**Weg A, so wie es jetzt eingebaut ist — und Weg B erst dann, wenn PocketRA wirklich in den Store
soll.** Begründung in drei Sätzen:

1. Der Nutzen des Pakets auf iOS ist heute **null**: es gibt genau ein iPad, und das steht auf Toms
   Schreibtisch neben dem Mac, der die IPA baut. Das Paket löst dort kein Problem.
2. Das Risiko ist zwar unwahrscheinlich, aber **teuer und spät** — es schlägt genau in dem Moment
   zu, in dem man die App zum ersten Mal wirklich veröffentlichen will.
3. Der Schalter kostet nichts und ist reversibel: fällt die Entscheidung anders, sind es zwei
   Zeilen in `user://settings.cfg`.

Was **nicht** empfehlenswert ist: das Paket auf iOS laufen zu lassen und darauf zu hoffen, dass
TestFlight es durchwinkt. Es wird es durchwinken — das ist ja gerade das Problem.

## 8. Wie der Schalter umgesetzt ist

Die Vorgabe steht an **einer** Stelle als Konstante: `UpdateConfig.PACK_DEFAULT_OFF_ON_IOS`.

| Ort | Wirkung |
|---|---|
| `UpdateConfig.pack_enabled()` (`game/scripts/update/update_config.gd`) | entscheidet, ob **geladen** wird |
| `UpdateBoot._pack_enabled()` (`game/scripts/update/update_boot.gd`) | entscheidet, ob ein schon vorhandenes `current.pck` **eingehängt** wird |

Beide müssen dieselbe Antwort geben; die Verdopplung ist Absicht und aus demselben Grund nötig wie
bei `cmp_version()` — der Bootstrap darf keine andere Skriptdatei anfassen, sonst läge sie im
Ressourcen-Cache und wäre selbst nicht mehr durch ein Paket ersetzbar (Kopf von `update_boot.gd`).

Reihenfolge beider Funktionen:

1. Kommandozeile `-- --update-pack on|off` (Prüfläufe),
2. `user://settings.cfg`, Abschnitt `[update]`, Schlüssel `pack` (dauerhaft, je Gerät),
3. Vorgabe: überall an, auf iOS aus.

```ini
# ~/…/pocketra/settings.cfg  bzw. auf dem Gerät im Dokumente-Ordner der App
[update]
pack=true
```

**Wichtig — was NICHT abgeschaltet ist:** Die App fragt `version.json` auf iOS weiter ab. Der
Notschalter `disabled`, die Sperre über `min_supported`/`min_supported_pack` und der Hinweis auf eine
neue Fassung wirken also unverändert auch auf dem iPad; nur das Nachladen selbst unterbleibt. Die
Reihenfolge in `UpdateService._handle_version()` ist genau deswegen so gebaut (Schritt 1 und 2 stehen
über der Abfrage, Schritt 2a).

Am Mac nachstellbar, ohne ein Gerät:

```bash
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --path game res://scenes/main_menu.tscn --quit-after 20000 -- --page main --lang de \
   --force-platform iOS --update-url http://127.0.0.1:8123/version.json --test-update
#   erwartet: „Ergebnis pack_off", „angeboten nichts", „Paket erlaubt: false"
#   und die Zeile „Plattformweichen: 0 Fehlschläge"
```

## 9. Quellen

* App Review Guidelines 2.5.2 / 2.5.6 / 4.7 — <https://developer.apple.com/app-store/review/guidelines/>
* ADPLA §3.3.2, SEC-Archivfassung — <https://www.sec.gov/Archives/edgar/data/1581760/000119312522172365/d328928dex1036.htm>
* Ablehnung eines Unity-AssetBundles unter 2.5.2 — <https://discussions.unity.com/questions/1588614/downloading-asset-bundle-leads-to-app-rejection-by.html>
* TestFlight-Review gegen Store-Review — <https://christianselig.com/2020/06/testflight-review/>
* Einordnung „Daten gegen Code" — <https://ptkd.com/journal/guideline-2-5-2-downloading-scripts-without-review>
* Apple lockert die ADPLA-Klausel (2017) — <https://www.theregister.com/2017/06/07/apple_relaxes_developer_rules/>
