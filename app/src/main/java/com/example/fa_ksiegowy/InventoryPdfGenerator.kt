package com.example.fa_ksiegowy

import android.content.Context
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import java.io.OutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * PDF отчёта по одной инвентаризации склада: таблица со всеми проверенными
 * товарами (было / стало / разница / разница в деньгах по себестоимости
 * товара) плюс итоговая строка. Стиль и вёрстка страницы — как в
 * [InvoicePdfGenerator], чтобы документы приложения выглядели единообразно.
 */
object InventoryPdfGenerator {

    private const val PAGE_WIDTH = 595
    private const val PAGE_HEIGHT = 842
    private const val MARGIN = 48f

    data class Row(
        val name: String,
        val unit: String,
        val before: Double,
        val after: Double,
        val priceNet: Double,
        val priceSell: Double = 0.0
    ) {
        val diff: Double get() = after - before
        /** Разница в деньгах по себестоимости (закупке). */
        val diffValue: Double get() = diff * priceNet
        /** Упущенная (при недостаче) или лишняя (при излишке) выручка по цене продажи. */
        val diffValueSell: Double get() = diff * priceSell
    }

    fun generate(
        context: Context,
        number: Int,
        dateMillis: Long,
        rows: List<Row>,
        out: OutputStream
    ) {
        val document = PdfDocument()
        var pageNumber = 1
        var page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
        var canvas = page.canvas

        val titlePaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 20f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val hintPaint = Paint().apply { color = 0xFF555555.toInt(); textSize = 9f; isAntiAlias = true }
        val sectionPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 11.5f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val tableHeaderPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 9f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val tableCellPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 9.5f; isAntiAlias = true }
        val diffUpPaint = Paint().apply { color = 0xFF1B7F3C.toInt(); textSize = 9.5f; isAntiAlias = true }
        val diffDownPaint = Paint().apply { color = 0xFFCC3232.toInt(); textSize = 9.5f; isAntiAlias = true }
        val linePaint = Paint().apply { color = 0xFFB0B0B0.toInt(); strokeWidth = 0.75f; isAntiAlias = true }
        val headerFillPaint = Paint().apply { color = 0xFFEDEEF5.toInt() }

        var y = MARGIN

        fun newPageIfNeeded(needed: Float) {
            if (y + needed > PAGE_HEIGHT - MARGIN) {
                document.finishPage(page)
                pageNumber++
                page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
                canvas = page.canvas
                y = MARGIN
            }
        }

        fun line(text: String, paint: Paint = tableCellPaint, gap: Float = 15f, x: Float = MARGIN) {
            newPageIfNeeded(gap)
            canvas.drawText(text, x, y, paint)
            y += gap
        }

        val qtyStr: (Double) -> String = { q -> if (q == q.toLong().toDouble()) q.toLong().toString() else String.format(Locale.US, "%.2f", q) }
        val money: (Double) -> String = { v -> String.format(Locale.US, "%,.2f", v).replace(",", " ").replace(".", ",") + " zł" }
        val dateFmt = SimpleDateFormat("dd.MM.yyyy HH:mm", Locale.getDefault())

        line(context.getString(R.string.inventory_pdf_title, number.toString()), titlePaint, 26f)
        line("${context.getString(R.string.inventory_pdf_date)}: ${dateFmt.format(Date(dateMillis))}", hintPaint, 22f)

        val tableLeft = MARGIN
        val tableRight = PAGE_WIDTH - MARGIN
        val colName = tableLeft
        val colUnit = colName + 148f
        val colBefore = colUnit + 42f
        val colAfter = colBefore + 42f
        val colDiff = colAfter + 42f
        val colDiffValue = colDiff + 42f
        val colDiffValueSell = colDiffValue + 82f
        val colStops = floatArrayOf(colName, colUnit, colBefore, colAfter, colDiff, colDiffValue, colDiffValueSell, tableRight)

        val headerRowHeight = 20f
        val dataRowHeight = 18f

        newPageIfNeeded(60f)
        var segmentTop = y - 6f

