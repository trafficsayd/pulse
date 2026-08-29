package io.pulseapp.pulse

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

private const val CONNECTION_CHANNEL = "pulse_connection"
private const val CONNECTION_NOTIFICATION_ID = 7318

/**
 * Keeps the paired transport process in Android's foreground-service class
 * while a close-person connection is active. The encrypted socket and
 * Flutter engine remain owned by the app; this service only supplies the
 * lifecycle priority Android requires for lock-screen communication.
 */
class PulseConnectionService : Service() {
    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CONNECTION_CHANNEL,
                    "Pulse connection",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Keeps the encrypted connection with your close person available"
                    setShowBadge(false)
                    lockscreenVisibility = Notification.VISIBILITY_SECRET
                },
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CONNECTION_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_pulse_notification)
            .setContentTitle("Pulse")
            .setContentText("Secure connection is active")
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                CONNECTION_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } else {
            startForeground(CONNECTION_NOTIFICATION_ID, notification)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int =
        START_STICKY

    override fun onBind(intent: Intent?): IBinder? = null
}
