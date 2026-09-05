package com.suhel.nextbell_platform

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val store = AlarmStore(context)
        val id = intent.getStringExtra("id") ?: return
        when (intent.action) {
            "ring" -> {
                if (store.get(id) == null) return
                store.activate(id)
                store.record(id, "fired")
                ContextCompat.startForegroundService(context, Intent(context, AlarmService::class.java))
            }
            "snooze", "dismiss" -> runCatching { store.handle(id, intent.action == "snooze") }
        }
    }
}
class RestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED,
            "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED")) {
            AlarmStore(context).restore(afterBoot = intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_LOCKED_BOOT_COMPLETED)
        }
    }
}
