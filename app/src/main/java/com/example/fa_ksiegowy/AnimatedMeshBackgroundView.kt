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
