package com.example.fa_ksiegowy

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Buduje "Ewidencję sprzedaży" (rejestr przychodów) w formie PDF dla działalności
 * nierejestrowanej — jedna operacja sprzedaży = jeden wiersz (Lp | Data | Wartość |
 * Narastająco | Opis), z sumą narastającą, potrzebną do pilnowania limitu kwartalnego
 * 10 813,50 zł obowiązującego od 01.01.2026 (zob. LimitsHelper.QUARTERLY_LIMIT_2026).
 *
 * Wierszy się NIE grupuje po dniu — każda sprzedaż ma swój własny wiersz, tak jak
 * w prawdziwej ewidencji, którą urząd skarbowy może poprosić o okazanie.
 *
 * Wzorowane na Pit36PdfGenerator (ta sama paleta, ten sam mechanizm tableRow/
 * newPageIfNeeded z paginacją) — celowo NIE używa InvoiceHtmlPdfGenerator, który
 * nie ma paginacji i psuje się przy dłuższych listach.
 */
object EwidencjaPdfGenerator {

    data class EwidencjaRow(
        val lp: Int,
        val dataMillis: Long,
        val wartosc: Double,
        val narastajaco: Double,
        val opis: String
    )

    private const val PAGE_WIDTH = 595
    private const val PAGE_HEIGHT = 842
    private const val MARGIN = 40f
    private val CONTENT_WIDTH = PAGE_WIDTH - 2 * MARGIN

    // Ta sama paleta co w Pit36PdfGenerator — spójny wygląd dokumentów w aplikacji.
    private const val COLOR_NAVY = 0xFF12162E.toInt()
    private const val COLOR_NAVY_SOFT = 0xFF1F2547.toInt()
    private const val COLOR_ACCENT = 0xFF2F6FED.toInt()
    private const val COLOR_LINE = 0xFFD8DCE6.toInt()
    private const val COLOR_ZEBRA = 0xFFF5F7FB.toInt()
    private const val COLOR_MUTED = 0xFF6B7280.toInt()
    private const val COLOR_HEADER_BG = 0xFFEEF2FB.toInt()
    private const val COLOR_TOTAL_BG = 0xFFEAF1FE.toInt()

    private data class Col(
        val text: String,
        val weight: Float,
        val paint: Paint,
        val alignRight: Boolean = false
    )

