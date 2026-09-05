package com.suhel.nextbell_platform

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.StateListAnimator
import android.animation.ValueAnimator
import android.app.Activity
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import kotlin.math.roundToInt

/** Presentation and actions stay native, including before a Flutter engine starts. */
class AlarmActivity : Activity() {
    private var bellMotion: ObjectAnimator? = null
    private val manrope by lazy {
        // Read the app's bundled font directly; this does not start Flutter.
        runCatching { Typeface.createFromAsset(assets, "flutter_assets/assets/fonts/Manrope.ttf") }
            .getOrElse { Typeface.create("sans-serif", Typeface.NORMAL) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = false
        }
        render()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        render()
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).roundToInt()
    private fun color(id: Int) = getColor(id)
    private fun shape(fill: Int, radius: Int, stroke: Int? = null) = GradientDrawable().apply {
        setColor(fill)
        cornerRadius = dp(radius).toFloat()
        stroke?.let { setStroke(dp(1), it) }
    }

    private fun label(value: String, size: Float, textColor: Int, weight: Int = 400) = TextView(this).apply {
        text = value
        textSize = size
        setTextColor(textColor)
        gravity = Gravity.CENTER
        includeFontPadding = false
        typeface = if (Build.VERSION.SDK_INT >= 28) Typeface.create(manrope, weight, false)
            else Typeface.create(manrope, if (weight >= 600) Typeface.BOLD else Typeface.NORMAL)
        fontVariationSettings = "'wght' $weight"
        setLineSpacing(dp(3).toFloat(), 1f)
    }

    private fun actionButton(value: String, primary: Boolean, action: () -> Unit) = Button(this).apply {
        text = value
        isAllCaps = false
        textSize = 16f
        typeface = if (Build.VERSION.SDK_INT >= 28) Typeface.create(manrope, 600, false)
            else Typeface.create(manrope, Typeface.BOLD)
        fontVariationSettings = "'wght' 600"
        setTextColor(color(R.color.nextbell_alarm_ink))
        minHeight = dp(56)
        minimumHeight = dp(56)
        setPadding(dp(20), dp(16), dp(20), dp(16))
        backgroundTintList = null
        background = RippleDrawable(
            ColorStateList.valueOf(Color.argb(35, 255, 255, 255)),
            shape(
                color(if (primary) R.color.nextbell_indigo else R.color.nextbell_alarm_card),
                18,
                if (primary) null else color(R.color.nextbell_alarm_outline),
            ),
            shape(Color.WHITE, 18),
        )
        elevation = 0f
        val target = this
        // The system's Remove animations preference also disables press movement.
        stateListAnimator = if (ValueAnimator.areAnimatorsEnabled()) StateListAnimator().apply {
            fun scale(to: Float) = AnimatorSet().apply {
                playTogether(ObjectAnimator.ofFloat(target, View.SCALE_X, to),
                    ObjectAnimator.ofFloat(target, View.SCALE_Y, to))
                duration = 160
                interpolator = DecelerateInterpolator()
            }
            addState(intArrayOf(android.R.attr.state_pressed), scale(.98f))
            addState(intArrayOf(), scale(1f))
        } else null
        setOnClickListener { action() }
    }

    private fun render() {
        bellMotion?.cancel()
        val store = AlarmStore(this)
        val alarm = store.get(intent.getStringExtra("id") ?: "")
            ?: store.active().mapNotNull { store.get(it) }.firstOrNull()
        if (alarm == null) { finish(); return }

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
        }
        fun add(view: View, gap: Int) {
            content.addView(view, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { bottomMargin = dp(gap) })
        }
        add(label("nextbell", 22f, color(R.color.nextbell_alarm_ink), 800), 36)
        val bell = ImageView(this).apply {
            setImageResource(R.drawable.nextbell_alarm_bell)
            setPadding(dp(23), dp(23), dp(23), dp(23))
            background = shape(color(R.color.nextbell_indigo), 32)
            rotation = -7f
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        content.addView(bell, LinearLayout.LayoutParams(dp(96), dp(96)).apply { bottomMargin = dp(28) })
        add(label(getString(R.string.nextbell_alarm_heading), 12f, color(R.color.nextbell_alarm_mint), 600).apply {
            letterSpacing = .08f
        }, 12)
        add(label(alarm.title, 34f, color(R.color.nextbell_alarm_ink), 700).apply {
            ViewCompat.setAccessibilityHeading(this, true)
        }, 16)
        add(label(alarm.subtitle, 15f, color(R.color.nextbell_alarm_muted)), 36)

        fun handle(snooze: Boolean) {
            runCatching { store.handle(alarm.id, snooze) }
                .onSuccess { finish() }
                .onFailure { Toast.makeText(this, R.string.nextbell_alarm_access_error, Toast.LENGTH_LONG).show() }
        }
        add(actionButton(getString(R.string.nextbell_alarm_snooze, alarm.snoozeMinutes), true) { handle(true) }, 12)
        add(actionButton(getString(R.string.nextbell_alarm_dismiss), false) { handle(false) }, 20)
        add(label(getString(R.string.nextbell_alarm_dismiss_hint), 12f, color(R.color.nextbell_alarm_muted)), 0)

        val viewport = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            // A readable width on tablets, with natural wrapping at large text sizes.
            val width = dp((resources.configuration.screenWidthDp - 48).coerceIn(1, 480))
            addView(content, LinearLayout.LayoutParams(width, LinearLayout.LayoutParams.WRAP_CONTENT))
        }
        val scroll = ScrollView(this).apply {
            isFillViewport = true
            clipToPadding = false
            setBackgroundColor(color(R.color.nextbell_alarm_surface))
            addView(viewport)
        }
        ViewCompat.setOnApplyWindowInsetsListener(scroll) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            view.setPadding(bars.left, bars.top + dp(24), bars.right, bars.bottom + dp(24))
            insets
        }
        setContentView(scroll)
        ViewCompat.requestApplyInsets(scroll)
        // One short bell gesture. Audio and buttons never wait for animation.
        if (ValueAnimator.areAnimatorsEnabled()) {
            bellMotion = ObjectAnimator.ofFloat(bell, View.ROTATION, -7f, 5f, -11f, -7f).apply {
                duration = 320
                start()
            }
        }
    }

    override fun onDestroy() {
        bellMotion?.cancel()
        super.onDestroy()
    }
}
