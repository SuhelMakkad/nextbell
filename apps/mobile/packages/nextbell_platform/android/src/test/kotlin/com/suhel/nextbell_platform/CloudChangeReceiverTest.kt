package com.suhel.nextbell_platform

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class CloudChangeReceiverTest {
    private lateinit var context: Context
    private lateinit var manager: NotificationManager
    @Before fun prepare() {
        context = RuntimeEnvironment.getApplication()
        manager = context.getSystemService(NotificationManager::class.java)
        manager.cancelAll()
        context.getSharedPreferences("nextbell_cloud", Context.MODE_PRIVATE).edit().clear().commit()
    }
    @Test fun unconfiguredPhoneNeverShowsUrgentNotices() {
        CloudChangeReceiver().onReceive(context, Intent().putExtra("type", "urgent_change"))
        assertTrue(manager.activeNotifications.isEmpty())
        assertNull(manager.getNotificationChannel("calendar_changes"))
    }
    @Test fun routinePushDoesNotCreateNotificationChannel() {
        context.getSharedPreferences("nextbell_cloud", Context.MODE_PRIVATE).edit()
            .putBoolean("alarmsEnabled", true).putBoolean("urgentNotices", true).commit()
        CloudChangeReceiver().onReceive(context, Intent().putExtra("type", "sync"))
        assertTrue(manager.activeNotifications.isEmpty())
        assertNull(manager.getNotificationChannel("calendar_changes"))
    }
    @Test fun enabledUrgentChannelIsQuietAndLowImportance() {
        context.getSharedPreferences("nextbell_cloud", Context.MODE_PRIVATE).edit()
            .putBoolean("alarmsEnabled", true).putBoolean("urgentNotices", true).commit()
        CloudChangeReceiver().onReceive(context, Intent().putExtra("type", "urgent_change"))
        val channel = manager.getNotificationChannel("calendar_changes")
        assertNotNull(channel)
        assertNull(channel.sound)
        assertEquals(NotificationManager.IMPORTANCE_LOW, channel.importance)
    }
}