    /**
     * @param rows wiersze ewidencji (patrz mapowanie w ReportFragment: kolejne sprzedaże
     *             z narastającą sumą).
     * @param periodLabel podpis okresu w nagłówku, np. "Q3 2026 (lip-wrz)" albo "2026".
     */
    fun generate(rows: List<EwidencjaRow>, periodLabel: String, file: File) {
        val document = PdfDocument()
        var pageNumber = 1
        var page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
        var canvas: Canvas = page.canvas
        var y = MARGIN

        val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = COLOR_NAVY; textSize = 16f; typeface = Typeface.DEFAULT_BOLD }
        val subPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = COLOR_MUTED; textSize = 9f }
        val sectionPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; textSize = 10.5f; typeface = Typeface.DEFAULT_BOLD }
        val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = COLOR_MUTED; textSize = 9.5f }
        val valuePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = COLOR_NAVY; textSize = 9.5f }
        val headerCellPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = COLOR_NAVY; textSize = 8.5f; typeface = Typeface.DEFAULT_BOLD }
        val totalLabelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = COLOR_NAVY; textSize = 9.5f; typeface = Typeface.DEFAULT_BOLD }
        val totalValuePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = COLOR_ACCENT; textSize = 10.5f; typeface = Typeface.DEFAULT_BOLD }
        val disclaimerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = COLOR_MUTED; textSize = 8f }
        val badgeTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; textSize = 9f; typeface = Typeface.DEFAULT_BOLD }

        val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = COLOR_LINE; style = Paint.Style.STROKE; strokeWidth = 0.8f }
        val zebraFill = Paint().apply { color = COLOR_ZEBRA; style = Paint.Style.FILL }
        val headerFill = Paint().apply { color = COLOR_HEADER_BG; style = Paint.Style.FILL }
        val totalFill = Paint().apply { color = COLOR_TOTAL_BG; style = Paint.Style.FILL }
        val sectionFill = Paint().apply { color = COLOR_NAVY_SOFT; style = Paint.Style.FILL }
        val badgeFill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = COLOR_ACCENT; style = Paint.Style.FILL }

        fun newPageIfNeeded(needed: Float) {
            if (y + needed > PAGE_HEIGHT - MARGIN) {
                document.finishPage(page)
                pageNumber++
                page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
                canvas = page.canvas
                y = MARGIN
            }
        }

        fun wrap(text: String, paint: Paint, maxWidth: Float): List<String> {
            if (text.isEmpty()) return listOf("")
            val words = text.split(" ")
            val lines = mutableListOf<String>()
            var current = StringBuilder()
            for (w in words) {
                val candidate = if (current.isEmpty()) w else current.toString() + " " + w
                if (paint.measureText(candidate) > maxWidth && current.isNotEmpty()) {
                    lines.add(current.toString())
                    current = StringBuilder(w)
                } else {
                    current = StringBuilder(candidate)
                }
            }
            if (current.isNotEmpty()) lines.add(current.toString())
            return if (lines.isEmpty()) listOf("") else lines
        }

        val cellPad = 5f
        val lineH = 11f

        fun tableRow(cols: List<Col>, bg: Paint? = null) {
            val widths = cols.map { CONTENT_WIDTH * it.weight }
            val wrapped = cols.mapIndexed { i, c -> wrap(c.text, c.paint, widths[i] - 2 * cellPad) }
            val maxLines = wrapped.maxOf { it.size }.coerceAtLeast(1)
            val rowH = maxLines * lineH + 2 * cellPad
            newPageIfNeeded(rowH)

            val top = y
            val bottom = y + rowH
            if (bg != null) canvas.drawRect(MARGIN, top, MARGIN + CONTENT_WIDTH, bottom, bg)

            var x = MARGIN
            for (i in cols.indices) {
                val col = cols[i]
                val w = widths[i]
                val lines = wrapped[i]
                var ty = top + cellPad + lineH - 3f
                for (l in lines) {
                    val tx = if (col.alignRight) x + w - cellPad - col.paint.measureText(l) else x + cellPad
                    canvas.drawText(l, tx, ty, col.paint)
                    ty += lineH
                }
                x += w
            }
            canvas.drawRect(MARGIN, top, MARGIN + CONTENT_WIDTH, bottom, borderPaint)
            var vx = MARGIN
            for (i in 0 until cols.size - 1) {
                vx += widths[i]
                canvas.drawLine(vx, top, vx, bottom, borderPaint)
            }
            y = bottom
        }

        fun sectionHeader(title: String) {
            newPageIfNeeded(18f + 6f)
            y += 6f
            val h = 18f
            newPageIfNeeded(h)
            canvas.drawRect(MARGIN, y, MARGIN + CONTENT_WIDTH, y + h, sectionFill)
            canvas.drawText(title, MARGIN + 8f, y + h - 5.5f, sectionPaint)
            y += h
        }

        val money: (Double) -> String = {
            String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") + " zł"
        }
        val dateFmt = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())
        val genFmt = SimpleDateFormat("dd.MM.yyyy HH:mm", Locale.getDefault())

        // ---- Nagłówek dokumentu ----
        val badgeText = "Ewidencja sprzedaży"
        val badgeW = badgeTextPaint.measureText(badgeText) + 16f
        canvas.drawRoundRect(RectF(MARGIN + CONTENT_WIDTH - badgeW, y, MARGIN + CONTENT_WIDTH, y + 16f), 3f, 3f, badgeFill)
        canvas.drawText(badgeText, MARGIN + CONTENT_WIDTH - badgeW + 8f, y + 11.5f, badgeTextPaint)
        y += 24f

        canvas.drawText("FA Księgowy — Ewidencja sprzedaży za okres: $periodLabel", MARGIN, y, titlePaint)
        y += 14f
        canvas.drawText("Wygenerowano: ${genFmt.format(Date())} · dokument pomocniczy, nie jest oficjalnym formularzem", MARGIN, y, subPaint)
        y += 10f

        // ---- Tabela operacji ----
        sectionHeader("Wykaz sprzedaży")
        tableRow(
            listOf(
                Col("Lp", 0.08f, headerCellPaint),
                Col("Data", 0.17f, headerCellPaint),
                Col("Wartość", 0.22f, headerCellPaint, alignRight = true),
                Col("Narastająco", 0.25f, headerCellPaint, alignRight = true),
                Col("Opis", 0.28f, headerCellPaint)
            ),
            bg = headerFill
        )

        rows.forEachIndexed { idx, r ->
            tableRow(
                listOf(
                    Col(r.lp.toString(), 0.08f, valuePaint),
                    Col(dateFmt.format(Date(r.dataMillis)), 0.17f, valuePaint),
                    Col(money(r.wartosc), 0.22f, valuePaint, alignRight = true),
                    Col(money(r.narastajaco), 0.25f, valuePaint, alignRight = true),
                    Col(r.opis, 0.28f, labelPaint)
                ),
                bg = if (idx % 2 == 1) zebraFill else null
            )
        }

        val total = rows.sumOf { it.wartosc }
        tableRow(
            listOf(
                Col("Razem", 0.52f, totalLabelPaint),
                Col(money(total), 0.48f, totalValuePaint, alignRight = true)
            ),
            bg = totalFill
        )

        // ---- Disclaimer ----
        newPageIfNeeded(28f)
        y += 8f
        val disclaimerLines = wrap(
            "Ewidencja generowana automatycznie na podstawie zapisanych w aplikacji przychodów. To dokument pomocniczy — " +
                "w razie kontroli warto porównać go z fakturami/paragonami i danymi z konta bankowego.",
            disclaimerPaint, CONTENT_WIDTH
        )
        for (l in disclaimerLines) {
            newPageIfNeeded(11f)
            canvas.drawText(l, MARGIN, y, disclaimerPaint)
            y += 11f
        }

        document.finishPage(page)
        FileOutputStream(file).use { out ->
            document.writeTo(out)
        }
        document.close()
    }
}
