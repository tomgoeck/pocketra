// Eigene Aufnahmequelle fuer den Sprechfunk (docs/MULTIPLAYER.md §11.3).
//
// Warum an der Engine vorbei: Godots Android-Treiber fordert den Recorder **fest** mit 44 100 Hz an
// (`platform/android/audio_driver_opensl.cpp`: `SL_SAMPLINGRATE_44_1`,
// `get_mix_rate() { return 44100; }` — unveraendert bis in den master-Zweig) und liest
// `audio/driver/mix_rate` gar nicht. Auf Toms Sony Xperia 5 V, das alle Pfade mit 48 000 Hz faehrt,
// nimmt Android nachweislich auf (`appops`: RECORD_AUDIO allow, duration 9,2 s), aber Godots
// `AudioStreamPlaybackMicrophone` mischt nur Nullen auf den Bus. Gemessen am 2026-09-09:
// `≠0 0%` ueber die ganze Messdauer, kein Wort davon im logcat.
//
// AudioRecord dagegen nimmt die **native** Rate des Geraets und ist der Standardweg auf Android.
// Drei Gewinne obendrein:
//   * VOICE_COMMUNICATION statt MIC: das System schaltet Echounterdrueckung und Rauschfilter dazu,
//     genau das, was ein Sprechfunk braucht (MIC liefert das Rohsignal).
//   * keine feste Rate mehr — das Geraet sagt, was es kann.
//   * godotengine/godot#108915 (Aufnahme stirbt nach 5-7 s Stille) faellt weg.
//
// Schnittstelle nach GDScript: `game/scripts/net/voice_chat.gd` holt sich die Bloecke ueber
// `PocketRaPlugin.micRead()` und rechnet sie mit **derselben** Kette weiter wie bisher
// (Herunterrechnen auf 8 kHz, Sprachschleuse, IMA-ADPCM, Versand). Die Sendekette bleibt
// unangetastet — sie ist auf echter Hardware belegt.

package net.pocketra.app.plugin

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor

object VoiceInput {

    /** So viel Ton haelt der Ringpuffer vor; was aelter ist, faellt vorne heraus. */
    private const val RING_SECONDS = 1.0

    /** Reihenfolge der Versuche: erst die Rate, die das Geraet selbst nennt, dann die ueblichen. */
    private val FALLBACK_RATES = intArrayOf(48000, 44100, 32000, 16000, 8000)

    private val lock = Object()

    private var record: AudioRecord? = null
    private var reader: Thread? = null
    @Volatile private var running = false

    private var ring = ShortArray(0)
    private var ringRead = 0
    private var ringWrite = 0
    private var ringFill = 0

    /** Tatsaechlich zustande gekommene Rate (aus dem AudioRecord zurueckgelesen), 0 = laeuft nicht. */
    @Volatile var rate = 0
        private set
    @Volatile var bufferBytes = 0
        private set
    @Volatile var totalFrames = 0L
        private set
    @Volatile var dropped = 0L
        private set
    @Volatile var lastError = ""
        private set
    @Volatile var aecOn = false
        private set
    @Volatile var nsOn = false
        private set

    private var aec: AcousticEchoCanceler? = null
    private var ns: NoiseSuppressor? = null

    fun isRunning(): Boolean = running

