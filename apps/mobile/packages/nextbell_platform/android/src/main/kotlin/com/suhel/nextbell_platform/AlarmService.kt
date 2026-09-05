package com.suhel.nextbell_platform

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.*
import androidx.core.app.NotificationCompat

class AlarmService : Service() {
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    companion object {
        private var running = false
        const val CHANNEL = "nextbell_alarms"
        fun refreshIfRunning(context: Context) {
            if (running) context.startService(Intent(context, AlarmService::class.java).setAction("refresh"))
        }
    }
    override fun onBind(intent: Intent?) = null
    override fun onCreate() {
        super.onCreate(); running = true
        val channel = NotificationChannel(CHANNEL, "Alarms", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Meeting and task alarms you enable in Nextbell"
            setSound(null, null); enableVibration(false); lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val store = AlarmStore(this)
        val alarm = store.active().mapNotNull { store.get(it) }.firstOrNull()
        if (alarm == null) { stopSelf(); return START_NOT_STICKY }
        val screen = PendingIntent.getActivity(this, 0,
            Intent(this, AlarmActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .setData(Uri.parse("nextbell://show/${alarm.id}")).putExtra("id", alarm.id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        fun action(name: String) = PendingIntent.getBroadcast(this, 0,
            Intent(this, AlarmReceiver::class.java).setAction(name).setData(Uri.parse("nextbell://$name/${alarm.id}"))
                .putExtra("id", alarm.id), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm).setContentTitle(alarm.title)
            .setContentText(alarm.subtitle).setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX).setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true).setContentIntent(screen).setFullScreenIntent(screen, true)
            .addAction(0, "Snooze ${alarm.snoozeMinutes} min", action("snooze"))
            .addAction(0, "Dismiss", action("dismiss")).build()
        if (Build.VERSION.SDK_INT >= 29) startForeground(7310, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        else startForeground(7310, notification)
        if (player == null) {
            wakeLock = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "nextbell:alarm").apply { acquire(10 * 60_000L) }
            runCatching {
                player = MediaPlayer().apply {
                    setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                    setDataSource(this@AlarmService, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                        ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))
                    isLooping = true; prepare(); start()
                }
            }
            vibrator = if (Build.VERSION.SDK_INT >= 31) getSystemService(VibratorManager::class.java).defaultVibrator
                else @Suppress("DEPRECATION") (getSystemService(Context.VIBRATOR_SERVICE) as Vibrator)
            vibrator?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 500, 600, 500, 1200), 0),
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build())
        }
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        player?.release(); vibrator?.cancel()
        if (wakeLock?.isHeld == true) wakeLock?.release()
        running = false; super.onDestroy()
    }
}
