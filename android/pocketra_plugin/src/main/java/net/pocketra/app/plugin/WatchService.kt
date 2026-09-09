// Vordergrunddienst: haelt die Mehrspieler-Lobby am Leben, waehrend die App im Hintergrund ist.
//
// Warum ueberhaupt ein Dienst? Godot haelt im Hintergrund die Hauptschleife an — `_process` laeuft
// nicht mehr, `WebSocketPeer.poll()` bleibt aus, der Vermittler bekommt keine Pong-Rahmen und trennt
// nach rund 40 s. Genau das war Toms Befund am 2026-09-09: "Ich habe einen Raum erstellt, dann in
// WhatsApp geschrieben — danach konnte er den Raum nicht mehr sehen."
//
// Der Dienst haelt deshalb eine **eigene** Verbindung (OkHttp, laeuft in eigenen Threads und ist von
// Godots Schleife unabhaengig) und meldet sich beim Vermittler als Beobachter an:
//
//     -> {"t":"hello","proto":1,"name":"…"}
//     -> {"t":"watch","code":"ABC123","token":"…"}
//     <- {"t":"watching","code":…,"seat":…}   danach lobby / chat / start / peer_left
//
// `watch` belegt keinen Platz (docs/MULTIPLAYER.md §3). Solange der Dienst haengt, verfaellt weder
// der Raum noch der reservierte Platz — und aus den Nachrichten werden Benachrichtigungen.
//
// Vordergrunddiensttyp: `specialUse`. `dataSync` waere inhaltlich naeher, hat seit Android 15 aber
// ein Zeitlimit von 6 h je 24 h; `connectedDevice` meint Hardware. Die App wird nicht ueber Google
// Play verteilt (eigener Server), die Begruendungspflicht des Play-Store entfaellt damit.