    /**
     * Aufnahme starten. `hintRate` ist die Rate, die das Geraet fuer sich selbst nennt
     * (AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE) — 0, wenn unbekannt. Rueckgabe: die Rate, mit der
     * der Recorder wirklich laeuft, 0 bei Fehlschlag.
     */
    fun start(hintRate: Int): Int {
        if (running) return rate
        lastError = ""
        val kandidaten = ArrayList<Int>()
        if (hintRate > 0) kandidaten.add(hintRate)
        for (r in FALLBACK_RATES) if (!kandidaten.contains(r)) kandidaten.add(r)

        for (r in kandidaten) {
            val minBuf = AudioRecord.getMinBufferSize(
                r, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            if (minBuf <= 0) continue
            // Reichlich Puffer: der Leser laeuft in einem eigenen Faden, aber Godot holt nur
            // etwa alle 16 ms ab. Mindestens 200 ms, damit nichts abreisst.
            val bytes = maxOf(minBuf * 4, r / 5 * 2)
            val rec = try {
                AudioRecord(
                    MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                    r, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bytes)
            } catch (e: SecurityException) {
                lastError = "keine RECORD_AUDIO-Freigabe"
                null
            } catch (e: Exception) {
                lastError = "AudioRecord(${r}): ${e.javaClass.simpleName}"
                null
            }
            if (rec == null) continue
            if (rec.state != AudioRecord.STATE_INITIALIZED) {
                lastError = "AudioRecord(${r}) nicht initialisiert"
                rec.release()
                continue
            }
            // **Zurueckgelesen**, nicht angenommen: manche Geraete liefern eine andere Rate.
            rate = if (rec.sampleRate > 0) rec.sampleRate else r
            bufferBytes = bytes
            record = rec
            _startEffects(rec.audioSessionId)
            synchronized(lock) {
                ring = ShortArray(maxOf((rate * RING_SECONDS).toInt(), 8192))
                ringRead = 0
                ringWrite = 0
                ringFill = 0
            }
            totalFrames = 0
            dropped = 0
            try {
                rec.startRecording()
            } catch (e: Exception) {
                lastError = "startRecording: ${e.javaClass.simpleName}"
                stop()
                return 0
            }
            if (rec.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                lastError = "RecordState ${rec.recordingState}"
                stop()
                return 0
            }
            running = true
            val chunk = maxOf(bytes / 4, 512)
            reader = Thread({ _readLoop(chunk) }, "PocketRaVoiceIn").apply {
                priority = Thread.NORM_PRIORITY + 1
                isDaemon = true
                start()
            }
            return rate
        }
        if (lastError.isEmpty()) lastError = "keine brauchbare Abtastrate"
        return 0
    }

    fun stop() {
        running = false
        reader?.let { try { it.join(300) } catch (e: InterruptedException) { } }
        reader = null
        _stopEffects()
        record?.let {
            try { if (it.recordingState == AudioRecord.RECORDSTATE_RECORDING) it.stop() } catch (e: Exception) { }
            try { it.release() } catch (e: Exception) { }
        }
        record = null
        rate = 0
        synchronized(lock) {
            ringRead = 0
            ringWrite = 0
            ringFill = 0
        }
    }

    /** Wie viele Abtastwerte liegen bereit? */
    fun available(): Int = synchronized(lock) { ringFill }

    /**
     * Bis zu `maxFrames` Abtastwerte als Float (-1…1) abholen und aus dem Ring nehmen.
     * Laeuft im Godot-Faden und haelt den Sperrbereich so kurz wie moeglich — kein Blockieren.
     */
    fun read(maxFrames: Int): FloatArray {
        synchronized(lock) {
            val n = minOf(maxFrames, ringFill)
            if (n <= 0) return FloatArray(0)
            val out = FloatArray(n)
            var r = ringRead
            for (i in 0 until n) {
                out[i] = ring[r] / 32768.0f
                r++
                if (r >= ring.size) r = 0
            }
            ringRead = r
            ringFill -= n
            return out
        }
    }

    /** Eine Zeile fuer die Mikrofonprobe im Spiel (Tom hat unterwegs kein adb). */
    fun info(): String {
        val fehler = if (lastError.isEmpty()) "" else " · Fehler: $lastError"
        return "AudioRecord ${rate} Hz · Puffer ${bufferBytes} B · ${totalFrames} F" +
            (if (aecOn) " · AEC" else "") + (if (nsOn) " · NS" else "") +
            (if (dropped > 0) " · verworfen $dropped" else "") + fehler
    }

    // ---------------------------------------------------------------- innen

    private fun _readLoop(chunk: Int) {
        val buf = ShortArray(chunk)
        while (running) {
            val rec = record ?: break
            val n = try {
                rec.read(buf, 0, buf.size)
            } catch (e: Exception) {
                lastError = "read: ${e.javaClass.simpleName}"
                break
            }
            if (n <= 0) {
                if (n < 0) lastError = "read gab $n zurueck"
                // Kein Busy-Loop, falls der Recorder gerade nichts liefert.
                try { Thread.sleep(5) } catch (e: InterruptedException) { break }
                continue
            }
            totalFrames += n
            synchronized(lock) {
                if (ring.isEmpty()) return@synchronized
                for (i in 0 until n) {
                    ring[ringWrite] = buf[i]
                    ringWrite++
                    if (ringWrite >= ring.size) ringWrite = 0
                    if (ringFill < ring.size) {
                        ringFill++
                    } else {
                        // Ring voll: der aelteste Abtastwert faellt heraus (Godot holt zu langsam).
                        dropped++
                        ringRead++
                        if (ringRead >= ring.size) ringRead = 0
                    }
                }
            }
        }
    }

    /**
     * Echounterdrueckung und Rauschfilter, sofern das Geraet sie mitbringt. VOICE_COMMUNICATION
     * schaltet sie ueblicherweise schon zu; ausdruecklich einzuschalten schadet nicht und macht es
     * auf Geraeten sichtbar, die es nicht von selbst tun.
     */
    private fun _startEffects(sessionId: Int) {
        aecOn = false
        nsOn = false
        try {
            if (AcousticEchoCanceler.isAvailable()) {
                aec = AcousticEchoCanceler.create(sessionId)?.also { it.enabled = true }
                aecOn = aec?.enabled == true
            }
        } catch (e: Exception) { }
        try {
            if (NoiseSuppressor.isAvailable()) {
                ns = NoiseSuppressor.create(sessionId)?.also { it.enabled = true }
                nsOn = ns?.enabled == true
            }
        } catch (e: Exception) { }
    }

    private fun _stopEffects() {
        try { aec?.release() } catch (e: Exception) { }
        try { ns?.release() } catch (e: Exception) { }
        aec = null
        ns = null
        aecOn = false
        nsOn = false
    }
}
