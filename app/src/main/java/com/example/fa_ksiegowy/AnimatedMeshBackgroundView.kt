package com.example.fa_ksiegowy

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View
import android.view.animation.LinearInterpolator
import kotlin.math.sin
import kotlin.random.Random

/**
 * Lightweight animated "plexus" background (glowing dots slowly drifting,
 * connected by thin lines when close enough) — same visual family as the
 * design mockup's background image, but drawn natively so it costs no
 * extra assets and matches the app's own blue palette.
 *
 * Usage: put as the first child of a FrameLayout, full match_parent, with
 * the real screen content drawn on top of it.
 */
class AnimatedMeshBackgroundView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    private data class Node(var x: Float, var y: Float, var vx: Float, var vy: Float, var r: Float)

    private val nodes = mutableListOf<Node>()
    private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#5B9CFF")
    }
    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#3B82F6")
        strokeWidth = 1.2f
    }
    private val maxLinkDist = 260f
    private var animator: ValueAnimator? = null
    private var seeded = false

    private fun seed(w: Int, h: Int) {
        if (seeded || w <= 0 || h <= 0) return
        seeded = true
        val count = ((w * h) / 42000f).toInt().coerceIn(14, 34)
        val rnd = Random(System.currentTimeMillis())
        repeat(count) {
            nodes.add(
                Node(
                    x = rnd.nextFloat() * w,
                    y = rnd.nextFloat() * h,
                    vx = (rnd.nextFloat() - 0.5f) * 0.35f,
                    vy = (rnd.nextFloat() - 0.5f) * 0.35f,
                    r = rnd.nextFloat() * 2.2f + 1.4f
                )
            )
        }
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        seed(w, h)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        seed(width, height)
        animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 16
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener {
                step()
                invalidate()
            }
            start()
        }
    }

    override fun onDetachedFromWindow() {
        animator?.cancel()
        animator = null
        super.onDetachedFromWindow()
    }

    private fun step() {
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0 || h <= 0) return
        val t = System.currentTimeMillis() * 0.0002
        for (n in nodes) {
            n.x += n.vx + sin(t + n.y * 0.01).toFloat() * 0.06f
            n.y += n.vy
            if (n.x < -20 || n.x > w + 20) n.vx = -n.vx
            if (n.y < -20 || n.y > h + 20) n.vy = -n.vy
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val n = nodes
        for (i in n.indices) {
            for (j in i + 1 until n.size) {
                val a = n[i]; val b = n[j]
                val dx = a.x - b.x; val dy = a.y - b.y
                val dist = kotlin.math.sqrt(dx * dx + dy * dy)
                if (dist < maxLinkDist) {
                    linePaint.alpha = (60 * (1f - dist / maxLinkDist)).toInt().coerceIn(0, 60)
                    canvas.drawLine(a.x, a.y, b.x, b.y, linePaint)
                }
            }
        }
        for (node in n) {
            dotPaint.alpha = 130
            canvas.drawCircle(node.x, node.y, node.r, dotPaint)
        }
    }
}
