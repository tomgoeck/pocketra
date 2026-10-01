// Godot-Android-Plugin "PocketRaPlugin" — lokale Benachrichtigungen ohne FCM.
//
// Toms Wunsch 2026-09-09: "Kann man Benachrichtigungen auch einrichten ohne FCM? Also wenn die App
// im Hintergrund ist und mir jemand im Raum schreibt oder jemand beitritt?" — Ja. Android bringt
// NotificationManager und NotificationChannel mit; ein Push-Dienst ist nur noetig, wenn die App
// gar nicht laeuft. Solange ein Vordergrunddienst laeuft, reicht der eigene Prozess.
//
// Godot friert im Hintergrund die Hauptschleife ein (kein _process, kein WebSocketPeer.poll()).
// Deshalb kann GDScript im Hintergrund nichts melden. Die Arbeit macht darum WatchService: er haelt
// eine eigene, schlanke WebSocket-Verbindung zum Vermittler (`watch{code, token}`,
// docs/MULTIPLAYER.md §3/§10) und macht aus `lobby`, `chat` und `start` Benachrichtigungen.
//
// Seit 2026-09-09 haengt eine **zweite** Aufgabe daran: die Aufnahmequelle fuer den Sprechfunk
// (VoiceInput.kt, docs/MULTIPLAYER.md §11.3). Ein Plugin mit zwei Aufgaben ist billiger als zwei
// Plugins mit je eigener AAR und eigenem Gradle-Bau; seit der Umbenennung auf PocketRA heisst es
// deshalb neutral "PocketRaPlugin" und nicht mehr nach nur einer der beiden Aufgaben.
//
// DER NAME STEHT AN SECHS STELLEN und muss ueberall gleich lauten, sonst laedt Godot das Plugin
// nicht: getPluginName() hier, der Manifest-Schluessel org.godotengine.plugin.v2.PocketRaPlugin
// samt Klassenwert (src/main/AndroidManifest.xml), PLUGIN_NAME/NAME in
// game/addons/pocketra_plugin/export_plugin.gd, SINGLETON in game/scripts/net/net_notify.gd,
// PLUGIN_SINGLETON in game/scripts/net/voice_chat.gd und ANDROID_PLUGIN in
// game/scripts/update/update_config.gd.
//
// Schnittstelle nach GDScript: game/scripts/net/net_notify.gd (Benachrichtigungen),
// game/scripts/net/voice_chat.gd (Aufnahme, `mic*`-Methoden unten) und
// game/scripts/audio_mix.gd (Headset-Erkennung, `isHeadsetConnected()` ganz unten).

package net.pocketra.app.plugin

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot

class PocketRaPlugin(godot: Godot) : GodotPlugin(godot) {

    override fun getPluginName() = "PocketRaPlugin"

    /** Darf die App Benachrichtigungen zeigen? Vor Android 13 immer ja. */
    @UsedByGodot
    fun hasPermission(): Boolean {
        val ctx: Context = activity ?: return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    /**
     * Ab Android 13 muss POST_NOTIFICATIONS erfragt werden. Der Dialog kommt asynchron; der
     * Rueckgabewert sagt nur, ob gefragt wurde. GDScript prueft danach wieder `hasPermission()`.
     */
    @UsedByGodot
    fun requestPermission(): Boolean {
        val act: Activity = activity ?: return false
        if (hasPermission()) return true
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        runOnHostThread {
            act.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFY)
        }
        return true
    }

    /** Eine Benachrichtigung sofort zeigen (App laeuft, steht aber nicht im Vordergrund). */
    @UsedByGodot
    fun showNotification(title: String, text: String) {
        val ctx: Context = activity ?: return
        Notifications.ensureChannels(ctx)
        Notifications.event(ctx, title, text)
    }

