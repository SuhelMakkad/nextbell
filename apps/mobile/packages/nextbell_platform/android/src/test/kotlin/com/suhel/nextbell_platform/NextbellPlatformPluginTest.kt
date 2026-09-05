package com.suhel.nextbell_platform

import android.content.Context
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class NextbellPlatformPluginTest {
    private lateinit var context: Context
    @Before fun prepare() {
        context = RuntimeEnvironment.getApplication()
        context.createDeviceProtectedStorageContext().getSharedPreferences("nextbell_alarms", Context.MODE_PRIVATE).edit().clear().commit()
    }
    private fun alarm(id: String = "future") = NativeAlarm(id, "event", "Meeting", "Soon",
        System.currentTimeMillis() + 600_000, 5, listOf("shared-calendar"), null, false)
    @Test fun schedulesAndActionsSurviveStoreRecreation() {
        val first = AlarmStore(context); first.schedule(alarm()); first.record("future", "dismiss")
        val restored = AlarmStore(context)
        assertEquals("Meeting", restored.get("future")?.title)
        assertEquals(listOf("shared-calendar"), restored.get("future")?.sourceIds)
        assertEquals("dismiss", restored.actions().single().kind)
        restored.acknowledge(restored.actions().map { it.id })
        assertTrue(AlarmStore(context).actions().isEmpty())
    }
    @Test fun snoozeReplacesOnlyCurrentAlarmAndRetainsNextReminder() {
        val store = AlarmStore(context); store.schedule(alarm("first")); store.schedule(alarm("second"))
        store.handle("first", true)
        assertNull(store.get("first")); assertNotNull(store.get("second"))
        assertEquals("first", store.all().single { it.parentId != null }.parentId)
        assertEquals("snooze", store.actions().single().kind)
        assertEquals(2, store.all().size)
    }
    @Test fun dismissDoesNotRemoveSubsequentReminder() {
        val store = AlarmStore(context); store.schedule(alarm("first")); store.schedule(alarm("second"))
        store.handle("first", false)
        assertEquals(listOf("second"), store.all().map { it.id })
        assertEquals("dismiss", store.actions().single().kind)
    }
    @Test fun expiredAlarmCannotCreateBacklog() {
        val store = AlarmStore(context)
        try { store.schedule(alarm().copy(fireAtMillis = 1)); fail("Expired alarm accepted") }
        catch (error: FlutterError) { assertEquals("expired", error.code) }
        assertTrue(store.all().isEmpty())
    }
}
