package com.example.fa_ksiegowy

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader
import android.util.AttributeSet
import android.view.View

/**
 * Gladki wykres liniowy "Trend (N miesiecy)" na ekranie Raporty — jedna linia
 * (np. zysk netto per miesiac) z delikatnym wypelnieniem gradientowym pod spodem,
 * rysowany recznie na Canvas (patrz MonthlyBarChartView/DonutChartView — to samo podejscie).
 */
class TrendLineChartView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : View(context, attrs) {

    data class Point(val label: String, val value: Double)

    private var points: List<Point> = emptyList()

    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 5f
        color = Color.parseColor("#4C8DFF")
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val axisPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#232B4D")
        strokeWidth = 2f
    }
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
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
        val bottomAxis = h - 40f
        val topPadding = 16f
        val leftPadding = 4f
        val usableHeight = bottomAxis - topPadding
        val usableWidth = w - leftPadding

        val maxVal = points.maxOf { it.value }.coerceAtLeast(1.0)
        val minVal = minOf(0.0, points.minOf { it.value })
        val range = (maxVal - minVal).coerceAtLeast(1.0)

        // Poziome linie siatki (0 / polowa / max)
        for (fraction in listOf(0f, 0.5f, 1f)) {
            val y = bottomAxis - fraction * usableHeight
            canvas.drawLine(leftPadding, y, w, y, axisPaint)
        }

        fun xFor(i: Int) = leftPadding + usableWidth * i / (points.size - 1)
        fun yFor(v: Double) = (bottomAxis - ((v - minVal) / range * usableHeight)).toFloat()

        val linePath = Path()
        val fillPath = Path()
        points.forEachIndexed { i, p ->
            val x = xFor(i)
            val y = yFor(p.value)
            if (i == 0) {
                linePath.moveTo(x, y)
                fillPath.moveTo(x, bottomAxis)
                fillPath.lineTo(x, y)
            } else {
                val prevX = xFor(i - 1)
                val midX = (prevX + x) / 2f
                linePath.cubicTo(midX, yFor(points[i - 1].value), midX, y, x, y)
                fillPath.cubicTo(midX, yFor(points[i - 1].value), midX, y, x, y)
            }
        }
        fillPath.lineTo(xFor(points.size - 1), bottomAxis)
        fillPath.close()

        fillPaint.shader = LinearGradient(
            0f, topPadding, 0f, bottomAxis,
            Color.parseColor("#404C8DFF"), Color.parseColor("#004C8DFF"),
            Shader.TileMode.CLAMP
        )
        canvas.drawPath(fillPath, fillPaint)
        canvas.drawPath(linePath, linePaint)

        points.forEachIndexed { i, p ->
            canvas.drawText(p.label, xFor(i), h, labelPaint)
        }
    }
}
