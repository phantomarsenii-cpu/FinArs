#!/usr/bin/env bash
# Update 73: оптимизация для слабых/старых телефонов (лаги, "телепортация" фона, кнопки не нажимаются).
# Причины и исправления:
#  1) AnimatedMeshBackgroundView крутился на КАЖДОЙ вкладке одновременно (4 экрана), в т. ч. скрытых,
#     с ValueAnimator длительностью 16 мс и сотнями отдельных drawLine на кадр -> главный поток
#     не успевал, касания не проходили. Теперь: анимация только пока вид виден, Choreographer
#     вместо ValueAnimator, ограничение частоты кадров, движение по времени (не по кадрам),
#     меньше точек, линии пачками (drawLines).
#  2) Размытие BlurView под системными панелями перерисовывается вместе с движущимся фоном —
#     на слабых GPU это самое тяжёлое. Добавлен PerformanceMode (FULL / LITE / MINIMAL):
#     учитывает экономию энергии, отключённые анимации, малый объём памяти и САМ замеряет плавность
#     первые секунды после запуска (FrameMetrics). Слабое устройство автоматически переходит на
#     облегчённый режим (реже кадры, меньше точек, затем статичный фон и градиент вместо размытия).
#     Новые телефоны остаются на полном качестве.
#  3) Страховка тура: если шаг не отрисовался за 3.5 с, тур не блокирует экран.
#  4) Тур: убрано упоминание авансовых платежей в уведомлениях (для нерегистрируемой деятельности
#     такого уведомления нет).
# Запускать из КОРНЯ репозитория.
set -euo pipefail

M=app/src/main
J=$M/java/com/example/fa_ksiegowy
for f in "$J/EdgeToEdge.kt" "$J/MainActivity.kt" "$J/OnboardingTour.kt" "$J/TourOverlayView.kt" "$J/AnimatedMeshBackgroundView.kt"; do
  [ -f "$f" ] || { echo "Запусти из корня репозитория (нет $f)"; exit 1; }
done

BK=".update73_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BK"
for f in "$J/EdgeToEdge.kt" "$J/MainActivity.kt" "$J/OnboardingTour.kt" "$J/TourOverlayView.kt" \
         "$J/AnimatedMeshBackgroundView.kt" "$M/res/values/strings.xml" "$M/res/values-pl/strings.xml" \
         "$M/res/values-ru/strings.xml" "$M/res/values-uk/strings.xml"; do
  cp "$f" "$BK/$(echo "$f" | tr '/' '_')"
done
# бэкапы не должны попадать в git
grep -qxF '.update*_backup_*/' .gitignore 2>/dev/null || echo '.update*_backup_*/' >> .gitignore

cat > "$J/PerformanceMode.kt" <<'KT_PERF'
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
KT_PERF
echo "создан: $J/PerformanceMode.kt"

cat > "$J/AnimatedMeshBackgroundView.kt" <<'KT_MESH'
package com.example.fa_ksiegowy

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.Choreographer
import android.view.View
import kotlin.math.sin
import kotlin.random.Random

/**
 * Лёгкий анимированный фон ("plexus": светящиеся точки, соединённые тонкими линиями).
 *
 * Update 73 — оптимизация для старых телефонов:
 *  - анимация идёт ТОЛЬКО пока вид реально на экране (скрытые вкладки, свёрнутое приложение,
 *    закрытые другим экраном — не рисуются и не тратят CPU/GPU);
 *  - частота кадров ограничена (30 fps, на слабых устройствах 20 fps), движение зависит от
 *    времени, а не от числа кадров — скорость одинаковая на любом телефоне;
 *  - меньше точек, линии рисуются пачками (3 группы прозрачности) вместо сотен отдельных вызовов;
 *  - на уровне MINIMAL (экономия энергии / очень слабый телефон) фон статичный.
 */
