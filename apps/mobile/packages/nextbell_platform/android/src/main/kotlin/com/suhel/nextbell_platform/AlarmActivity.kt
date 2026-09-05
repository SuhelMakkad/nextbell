package com.suhel.nextbell_platform

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.graphics.Color
import android.view.Gravity
import android.view.WindowManager
import android.widget.*

/** Actions are native so they work without starting a Flutter engine. */
class AlarmActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 27) { setShowWhenLocked(true); setTurnScreenOn(true) }
        else @Suppress("DEPRECATION") window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        render()
    }
    override fun onNewIntent(intent: android.content.Intent) { super.onNewIntent(intent); setIntent(intent); render() }
    private fun render() {
        val store = AlarmStore(this)
        val alarm = store.get(intent.getStringExtra("id") ?: "") ?: store.active().mapNotNull { store.get(it) }.firstOrNull()
        if (alarm == null) { finish(); return }
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER; setPadding(40, 64, 40, 64)
            setBackgroundColor(Color.rgb(23, 22, 43))
        }
        fun label(value: String, size: Float, color: Int) = TextView(this).apply {
            text = value; textSize = size; setTextColor(color); gravity = Gravity.CENTER; setPadding(0, 16, 0, 16)
        }
        layout.addView(label("NEXTBELL", 16f, Color.rgb(190, 183, 255)))
        layout.addView(label(alarm.title, 32f, Color.WHITE))
        layout.addView(label(alarm.subtitle, 18f, Color.LTGRAY))
        for ((text, snooze) in listOf("Snooze ${alarm.snoozeMinutes} minutes" to true, "Dismiss" to false)) {
            layout.addView(Button(this).apply {
                this.text = text; textSize = 18f; minHeight = 64
                setOnClickListener {
                    runCatching { store.handle(alarm.id, snooze) }.onSuccess { finish() }
                        .onFailure { Toast.makeText(this@AlarmActivity, "Check alarm access in Settings", Toast.LENGTH_LONG).show() }
                }
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        }
        val scroll = ScrollView(this).apply { isFillViewport = true; addView(layout) }
        setContentView(scroll)
    }
}
