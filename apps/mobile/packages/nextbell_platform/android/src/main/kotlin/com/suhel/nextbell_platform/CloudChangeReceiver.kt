package com.suhel.nextbell_platform

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/** Show time-sensitive FCM changes before a Flutter engine has to start. */
class CloudChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.getStringExtra("type") != "urgent_change") return
        val settings = context.getSharedPreferences("nextbell_cloud", Context.MODE_PRIVATE)
        if (!settings.getBoolean("alarmsEnabled", false) || !settings.getBoolean("urgentNotices", false)) return
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel("calendar_changes", "Upcoming meeting changes", NotificationManager.IMPORTANCE_LOW)
        channel.description = "Quiet notices when a meeting with an alarm soon is moved or canceled."
        channel.setSound(null, null)
        manager.createNotificationChannel(channel)
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
        val pending = PendingIntent.getActivity(context, 7410, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        manager.notify(7410, NotificationCompat.Builder(context, channel.id)
            .setSmallIcon(R.drawable.nextbell_alarm_bell)
            .setContentTitle("Your upcoming reminders have changed")
            .setContentText("Nextbell is refreshing your alarms. Open the app to check the latest times.")
            .setContentIntent(pending).setAutoCancel(true).setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE).setSilent(true).build())
    }
}