class AnimatedMeshBackgroundView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    private var xs = FloatArray(0)
    private var ys = FloatArray(0)
    private var vxs = FloatArray(0)
    private var vys = FloatArray(0)
    private var rs = FloatArray(0)
    private var count = 0

    private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#5B9CFF")
        alpha = 170
    }
    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#3B82F6")
        strokeWidth = 1.2f
    }

    // 3 группы линий по прозрачности (ближе — ярче)
    private var bucketA = FloatArray(0)
    private var bucketB = FloatArray(0)
    private var bucketC = FloatArray(0)

    private var level = PerformanceMode.level(context)
    private var maxLinkDist = 300f
    private var minFrameIntervalNs = 33_000_000L
    private var running = false
    private var lastFrameNs = 0L
    private var seededW = 0
    private var seededH = 0

    private val levelListener: (Int) -> Unit = { newLevel ->
        level = newLevel
        applyLevel()
        updateRunning()
        invalidate()
    }

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (!running) return
            if (lastFrameNs == 0L) lastFrameNs = frameTimeNanos
            val elapsed = frameTimeNanos - lastFrameNs
            if (elapsed >= minFrameIntervalNs) {
                // dt в "кадрах по 60 fps": движение не зависит от реальной частоты кадров
                val dt = (elapsed / 16_666_667f).coerceIn(0.5f, 4f)
                lastFrameNs = frameTimeNanos
                step(dt)
                invalidate()
            }
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    private fun applyLevel() {
        when (level) {
            PerformanceMode.FULL -> { maxLinkDist = 300f; minFrameIntervalNs = 30_000_000L }
            PerformanceMode.LITE -> { maxLinkDist = 230f; minFrameIntervalNs = 48_000_000L }
            else -> { maxLinkDist = 260f; minFrameIntervalNs = 100_000_000L }
        }
        if (seededW > 0 && seededH > 0) seed(seededW, seededH, force = true)
    }

    private fun targetCount(w: Int, h: Int): Int {
        val base = ((w * h) / 30000f).toInt()
        return when (level) {
            PerformanceMode.FULL -> base.coerceIn(20, 40)
            PerformanceMode.LITE -> base.coerceIn(12, 22)
            else -> base.coerceIn(16, 28)
        }
    }

    private fun seed(w: Int, h: Int, force: Boolean = false) {
        if (w <= 0 || h <= 0) return
        val n = targetCount(w, h)
        if (!force && count == n && seededW == w && seededH == h) return
        seededW = w
        seededH = h
        xs = FloatArray(n); ys = FloatArray(n)
        vxs = FloatArray(n); vys = FloatArray(n); rs = FloatArray(n)
        count = n
        val rnd = Random(System.nanoTime())
        for (i in 0 until n) {
            xs[i] = rnd.nextFloat() * w
            ys[i] = rnd.nextFloat() * h
            vxs[i] = (rnd.nextFloat() - 0.5f) * 0.55f
            vys[i] = (rnd.nextFloat() - 0.5f) * 0.55f
            rs[i] = rnd.nextFloat() * 2.6f + 1.4f
        }
        val pairs = n * (n - 1) / 2 * 4
        if (bucketA.size < pairs) {
            bucketA = FloatArray(pairs); bucketB = FloatArray(pairs); bucketC = FloatArray(pairs)
        }
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        applyLevel()
        seed(w, h, force = true)
    }

    // ---------- жизненный цикл: рисуем только когда вид реально виден ----------

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        level = PerformanceMode.level(context)
        applyLevel()
        PerformanceMode.addListener(levelListener)
        updateRunning()
    }

    override fun onDetachedFromWindow() {
        PerformanceMode.removeListener(levelListener)
        stop()
        super.onDetachedFromWindow()
    }

    override fun onVisibilityAggregated(isVisible: Boolean) {
        super.onVisibilityAggregated(isVisible)
        updateRunning()
    }

    override fun onWindowVisibilityChanged(visibility: Int) {
        super.onWindowVisibilityChanged(visibility)
        updateRunning()
    }

    private fun shouldRun(): Boolean =
        isAttachedToWindow && isShown && windowVisibility == VISIBLE && level < PerformanceMode.MINIMAL

    private fun updateRunning() {
        if (shouldRun()) start() else stop()
    }

    private fun start() {
        if (running) return
        running = true
        lastFrameNs = 0L
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    private fun stop() {
        if (!running) return
        running = false
        Choreographer.getInstance().removeFrameCallback(frameCallback)
    }

    // ---------- физика и рисование ----------

    private fun step(dt: Float) {
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0 || h <= 0) return
        val t = System.currentTimeMillis() * 0.0002
        for (i in 0 until count) {
            xs[i] += (vxs[i] + sin(t + ys[i] * 0.01).toFloat() * 0.06f) * dt
            ys[i] += vys[i] * dt
            if (xs[i] < -20 || xs[i] > w + 20) vxs[i] = -vxs[i]
            if (ys[i] < -20 || ys[i] > h + 20) vys[i] = -vys[i]
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val n = count
        if (n == 0) return
        val maxSq = maxLinkDist * maxLinkDist
        var ca = 0; var cb = 0; var cc = 0
        for (i in 0 until n) {
            val ax = xs[i]; val ay = ys[i]
            for (j in i + 1 until n) {
                val dx = ax - xs[j]; val dy = ay - ys[j]
                val d2 = dx * dx + dy * dy
                if (d2 < maxSq) {
                    val closeness = 1f - d2 / maxSq   // 0 (далеко) .. 1 (рядом)
                    when {
                        closeness > 0.6f -> {
                            bucketA[ca++] = ax; bucketA[ca++] = ay; bucketA[ca++] = xs[j]; bucketA[ca++] = ys[j]
                        }
                        closeness > 0.25f -> {
                            bucketB[cb++] = ax; bucketB[cb++] = ay; bucketB[cb++] = xs[j]; bucketB[cb++] = ys[j]
                        }
                        else -> {
                            bucketC[cc++] = ax; bucketC[cc++] = ay; bucketC[cc++] = xs[j]; bucketC[cc++] = ys[j]
                        }
                    }
                }
            }
        }
        if (cc > 0) { linePaint.alpha = 26; canvas.drawLines(bucketC, 0, cc, linePaint) }
        if (cb > 0) { linePaint.alpha = 55; canvas.drawLines(bucketB, 0, cb, linePaint) }
        if (ca > 0) { linePaint.alpha = 85; canvas.drawLines(bucketA, 0, ca, linePaint) }
        for (i in 0 until n) canvas.drawCircle(xs[i], ys[i], rs[i], dotPaint)
    }
}
KT_MESH
echo "обновлён: $J/AnimatedMeshBackgroundView.kt"

