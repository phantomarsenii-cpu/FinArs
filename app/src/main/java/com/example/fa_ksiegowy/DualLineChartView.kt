package com.example.fa_ksiegowy

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.util.AttributeSet
import android.view.View

/**
 * Dwuliniowy, gladki wykres "Podsumowanie miesiaca" na ekranie Start — linia
 * przychodu (zielona) i wydatku (czerwona) w kilku punktach miesiaca, dokladnie
 * jak w makiecie (wczesniej byl to wykres slupkowy — MonthlyBarChartView, ktory
 * zostal tu zastapiony, ale nadal jest uzywany na ekranie Raporty w innej formie).
 */
class DualLineChartView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : View(context, attrs) {

    data class Point(val label: String, val income: Double, val expense: Double)

    private var points: List<Point> = emptyList()

    private val incomePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 5f
        color = Color.parseColor("#34D399")
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val expensePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 5f
        color = Color.parseColor("#F87171")
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val axisPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#232B4D")
        strokeWidth = 2f
    }
    private val xLabelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#7B87AD")
        textSize = 24f
        textAlign = Paint.Align.CENTER
    }
    private val yLabelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#7B87AD")
        textSize = 22f
        textAlign = Paint.Align.LEFT
    }

    fun submitData(newPoints: List<Point>) {
        points = newPoints
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (points.size < 2) return

        val w = width.toFloat()
        val h = height.toFloat()
        val bottomAxis = h - 36f
        val topPadding = 16f
        val leftPadding = 36f
        val usableHeight = bottomAxis - topPadding
        val usableWidth = w - leftPadding

        val maxVal = points.flatMap { listOf(it.income, it.expense) }.maxOrNull()?.coerceAtLeast(1.0) ?: 1.0

        for (fraction in listOf(0f, 1f)) {
            val y = bottomAxis - fraction * usableHeight
            canvas.drawLine(leftPadding, y, w, y, axisPaint)
        }
        yLabelPaint.textAlign = Paint.Align.LEFT
        canvas.drawText(formatK(maxVal), 0f, topPadding + 10f, yLabelPaint)
        canvas.drawText("0", 0f, bottomAxis, yLabelPaint)

        fun xFor(i: Int) = leftPadding + usableWidth * i / (points.size - 1)
        fun yFor(v: Double) = (bottomAxis - (v / maxVal * usableHeight)).toFloat()

        fun buildPath(valueOf: (Point) -> Double): Path {
            val path = Path()
            points.forEachIndexed { i, p ->
                val x = xFor(i)
                val y = yFor(valueOf(p))
                if (i == 0) path.moveTo(x, y)
                else {
                    val prevX = xFor(i - 1)
                    val midX = (prevX + x) / 2f
                    path.cubicTo(midX, yFor(valueOf(points[i - 1])), midX, y, x, y)
                }
            }
            return path
        }

        canvas.drawPath(buildPath { it.income }, incomePaint)
        canvas.drawPath(buildPath { it.expense }, expensePaint)

        points.forEachIndexed { i, p ->
            canvas.drawText(p.label, xFor(i), h, xLabelPaint)
        }
    }

    private fun formatK(v: Double): String =
        if (v >= 1000) "${(v / 1000).let { if (it == it.toLong().toDouble()) it.toLong().toString() else String.format("%.1f", it) }}k"
        else v.toLong().toString()
}
