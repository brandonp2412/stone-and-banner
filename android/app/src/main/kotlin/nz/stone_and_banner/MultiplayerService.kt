package nz.stone_and_banner

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.content.pm.ServiceInfo

/** Keep the authoritative Flutter/WebRTC process scheduled while a match is backgrounded. */
class MultiplayerService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= 26) {
            val notifications = getSystemService(NotificationManager::class.java)
            notifications.createNotificationChannel(
                NotificationChannel("multiplayer", "Multiplayer game", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= 26)
            Notification.Builder(this, "multiplayer") else Notification.Builder(this)
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle("Stone & Banner multiplayer")
            .setContentText("Keeping your live game connected")
            .setOngoing(true)
            .setContentIntent(android.app.PendingIntent.getActivity(
                this, 0, Intent(this, MainActivity::class.java),
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            ))
            .build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(901, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(901, notification)
        }
        wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "stone_and_banner:multiplayer")
            .apply { acquire() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_NOT_STICKY
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }
}