    /**
     * Vordergrunddienst starten. Er haengt als Beobachter am Raum: er belegt keinen Platz, haelt
     * aber Raum und Platz beim Vermittler am Leben (server/mp_server.py `on_watch`) und meldet
     * Beitritte, Chatzeilen und den Spielstart.
     *
     * Muss aus dem **Vordergrund** gerufen werden — seit Android 12 darf ein Vordergrunddienst
     * nicht aus dem Hintergrund starten. Die Lobby ruft das genau dann, wenn sie aufgeht.
     */
    @UsedByGodot
    fun startWatch(url: String, code: String, token: String, roomTitle: String, textsJson: String) {
        val ctx: Context = activity ?: return
        val i = Intent(ctx, WatchService::class.java).apply {
            action = WatchService.ACTION_START
            putExtra(WatchService.EXTRA_URL, url)
            putExtra(WatchService.EXTRA_CODE, code)
            putExtra(WatchService.EXTRA_TOKEN, token)
            putExtra(WatchService.EXTRA_ROOM, roomTitle)
            // Anzeigetexte uebersetzt aus GDScript (strings.csv `mp.notify_*`)
            putExtra(WatchService.EXTRA_TEXTS, textsJson)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ctx.startForegroundService(i)
            else ctx.startService(i)
        } catch (e: Exception) {
            // Kein Grund, das Spiel anzuhalten: ohne Dienst gibt es nur keine Benachrichtigungen.
        }
    }

    @UsedByGodot
    fun stopWatch() {
        val ctx: Context = activity ?: return
        try {
            ctx.stopService(Intent(ctx, WatchService::class.java))
        } catch (e: Exception) {
        }
    }

    /**
     * Die App neu starten (Toms Wunsch 2026-09-09: „wenn eine Paketaktualisierung da war, dann muss
     * ich ja die App neu starten, geht das nicht auch per Knopfdruck?").
     *
     * Godot kann das auf Android nicht selbst — `OS.set_restart_on_exit()` wirkt nur auf dem
     * Desktop. Von Android aus geht es ueber den Start-Intent des eigenen Pakets mit
     * NEW_TASK|CLEAR_TASK; danach wird der alte Prozess beendet, damit die Aktualisierung wirklich
     * frisch geladen wird (`UpdateBoot` haengt das Paket vor allen Autoloads ein).
     *
     * Rueckgabe: ob der Neustart angestossen wurde. `false` heisst, GDScript soll beim bisherigen
     * Hinweis bleiben.
     */
    @UsedByGodot
    fun restartApp(): Boolean {
        val ctx: Context = activity ?: return false
        val intent = try {
            ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
        } catch (e: Exception) {
            null
        } ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        runOnHostThread {
            try {
                ctx.startActivity(intent)
            } catch (e: Exception) {
                return@runOnHostThread
            }
            // Kurz warten, damit die neue Activity steht, dann den alten Prozess wegraeumen.
            Handler(Looper.getMainLooper()).postDelayed({
                Process.killProcess(Process.myPid())
            }, 400)
        }
        return true
    }

    // ---------------------------------------------------------------- Sprechfunk-Aufnahme
    //
    // Godots eigener Eingang ist auf Android fest auf 44 100 Hz verdrahtet und liefert auf Geraeten
    // mit 48 000 Hz nur Nullen (docs/MULTIPLAYER.md §11.3). Diese Methoden gehen daran vorbei.

    /** Freigabe fuer die Aufnahme — massgeblich vom System, nicht aus Godots Zwischenspeicher. */
    @UsedByGodot
    fun micHasPermission(): Boolean {
        val ctx: Context = activity ?: return false
        return ctx.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
    }