package net.pocketra.app.plugin

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class WatchService : Service() {

    private var client: OkHttpClient? = null
    private var socket: WebSocket? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var url = ""
    private var code = ""
    private var token = ""
    private var roomTitle = ""
    /** Anzeigetexte kommen uebersetzt aus GDScript (strings.csv `mp.notify_*`), nicht aus dem Code. */
    private var textConnected = "Raum %s"
    private var textJoin = "%s"
    private var textStart = "Start"
    /**
     * Welche Anlaesse darf der Dienst melden? Kommt als `events` im selben JSON wie die Texte
     * (net_notify.gd `events_flags()`, Optionen -> "Benachrichtigungen"). Fehlt der Schluessel —
     * etwa weil eine aeltere App den Dienst startet —, bleibt es bei "alles melden".
     * Der Hauptschalter steckt nicht hier: steht er auf aus, wird der Dienst gar nicht gestartet.
     */
    private var evJoin = true
    private var evChat = true
    private var evStart = true
    private var seat = -1
    private var started = false
    /** client_id -> Name, um "X ist beigetreten" zu erkennen (dieselbe Regel wie in net_hub.gd). */
    private var known = HashSet<String>()
    private var haveLobby = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null || intent.action != ACTION_START) {
            stopSelf()
            return START_NOT_STICKY
        }
        val wantCode = intent.getStringExtra(EXTRA_CODE) ?: ""
        if (started && wantCode == code && socket != null) {
            // Zweiter Auftrag fuer denselben Raum (z. B. nach einem `resume`) — nichts neu aufbauen.
            return START_STICKY
        }
        url = intent.getStringExtra(EXTRA_URL) ?: ""
        code = wantCode
        token = intent.getStringExtra(EXTRA_TOKEN) ?: ""
        roomTitle = intent.getStringExtra(EXTRA_ROOM) ?: ""
        applyTexts(intent.getStringExtra(EXTRA_TEXTS))
        if (url.isEmpty() || code.isEmpty() || token.isEmpty()) {
            stopSelf()
            return START_NOT_STICKY
        }
        goForeground()
        connect()
        return START_STICKY
    }

    /**
     * {"connected": "Raum %s — verbunden", "join": "%s ist beigetreten", "start": "…",
     *  "events": {"join": true, "chat": true, "start": true}}
     */
    private fun applyTexts(json: String?) {
        if (json.isNullOrEmpty()) return
        try {
            val o = JSONObject(json)
            textConnected = o.optString("connected", textConnected)
            textJoin = o.optString("join", textJoin)
            textStart = o.optString("start", textStart)
            val ev = o.optJSONObject("events")
            if (ev != null) {
                evJoin = ev.optBoolean("join", true)
                evChat = ev.optBoolean("chat", true)
                evStart = ev.optBoolean("start", true)
            }
        } catch (e: Exception) {
        }
    }

    private fun appLabel(): String =
        try { applicationInfo.loadLabel(packageManager).toString() } catch (e: Exception) { "PocketRA" }

    private fun fill(pattern: String, value: String): String =
        if (pattern.contains("%s")) pattern.replace("%s", value) else "$pattern $value"

    private fun goForeground() {
        if (started) return
        started = true
        val n = Notifications.service(this, appLabel(),
            fill(textConnected, roomTitle.ifEmpty { code }))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(Notifications.ID_SERVICE, n,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(Notifications.ID_SERVICE, n)
        }
        // Der Funk darf im Doze-Modus nicht wegschlafen, solange wir auf Mitspieler warten.
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
        wakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "pocketra:mp-watch")
        try {
            wakeLock?.acquire(6 * 60 * 60 * 1000L)
        } catch (e: Exception) {
        }
    }

    private fun connect() {
        val c = OkHttpClient.Builder()
            .pingInterval(20, TimeUnit.SECONDS)          // wie der Vermittler (server/mp_server.py)
            .readTimeout(0, TimeUnit.MILLISECONDS)
            .build()
        client = c
        socket = c.newWebSocket(Request.Builder().url(url.toHttp()).build(), Listener())
    }

    /** `wss://…` / `ws://…` sind fuer OkHttp gleichbedeutend mit `https://` / `http://`. */
    private fun String.toHttp(): String = when {
        startsWith("wss://") -> "https://" + substring(6)
        startsWith("ws://") -> "http://" + substring(5)
        else -> this
    }

    private fun send(o: JSONObject) {
        socket?.send(o.toString())
    }

    private inner class Listener : WebSocketListener() {
        override fun onOpen(ws: WebSocket, response: Response) {
            send(JSONObject().put("t", "hello").put("proto", 1).put("name", roomTitle.ifEmpty { "App" }))
            send(JSONObject().put("t", "watch").put("code", code).put("token", token))
        }

        override fun onMessage(ws: WebSocket, text: String) {
            val d = try { JSONObject(text) } catch (e: Exception) { return }
            when (d.optString("t")) {
                "watching" -> seat = d.optInt("seat", -1)
                "lobby" -> onLobby(d.optJSONArray("clients"))
                "chat" -> onChat(d)
                "start" -> if (evStart) Notifications.event(this@WatchService, roomOrCode(), textStart)
                "error" -> stopSelf()                    // Platz weg, Raum zu: nichts mehr zu halten
            }
        }

        override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
            // Netz weg: in fuenf Sekunden neu versuchen, solange der Dienst laeuft.
            socket = null
            if (started) {
                android.os.Handler(mainLooper).postDelayed({ if (started) connect() }, 5000)
            }
        }

        override fun onClosed(ws: WebSocket, cd: Int, reason: String) = onFailure(ws, Exception(reason), null)
    }

    private fun roomOrCode(): String = roomTitle.ifEmpty { code }

    private fun onLobby(clients: JSONArray?) {
        if (clients == null) return
        val now = HashSet<String>()
        val neu = ArrayList<String>()
        for (i in 0 until clients.length()) {
            val c = clients.optJSONObject(i) ?: continue
            if (c.optBoolean("absent", false)) continue
            val id = c.optString("client_id", "")
            if (id.isEmpty()) continue                   // KI-Plaetze haben keine Verbindung
            now.add(id)
            if (haveLobby && !known.contains(id) && c.optInt("seat", -1) != seat) {
                neu.add(c.optString("name", "?"))
            }
        }
        known = now
        haveLobby = true
        if (!evJoin) return                              // Anlass in den Optionen abgeschaltet
        for (name in neu) {
            Notifications.event(this, roomOrCode(), fill(textJoin, name))
        }
    }

    private fun onChat(d: JSONObject) {
        if (!evChat) return                              // Anlass in den Optionen abgeschaltet
        if (d.optInt("seat", -1) == seat) return         // die eigene Zeile nicht melden
        val text = d.optString("text", "")
        if (text.isEmpty()) return
        Notifications.event(this, d.optString("name", "?"), text)
    }

    override fun onDestroy() {
        started = false
        try { socket?.close(1000, "stop") } catch (e: Exception) {}
        socket = null
        client?.dispatcher?.executorService?.shutdown()
        client = null
        try { if (wakeLock?.isHeld == true) wakeLock?.release() } catch (e: Exception) {}
        wakeLock = null
        super.onDestroy()
    }

    /** Android 15: `dataSync`/`specialUse` koennen ein Zeitlimit bekommen — dann sauber aufhoeren. */
    override fun onTimeout(startId: Int) {
        stopSelf()
    }

    companion object {
        const val ACTION_START = "net.pocketra.app.plugin.START"
        const val EXTRA_URL = "url"
        const val EXTRA_CODE = "code"
        const val EXTRA_TOKEN = "token"
        const val EXTRA_ROOM = "room"
        const val EXTRA_TEXTS = "texts"
    }
}