python3 - <<'PY'
import re
M = "app/src/main"
J = M + "/java/com/example/fa_ksiegowy"
def read(p): return open(p, encoding="utf-8").read()
def write(p, s): open(p, "w", encoding="utf-8").write(s); print("изменён:", p)
def rep(s, old, new, what):
    assert s.count(old) == 1, "не найден фрагмент: " + what
    return s.replace(old, new)

# ---------------- EdgeToEdge.kt: размытие -> лёгкий градиент на уровне MINIMAL ----------------
p = J + "/EdgeToEdge.kt"
s = read(p)
if "blurOn" not in s:
    s = rep(s,
"""        init {
            setWillNotDraw(false)
            addView(blurView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        }
""",
"""        // Update 73: на слабых устройствах (PerformanceMode.MINIMAL) вместо размытия — простой
        // градиент-затемнение: без BlurView и без saveLayer на каждый кадр.
        private var blurOn = true
        private val scrimPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val levelListener: (Int) -> Unit = { applyLevel(it) }

        init {
            setWillNotDraw(false)
            addView(blurView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
            applyLevel(PerformanceMode.level(context))
        }

        private fun applyLevel(level: Int) {
            val on = level < PerformanceMode.MINIMAL
            if (on == blurOn && blurView.visibility == (if (on) VISIBLE else GONE)) return
            blurOn = on
            blurView.visibility = if (on) VISIBLE else GONE
            invalidate()
        }

        override fun onAttachedToWindow() {
            super.onAttachedToWindow()
            PerformanceMode.addListener(levelListener)
            applyLevel(PerformanceMode.level(context))
        }

        override fun onDetachedFromWindow() {
            PerformanceMode.removeListener(levelListener)
            super.onDetachedFromWindow()
        }
""", "FadeBlurStrip init")

    s = rep(s,
"""            invalidate()
        }

        override fun dispatchDraw(canvas: Canvas) {
            val save = canvas.saveLayer(0f, 0f, width.toFloat(), height.toFloat(), null)
""",
"""            // тот же градиент, но цветом затемнения — для режима без размытия
            val scrim = Color.argb(215, 5, 9, 24)
            val scrimClear = Color.argb(0, 5, 9, 24)
            scrimPaint.shader = if (fadeFromEdge == Gravity.TOP) {
                LinearGradient(0f, 0f, 0f, h.toFloat(), scrim, scrimClear, Shader.TileMode.CLAMP)
            } else {
                val solid = solidPx.coerceIn(0, h - 1)
                val frac = (h - solid).toFloat() / h
                LinearGradient(
                    0f, 0f, 0f, h.toFloat(),
                    intArrayOf(scrimClear, scrim, scrim),
                    floatArrayOf(0f, frac, 1f),
                    Shader.TileMode.CLAMP
                )
            }
            invalidate()
        }

        override fun dispatchDraw(canvas: Canvas) {
            if (!blurOn) {
                canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), scrimPaint)
                return
            }
            val save = canvas.saveLayer(0f, 0f, width.toFloat(), height.toFloat(), null)
""", "FadeBlurStrip dispatchDraw")
    write(p, s)