    /**
     * Die Freigabe kann auch Godot selbst erfragen (`OS.request_permission`), und genau das tut
     * `voice_chat.gd` schon. Diese Fassung gibt es fuer den Fall, dass der Dialog aus dem Plugin
     * kommen soll; sie fragt dieselbe Berechtigung an derselben Activity an.
     */
    @UsedByGodot
    fun micRequestPermission(): Boolean {
        val act: Activity = activity ?: return false
        if (micHasPermission()) return true
        runOnHostThread {
            act.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQ_RECORD)
        }
        return true
    }

    /**
     * Aufnahme starten. Rueckgabe: die Rate, mit der der Recorder **wirklich** laeuft (aus dem
     * AudioRecord zurueckgelesen), 0 bei Fehlschlag — dann faellt GDScript auf Godots Eingang
     * zurueck. Als erste Rate wird die genommen, die das Geraet selbst nennt.
     */
    @UsedByGodot
    fun micStart(): Int {
        if (!micHasPermission()) return 0
        var hint = 0
        try {
            val am = activity?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            hint = am?.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull() ?: 0
        } catch (e: Exception) {
        }
        return VoiceInput.start(hint)
    }

    @UsedByGodot
    fun micStop() = VoiceInput.stop()

    /** Laufende Rate, 0 = Aufnahme laeuft nicht. */
    @UsedByGodot
    fun micRate(): Int = VoiceInput.rate

    /** Wie viele Abtastwerte liegen bereit? */
    @UsedByGodot
    fun micAvailable(): Int = VoiceInput.available()

    /**
     * Bis zu `maxFrames` Abtastwerte als Float (-1…1) abholen — **am Stueck** ueber die
     * JNI-Grenze (`float[]` wird zu `PackedFloat32Array`, s. platform/android/jni_utils.cpp),
     * nicht Wert fuer Wert. Blockiert nicht: der Lesefaden fuellt einen Ringpuffer, hier wird nur
     * daraus abgeschoepft.
     */
    @UsedByGodot
    fun micRead(maxFrames: Int): FloatArray = VoiceInput.read(maxFrames)

    /** Eine Zeile fuer die Mikrofonprobe im Spiel. */
    @UsedByGodot
    fun micInfo(): String = VoiceInput.info()

    // ---------------------------------------------------------------- Headset-Erkennung
    //
    // Toms Handtest 2026-09-11: "Wenn es nicht ueber das Headset laeuft, geht es gar nicht
    // (Spieltoene gehen ins Mikrofon)." Das Spiel senkt die uebrigen Toene deshalb auf ein Viertel,
    // wenn ein Headset angeschlossen ist, und schaltet sie sonst ganz stumm (scripts/audio_mix.gd).
    // Dafuer braucht GDScript eine verlaessliche Antwort — Godot hat keine.
    //
    // AudioManager.getDevices(GET_DEVICES_OUTPUTS) liefert die Liste der wirklich vorhandenen
    // Ausgaenge. Der eingebaute Lautsprecher ist TYPE_BUILTIN_SPEAKER und zaehlt nicht; alles
    // andere in HEADSET_TYPES traegt den Ton ans Ohr und damit vom Mikrofon weg.
    //
    // Ein AudioDeviceCallback haelt die Antwort aktuell, ohne dass GDScript pollen muss: Stecker
    // ziehen oder ein Bluetooth-Hoerer, der waehrend der Partie wegfaellt, kommt so sofort an.
    // Die Liste selbst abzufragen kostet wenig, der Callback spart aber den Weg ueber JNI bei
    // jedem Frame.

    /** Ist gerade ein Kopfhoerer/Headset (Klinke, USB, Bluetooth, BLE) der Ausgang? */
    @UsedByGodot
    fun isHeadsetConnected(): Boolean {
        ensureDeviceCallback()
        val cached = headsetCached
        if (cached != null) return cached
        val now = queryHeadset()
        headsetCached = now
        return now
    }

    private fun queryHeadset(): Boolean {
        val am = try {
            activity?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        } catch (e: Exception) {
            null
        } ?: return false
        return try {
            am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { HEADSET_TYPES.contains(it.type) }
        } catch (e: Exception) {
            false
        }
    }

    /** Einmalig anmelden. Der Callback verwirft nur den Zwischenspeicher, er rechnet nichts. */
    private fun ensureDeviceCallback() {
        if (deviceCallback != null) return
        val am = try {
            activity?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        } catch (e: Exception) {
            null
        } ?: return
        val cb = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>?) {
                headsetCached = null
            }

            override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>?) {
                headsetCached = null
            }
        }
        try {
            am.registerAudioDeviceCallback(cb, Handler(Looper.getMainLooper()))
            deviceCallback = cb
        } catch (e: Exception) {
        }
    }

    private var deviceCallback: AudioDeviceCallback? = null

    @Volatile
    private var headsetCached: Boolean? = null

    companion object {
        const val REQ_NOTIFY = 4711
        const val REQ_RECORD = 4712

        /**
         * Alles, was den Ton ans Ohr statt in den Raum bringt. TYPE_BLE_HEADSET/_SPEAKER gibt es
         * erst ab API 31, TYPE_USB_HEADSET ab 26 — die Konstanten sind aber blosse Ganzzahlen und
         * seit compileSdk 35 alle bekannt, ein Versionstest waere also nur Zierde: auf aelteren
         * Geraeten taucht der Typ schlicht nie in der Liste auf.
         *
         * TYPE_USB_DEVICE steht bewusst NICHT dabei: das ist jedes USB-Audiogeraet, auch ein
         * Lautsprecher an einem Dock. Die falsche Antwort kostet hier eine Rueckkopplung, also
         * ist "kein Headset" im Zweifel die richtige.
         */
        private val HEADSET_TYPES = setOf(
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_HEARING_AID
        )
    }
}
