package com.example.fa_ksiegowy

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import android.view.FrameMetrics
import android.view.Window
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Уровень "визуальной нагрузки" приложения.
 *
 *  FULL    — всё как задумано: живой фон (30 fps) + размытие под системными панелями.
 *  LITE    — фон реже (20 fps) и с меньшим числом точек, размытие остаётся.
 *  MINIMAL — фон статичный, размытие заменено лёгким градиентным затемнением.
 *
 * Уровень определяется автоматически:
 *  - режим экономии энергии или отключённые системные анимации -> MINIMAL;
 *  - устройство с малым объёмом памяти -> стартуем с LITE;
 *  - после запуска приложение ~6 секунд меряет реальную плавность (FrameMetrics); если на этом
 *    телефоне слишком много медленных кадров — уровень понижается и запоминается.
 * Так новые телефоны остаются на FULL, а старые сами переходят на облегчённый режим.
 */
object PerformanceMode {
    const val FULL = 0
    const val LITE = 1
    const val MINIMAL = 2

    private const val PREFS = "settings"
    private const val KEY_LEVEL = "perf_level"

    private const val WARMUP_MS = 1500L      // первые кадры после старта всегда медленные — не считаем
    private const val MEASURE_MS = 6500L     // сколько меряем плавность
    private const val SLOW_FRAME_MS = 32L    // кадр дольше — считаем "тормозным"
    private const val SLOW_SHARE_PERCENT = 30
    private const val MIN_FRAMES = 40

    private val listeners = CopyOnWriteArrayList<(Int) -> Unit>()
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var stored = -1
    private var monitored = false

    /** Текущий эффективный уровень (с учётом экономии энергии и отключённых анимаций). */
    fun level(context: Context): Int {
        val app = context.applicationContext
        var lvl = storedLevel(app)
        try {
            val pm = app.getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (pm?.isPowerSaveMode == true) lvl = MINIMAL
            val scale = Settings.Global.getFloat(
                app.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
            if (scale == 0f) lvl = MINIMAL
        } catch (e: Exception) {
            // ничего — остаёмся на сохранённом уровне
        }
        return lvl
    }

    private fun storedLevel(app: Context): Int {
        val cached = stored
        if (cached >= 0) return cached
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val value = if (prefs.contains(KEY_LEVEL)) {
            prefs.getInt(KEY_LEVEL, FULL).coerceIn(FULL, MINIMAL)
        } else {
            initialGuess(app)
        }
        stored = value
        return value
    }

    private fun initialGuess(app: Context): Int {
        return try {
            val am = app.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            if (am.isLowRamDevice || am.memoryClass <= 128) LITE else FULL
        } catch (e: Exception) {
            FULL
        }
    }

    fun setLevel(context: Context, level: Int) {
        val app = context.applicationContext
        val lvl = level.coerceIn(FULL, MINIMAL)
        if (storedLevel(app) == lvl) return
        stored = lvl
        app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putInt(KEY_LEVEL, lvl).apply()
        val effective = level(app)
        main.post { listeners.forEach { it(effective) } }
    }

    fun addListener(l: (Int) -> Unit) { listeners.addIfAbsent(l) }
    fun removeListener(l: (Int) -> Unit) { listeners.remove(l) }

    /**
     * Один раз за запуск процесса меряет плавность и при необходимости понижает уровень.
     * Вызывать, когда главный экран уже на виду (MainActivity.onResume).
     */
    fun startMonitor(activity: Activity) {
        if (monitored) return
        if (level(activity) >= MINIMAL) return
        monitored = true

        val window = activity.window
        val start = SystemClock.uptimeMillis()
        var total = 0
        var slow = 0

        val frameListener = Window.OnFrameMetricsAvailableListener { _, metrics, _ ->
            if (SystemClock.uptimeMillis() - start >= WARMUP_MS) {
                total++
                val ms = metrics.getMetric(FrameMetrics.TOTAL_DURATION) / 1_000_000L
                if (ms > SLOW_FRAME_MS) slow++
            }
        }
        try {
            window.addOnFrameMetricsAvailableListener(frameListener, main)
        } catch (e: Exception) {
            return
        }

        main.postDelayed({
            try { window.removeOnFrameMetricsAvailableListener(frameListener) } catch (e: Exception) { }
            if (total >= MIN_FRAMES && slow * 100 / total >= SLOW_SHARE_PERCENT) {
                setLevel(activity, storedLevel(activity.applicationContext) + 1)
            }
        }, MEASURE_MS)
    }
}
