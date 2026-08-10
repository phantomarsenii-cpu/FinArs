package com.example.fa_ksiegowy

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View

/**
 * Простая столбчатая диаграмма "доход/расход по месяцам" без сторонних
 * библиотек (рисуется вручную на Canvas) — намеренное решение, чтобы не
 * тащить в build.gradle новую зависимость (риск конфликта версий/сборки
 * через GitHub Actions, который негде протестировать локально).
 */
class MonthlyBarChartView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : View(context, attrs) {

    data class MonthPoint(val label: String, val income: Double, val expense: Double)

    private var points: List<MonthPoint> = emptyList()

    private val incomePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#4CAF50") }
    private val expensePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#FF6B6B") }
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#A0A8B8")
        textSize = 28f
        textAlign = Paint.Align.CENTER
    }
    private val axisPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#3A4152")
        strokeWidth = 2f
    }

    fun submitData(newPoints: List<MonthPoint>) {
        points = newPoints
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (points.isEmpty()) return

        val w = width.toFloat()
        val h = height.toFloat()
        val bottomAxis = h - 60f
        canvas.drawLine(0f, bottomAxis, w, bottomAxis, axisPaint)

        val maxVal = points.maxOf { maxOf(it.income, it.expense) }.coerceAtLeast(1.0)
        val slotWidth = w / points.size
        val barWidth = slotWidth * 0.32f
        val topPadding = 20f
        val usableHeight = bottomAxis - topPadding

        points.forEachIndexed { i, p ->
            val slotCenter = slotWidth * i + slotWidth / 2f

            val incomeHeight = (p.income / maxVal * usableHeight).toFloat()
            val incomeLeft = slotCenter - barWidth - 4f
            canvas.drawRect(incomeLeft, bottomAxis - incomeHeight, incomeLeft + barWidth, bottomAxis, incomePaint)

            val expenseHeight = (p.expense / maxVal * usableHeight).toFloat()
            val expenseLeft = slotCenter + 4f
            canvas.drawRect(expenseLeft, bottomAxis - expenseHeight, expenseLeft + barWidth, bottomAxis, expensePaint)

            canvas.drawText(p.label, slotCenter, h - 20f, labelPaint)
        }
    }
}