        fun drawHeaderRow() {
            canvas.drawRect(tableLeft, segmentTop, tableRight, segmentTop + headerRowHeight, headerFillPaint)
            val baselineY = segmentTop + headerRowHeight - 6f
            canvas.drawText(context.getString(R.string.inventory_pdf_col_product), colName + 4f, baselineY, tableHeaderPaint)
            canvas.drawText(context.getString(R.string.inventory_pdf_col_unit), colUnit + 4f, baselineY, tableHeaderPaint)
            canvas.drawText(context.getString(R.string.inventory_pdf_col_before), colBefore + 4f, baselineY, tableHeaderPaint)
            canvas.drawText(context.getString(R.string.inventory_pdf_col_after), colAfter + 4f, baselineY, tableHeaderPaint)
            canvas.drawText(context.getString(R.string.inventory_pdf_col_diff), colDiff + 4f, baselineY, tableHeaderPaint)
            canvas.drawText(context.getString(R.string.inventory_pdf_col_diff_value), colDiffValue + 4f, baselineY, tableHeaderPaint)
            canvas.drawText(context.getString(R.string.inventory_pdf_col_diff_value_sell), colDiffValueSell + 4f, baselineY, tableHeaderPaint)
            y = segmentTop + headerRowHeight
            canvas.drawLine(tableLeft, y, tableRight, y, linePaint)
        }

        fun closeSegment(bottom: Float) {
            canvas.drawRect(tableLeft, segmentTop, tableRight, bottom, linePaint.apply { style = Paint.Style.STROKE })
            for (i in 1 until colStops.size - 1) {
                canvas.drawLine(colStops[i], segmentTop, colStops[i], bottom, linePaint)
            }
        }

        drawHeaderRow()
        for (row in rows) {
            if (y + dataRowHeight > PAGE_HEIGHT - MARGIN) {
                closeSegment(y)
                document.finishPage(page)
                pageNumber++
                page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
                canvas = page.canvas
                y = MARGIN
                segmentTop = y - 6f
                drawHeaderRow()
            }
            val baselineY = y + dataRowHeight - 6f
            val diffPaint = when {
                row.diff > 0 -> diffUpPaint
                row.diff < 0 -> diffDownPaint
                else -> tableCellPaint
            }
            canvas.drawText(row.name.take(23), colName + 4f, baselineY, tableCellPaint)
            canvas.drawText(row.unit, colUnit + 4f, baselineY, tableCellPaint)
            canvas.drawText(qtyStr(row.before), colBefore + 4f, baselineY, tableCellPaint)
            canvas.drawText(qtyStr(row.after), colAfter + 4f, baselineY, tableCellPaint)
            val diffSign = if (row.diff > 0) "+" else ""
            canvas.drawText("$diffSign${qtyStr(row.diff)}", colDiff + 4f, baselineY, diffPaint)
            canvas.drawText(money(row.diffValue), colDiffValue + 4f, baselineY, diffPaint)
            canvas.drawText(money(row.diffValueSell), colDiffValueSell + 4f, baselineY, diffPaint)
            y += dataRowHeight
            canvas.drawLine(tableLeft, y, tableRight, y, linePaint)
        }
        val gridBottom = y
        closeSegment(gridBottom)
        y += 22f

        val changed = rows.filter { it.diff != 0.0 }
        val totalDiffValue = rows.sumOf { it.diffValue }
        val totalDiffValueSell = rows.sumOf { it.diffValueSell }
        newPageIfNeeded(72f)
        line("${context.getString(R.string.inventory_pdf_total_products)}: ${rows.size}", sectionPaint, 16f)
        line("${context.getString(R.string.inventory_pdf_total_changed)}: ${changed.size}", sectionPaint, 16f)
        val totalPaint = if (totalDiffValue < 0) diffDownPaint else if (totalDiffValue > 0) diffUpPaint else sectionPaint
        line("${context.getString(R.string.inventory_pdf_total_diff_value)}: ${money(totalDiffValue)}", totalPaint, 16f)
        val totalSellPaint = if (totalDiffValueSell < 0) diffDownPaint else if (totalDiffValueSell > 0) diffUpPaint else sectionPaint
        line("${context.getString(R.string.inventory_pdf_total_diff_value_sell)}: ${money(totalDiffValueSell)}", totalSellPaint, 16f)

        document.finishPage(page)
        document.writeTo(out)
        document.close()
    }
}
