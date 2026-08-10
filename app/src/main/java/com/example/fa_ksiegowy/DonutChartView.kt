package com.example.fa_ksiegowy

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View

/**
 * Wykres kolowy (donut) "Podsumowanie" na ekranie Raporty — trzy segmenty
 * (przychod/wydatki/podatek) rysowane recznie na Canvas, bez zaleznosci od
 * bibliotek wykresow (patrz MonthlyBarChartView — to samo podejscie).
 */
class DonutChartView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : View(context, attrs) {

    data class Segment(val value: Double, val color: Int)

    private var segments: List<Segment> = emptyList()
    private var centerLabel: String = ""
    private var centerValue: String = ""

    private val arcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = Color.parseColor("#232B4D")
    }
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#A0A8C8")
        textAlign = Paint.Align.CENTER
        textSize = 26f
    }
    private val valuePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textAlign = Paint.Align.CENTER
        textSize = 40f
        isFakeBoldText = true
    }

    fun submitData(segs: List<Segment>, centerLabel: String, centerValue: String) {
        this.segments = segs.filter { it.value > 0 }
        this.centerLabel = centerLabel
        this.centerValue = centerValue
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        val strokeW = h * 0.16f
        arcPaint.strokeWidth = strokeW
        bgPaint.strokeWidth = strokeW
        val pad = strokeW / 2f + 4f
        val rect = RectF(pad, pad, w - pad, h - pad)

        canvas.drawArc(rect, 0f, 360f, false, bgPaint)

        val total = segments.sumOf { it.value }
        if (total > 0) {
            var startAngle = -90f
            for (seg in segments) {
                val sweep = (seg.value / total * 360.0).toFloat()
                arcPaint.color = seg.color
                canvas.drawArc(rect, startAngle, sweep.coerceAtLeast(0.5f), false, arcPaint)
                startAngle += sweep
            }
        }

        val cx = w / 2f
        val cy = h / 2f
        canvas.drawText(centerValue, cx, cy + 4f, valuePaint)
        canvas.drawText(centerLabel, cx, cy - valuePaint.textSize + 2f, labelPaint)
    }
}
