// Kanaele und Benachrichtigungen. Zwei Kanaele, damit die laufende Dienstmeldung nicht klingelt:
//
//   mp_service  IMPORTANCE_LOW   — "Raum XYZ — verbunden", still, dauerhaft, nicht wegwischbar
//   mp_events   IMPORTANCE_HIGH  — jemand tritt bei, schreibt, die Partie beginnt
//
// Ein Tipp auf jede dieser Meldungen holt die App zurueck in den Vordergrund (Startintent des
// eigenen Pakets); die App landet dort, wo sie war — in der Lobby.

package net.pocketra.app.plugin

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

object Notifications {

    const val CHANNEL_SERVICE = "mp_service"
    const val CHANNEL_EVENTS = "mp_events"
    const val ID_SERVICE = 1001
    private var nextEventId = 1100

    fun ensureChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL_SERVICE) == null) {
            val c = NotificationChannel(CHANNEL_SERVICE, "Mehrspieler-Verbindung",
                NotificationManager.IMPORTANCE_LOW)
            c.description = "Haelt die Verbindung zum Raum, solange du in einer Lobby sitzt."
            c.setShowBadge(false)
            nm.createNotificationChannel(c)
        }
        if (nm.getNotificationChannel(CHANNEL_EVENTS) == null) {
            val c = NotificationChannel(CHANNEL_EVENTS, "Mehrspieler",
                NotificationManager.IMPORTANCE_HIGH)
            c.description = "Jemand tritt dem Raum bei, schreibt im Chat oder startet die Partie."
            nm.createNotificationChannel(c)
        }
    }

    /** Tipp auf die Meldung: die App wieder nach vorn holen (sie steht dann in der Lobby). */
    private fun openApp(ctx: Context): PendingIntent? {
        val i: Intent = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName) ?: return null
        i.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags = flags or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(ctx, 0, i, flags)
    }

    private fun icon(ctx: Context): Int {
        // Godot legt das Startsymbol als `icon` im Ressourcenpaket der App ab; faellt es weg,
        // nimmt Android das Systemsymbol. Ohne gueltiges Symbol zeigt Android gar nichts an.
        val id = ctx.resources.getIdentifier("icon", "mipmap", ctx.packageName)
        if (id != 0) return id
        val id2 = ctx.resources.getIdentifier("icon", "drawable", ctx.packageName)
        return if (id2 != 0) id2 else android.R.drawable.stat_notify_chat
    }

    private fun builder(ctx: Context, channel: String): Notification.Builder {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(ctx, channel)
        else
            @Suppress("DEPRECATION") Notification.Builder(ctx)
    }

    /** Die stille Dauermeldung des Vordergrunddienstes ("Raum XYZ — verbunden"). */
    fun service(ctx: Context, title: String, text: String): Notification {
        ensureChannels(ctx)
        val b = builder(ctx, CHANNEL_SERVICE)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(icon(ctx))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
        openApp(ctx)?.let { b.setContentIntent(it) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            b.setVisibility(Notification.VISIBILITY_PUBLIC)
        }
        return b.build()
    }

    /** Ein Ereignis: Beitritt, Chatzeile, Spielstart. */
    fun event(ctx: Context, title: String, text: String) {
        ensureChannels(ctx)
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        val b = builder(ctx, CHANNEL_EVENTS)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(icon(ctx))
            .setAutoCancel(true)
        openApp(ctx)?.let { b.setContentIntent(it) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            b.setPriority(Notification.PRIORITY_HIGH)
        }
        nextEventId += 1
        try {
            nm.notify(nextEventId, b.build())
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS fehlt (Android 13+) — dann eben still.
        }
    }
}
