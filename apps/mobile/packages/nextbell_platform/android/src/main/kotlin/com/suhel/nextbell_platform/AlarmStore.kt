package com.suhel.nextbell_platform

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** Durable native schedules/actions are usable before Flutter starts. */
internal class AlarmStore(private val context: Context) {
    private val prefs = context.createDeviceProtectedStorageContext().getSharedPreferences("nextbell_alarms", Context.MODE_PRIVATE)
    private val manager = context.getSystemService(AlarmManager::class.java)
    companion object { val lock = Any() }
    private fun json(a: NativeAlarm) = JSONObject().put("id", a.id).put("entryId", a.entryId)
        .put("title", a.title).put("subtitle", a.subtitle).put("fireAt", a.fireAtMillis)
        .put("snooze", a.snoozeMinutes).put("sources", JSONArray(a.sourceIds)).put("parent", a.parentId)
    private fun decode(j: JSONObject): NativeAlarm {
        val ids = j.getJSONArray("sources")
        return NativeAlarm(j.getString("id"), j.getString("entryId"), j.getString("title"), j.getString("subtitle"),
            j.getLong("fireAt"), j.getLong("snooze"), (0 until ids.length()).map { ids.getString(it) },
            if (j.isNull("parent")) null else j.getString("parent"), false)
    }
    fun all(): List<NativeAlarm> = synchronized(lock) {
        prefs.all.filterKeys { it.startsWith("alarm:") }.values.mapNotNull { value ->
            runCatching { decode(JSONObject(value as String)) }.getOrNull()
        }
    }
    fun get(id: String): NativeAlarm? = all().firstOrNull { it.id == id }
    private fun intent(a: NativeAlarm) = PendingIntent.getBroadcast(context, 0,
        Intent(context, AlarmReceiver::class.java).setAction("ring").setData(Uri.parse("nextbell://alarm/${a.id}"))
            .putExtra("id", a.id), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun canSchedule() = Build.VERSION.SDK_INT < 31 || manager.canScheduleExactAlarms()
    fun schedule(a: NativeAlarm) = synchronized(lock) {
        if (prefs.contains("handled:${a.id}")) throw FlutterError("handled", "This reminder was already handled.")
        if (!canSchedule()) throw FlutterError("permission", "Allow alarms and reminders in device settings.")
        if (a.fireAtMillis <= System.currentTimeMillis()) throw FlutterError("expired", "This alarm time has already passed.")
        val show = PendingIntent.getActivity(context, 0,
            Intent(context, AlarmActivity::class.java).setData(Uri.parse("nextbell://show/${a.id}")).putExtra("id", a.id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        // Persist before scheduling; a process death is recoverable at boot/resume.
        val previous = prefs.getString("alarm:${a.id}", null)
        prefs.edit().putString("alarm:${a.id}", json(a).toString()).commit()
        try { manager.setAlarmClock(AlarmManager.AlarmClockInfo(a.fireAtMillis, show), intent(a)) }
        catch (e: Exception) {
            if (previous == null) prefs.edit().remove("alarm:${a.id}").commit()
            else prefs.edit().putString("alarm:${a.id}", previous).commit()
            if (e is IllegalStateException && (e.message?.contains("alarms", ignoreCase = true) == true)) {
                throw FlutterError("capacity", "The device alarm limit has been reached.")
            }
            throw e
        }
    }
    fun cancel(ids: List<String>) = synchronized(lock) {
        ids.forEach { id -> get(id)?.let { manager.cancel(intent(it)) }; prefs.edit().remove("alarm:$id").commit() }
        val active = active().filterNot { ids.contains(it) }
        prefs.edit().putString("active", JSONArray(active).toString()).commit()
        AlarmService.refreshIfRunning(context)
    }
    fun restore(afterBoot: Boolean = false) {
        val now = System.currentTimeMillis()
        val expired = all().filter { it.fireAtMillis <= now && (afterBoot || !active().contains(it.id)) }
        expired.forEach { record(it.parentId ?: it.id, "expired") }
        cancel(expired.map { it.id })
        all().filter { it.fireAtMillis > now }.forEach { runCatching { schedule(it) } }
    }
    fun active(): List<String> = synchronized(lock) {
        val array = JSONArray(prefs.getString("active", "[]")); (0 until array.length()).map { array.getString(it) }
    }
    fun activate(id: String) = synchronized(lock) {
        prefs.edit().putString("active", JSONArray((active() + id).distinct()).toString()).commit()
    }
    fun record(id: String, kind: String) = synchronized(lock) {
        prefs.edit().putLong("handled:$id", System.currentTimeMillis()).commit()
        val array = JSONArray(prefs.getString("actions", "[]"))
        array.put(JSONObject().put("id", UUID.randomUUID().toString()).put("alarmId", id).put("kind", kind)
            .put("at", System.currentTimeMillis()))
        prefs.edit().putString("actions", array.toString()).commit()
    }
    fun actions(): List<NativeAlarmAction> = synchronized(lock) {
        val a = JSONArray(prefs.getString("actions", "[]"))
        (0 until a.length()).map { val j = a.getJSONObject(it)
            NativeAlarmAction(j.getString("id"), j.getString("alarmId"), j.getString("kind"), j.getLong("at")) }
    }
    fun acknowledge(ids: List<String>) = synchronized(lock) {
        val a = JSONArray(prefs.getString("actions", "[]")); val next = JSONArray()
        (0 until a.length()).forEach { if (!ids.contains(a.getJSONObject(it).getString("id"))) next.put(a.getJSONObject(it)) }
        prefs.edit().putString("actions", next.toString()).commit()
    }
    fun handle(id: String, snooze: Boolean) {
        val alarm = get(id) ?: return
        record(alarm.parentId ?: id, if (snooze) "snooze" else "dismiss")
        if (snooze) {
            // Schedule first: if permission was revoked, the current alarm stays actionable.
            schedule(alarm.copy(id = UUID.randomUUID().toString(), parentId = alarm.parentId ?: alarm.id,
                subtitle = "Snoozed reminder", fireAtMillis = System.currentTimeMillis() + alarm.snoozeMinutes * 60_000))
        }
        cancel(listOf(id))
    }
}