else:
    print("EdgeToEdge: уже применено")

# ---------------- MainActivity.kt: замер плавности ----------------
p = J + "/MainActivity.kt"
s = read(p)
if "PerformanceMode" not in s:
    s = rep(s,
"""    override fun onResume() {
        super.onResume()
        scheduleTourIfNeeded()
    }
""",
"""    override fun onResume() {
        super.onResume()
        // Update 73: один раз за запуск замеряем плавность и при необходимости облегчаем анимации.
        PerformanceMode.startMonitor(this)
        scheduleTourIfNeeded()
    }
""", "MainActivity.onResume")
    write(p, s)
else:
    print("MainActivity: уже применено")

# ---------------- TourOverlayView.kt: без пульсации на слабых устройствах ----------------
p = J + "/TourOverlayView.kt"
s = read(p)
if "PerformanceMode" not in s:
    s = rep(s,
"""    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        pulseAnimator = ValueAnimator.ofFloat(0f, 1f).apply {""",
"""    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (PerformanceMode.level(context) >= PerformanceMode.LITE) {
            pulse = 0.6f   // слабое устройство: рамка без бесконечной пульсации
            return
        }
        pulseAnimator = ValueAnimator.ofFloat(0f, 1f).apply {""", "TourOverlayView pulse")
    write(p, s)
else:
    print("TourOverlayView: уже применено")

# ---------------- тексты: уведомления ----------------
T = {
 "values":    "Reminders about limits, low stock, invoice due dates and the annual PIT deadline appear here.",
 "values-pl": "Tutaj pojawiają się przypomnienia o limitach, niskim stanie magazynu, terminach płatności faktur i terminie rocznego zeznania PIT.",
 "values-ru": "Здесь появляются напоминания о лимитах, низких остатках на складе, сроках оплаты фактур и сроке подачи годовой декларации PIT.",
 "values-uk": "Тут з’являються нагадування про ліміти, низькі залишки на складі, строки оплати фактур і строк подання річної декларації PIT.",
}
for d, txt in T.items():
    p = M + "/res/" + d + "/strings.xml"
    s = read(p)
    pat = re.compile(r'(<string name="tour_bell_text"[^>]*>)(.*?)(</string>)', re.S)
    assert len(pat.findall(s)) == 1, d + ": нет tour_bell_text"
    s = pat.sub(lambda m: m.group(1) + txt + m.group(3), s, count=1)
    write(p, s)

# ---------------- OnboardingTour.kt: страховка от "зависшего" тура ----------------
# Если по какой-то причине шаг не отрисовался за 3.5 с (медленное устройство, вкладка не успела
# создаться), оверлей показывает шаг без подсветки, чтобы экран никогда не оставался заблокированным.
p = J + "/OnboardingTour.kt"
s = read(p)
if "guardIndex" not in s:
    old = "        ov.beginTransition()\n\n"
    assert s.count(old) == 1, "OnboardingTour: нет beginTransition"
    s = s.replace(old, old.rstrip("\n") + """
        val guardIndex = i
        handler.postDelayed({
            if (overlay != null && busy && index == guardIndex) render(step, null)
        }, 3500)

""")
    write(p, s)
else:
    print("OnboardingTour: уже применено")

PY

echo
echo "Готово. Бэкапы: $BK"
