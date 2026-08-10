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
 * Buduje PDF dokumentu sprzedaży dla osoby fizycznej (Faktura imienna, gdy
 * sprzedawca jest VAT-owcem, lub Rachunek, gdy nie jest) — z pozycją
 * towaru/usługi w formie tabeli, danymi sprzedawcy/nabywcy obok siebie
 * i pieczątką "ZAPŁACONO". Wszystkie etykiety pochodzą z zasobów string —
 * dokument jest w pełni w języku aktualnie wybranym w aplikacji (kontekst
 * przekazywany przez wywołującego musi mieć już zastosowaną lokalizację,
 * patrz [BaseActivity]/[LocaleHelper] — nie używamy tu applicationContext).
 */
object InvoicePdfGenerator {

    private const val PAGE_WIDTH = 595
    private const val PAGE_HEIGHT = 842
    private const val MARGIN = 48f

    private data class Labels(
        val docKind: String,
        val issueDate: String,
        val saleDate: String,
        val seller: String,
        val buyer: String,
        val nip: String,
        val bankAccount: String,
        val buyerPrivate: String,
        val tableLp: String,
        val tableName: String,
        val tableUnit: String,
        val tableQty: String,
        val tablePrice: String,
        val tableTotal: String,
        val unitPiece: String,
        val sumLabel: String,
        val paidStamp: String,
        val paymentDateLabel: String,
        val paymentStatusLine: String,
        val footer: String
    )

    private fun buildLabels(context: Context, isVatPayer: Boolean, paymentMethod: PaymentMethod): Labels = Labels(
        docKind = context.getString(if (isVatPayer) R.string.invoice_pdf_faktura else R.string.invoice_pdf_rachunek),
        issueDate = context.getString(R.string.invoice_pdf_issue_date),
        saleDate = context.getString(R.string.invoice_pdf_sale_date),
        seller = context.getString(R.string.invoice_pdf_seller),
        buyer = context.getString(R.string.invoice_pdf_buyer),
        nip = context.getString(R.string.invoice_pdf_nip),
        bankAccount = context.getString(R.string.invoice_pdf_bank_account),
        buyerPrivate = context.getString(R.string.invoice_pdf_buyer_private),
        tableLp = context.getString(R.string.invoice_pdf_table_lp),
        tableName = context.getString(R.string.invoice_pdf_table_name),
        tableUnit = context.getString(R.string.invoice_pdf_table_unit),
        tableQty = context.getString(R.string.invoice_pdf_table_qty),
        tablePrice = context.getString(R.string.invoice_pdf_table_price),
        tableTotal = context.getString(R.string.invoice_pdf_table_total),
        unitPiece = context.getString(R.string.invoice_pdf_unit_piece),
        sumLabel = context.getString(R.string.invoice_pdf_sum_label),
        paidStamp = context.getString(R.string.invoice_pdf_paid_stamp),
        paymentDateLabel = context.getString(R.string.invoice_pdf_payment_date),
        paymentStatusLine = context.getString(paymentMethod.paidLabelResId),
        footer = context.getString(R.string.invoice_pdf_footer)
    )

    fun generate(
        context: Context,
        seller: InvoiceSellerData,
        invoiceNumber: Int,
        issueDateMillis: Long,
        paymentDateMillis: Long,
        serviceDateMillis: Long,
        isPhysicalPerson: Boolean,
        buyerName: String,
        buyerNip: String?,
        buyerStreet: String,
        buyerPostalCode: String,
        buyerCity: String,
        serviceName: String,
        amount: Double,
        paymentMethod: PaymentMethod,
        out: OutputStream
    ) {
        val isVatPayer = seller.nip.isNotBlank()
        val l = buildLabels(context, isVatPayer, paymentMethod)

        val document = PdfDocument()
        var pageNumber = 1
        var page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
        var canvas = page.canvas

        val titlePaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 20f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val sectionPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 11.5f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val textPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 10.5f; isAntiAlias = true }
        val hintPaint = Paint().apply { color = 0xFF555555.toInt(); textSize = 9f; isAntiAlias = true }
        val tableHeaderPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 9.5f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val tableCellPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 10f; isAntiAlias = true }
        val stampPaint = Paint().apply { color = 0xFF1B7F3C.toInt(); textSize = 13f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
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

        fun line(text: String, paint: Paint = textPaint, gap: Float = 15f, x: Float = MARGIN) {
            newPageIfNeeded(gap)
            canvas.drawText(text, x, y, paint)
            y += gap
        }

        fun wrappedLines(text: String, maxCharsPerLine: Int, paint: Paint, gap: Float, x: Float = MARGIN): Float {
            val words = text.split(" ")
            var current = StringBuilder()
            var startY = y
            for (w in words) {
                if (current.length + w.length + 1 > maxCharsPerLine) {
                    newPageIfNeeded(gap)
                    canvas.drawText(current.toString(), x, y, paint)
                    y += gap
                    current = StringBuilder()
                }
                if (current.isNotEmpty()) current.append(" ")
                current.append(w)
            }
            if (current.isNotEmpty()) {
                newPageIfNeeded(gap)
                canvas.drawText(current.toString(), x, y, paint)
                y += gap
            }
            return y - startY
        }

        val money: (Double) -> String = {
            String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") + " zł"
        }
        val dateFmt = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())

        // --- Nagłówek ---
        line("${l.docKind} nr $invoiceNumber", titlePaint, 26f)
        line("${l.issueDate}: ${dateFmt.format(Date(issueDateMillis))}    ${l.saleDate}: ${dateFmt.format(Date(serviceDateMillis))}", hintPaint, 22f)

        // --- Sprzedawca / Nabywca obok siebie ---
        val colLeftX = MARGIN
        val colRightX = MARGIN + (PAGE_WIDTH - 2 * MARGIN) / 2 + 8f
        val blockTopY = y

        y = blockTopY
        line(l.seller, sectionPaint, 17f, colLeftX)
        if (seller.name.isNotBlank()) line(seller.name, textPaint, 14f, colLeftX)
        val sellerAddress = listOfNotNull(
            seller.street.ifBlank { null },
            listOf(seller.postalCode, seller.city).filter { it.isNotBlank() }.joinToString(" ").ifBlank { null }
        ).joinToString(", ")
        if (sellerAddress.isNotBlank()) line(sellerAddress, textPaint, 14f, colLeftX)
        if (seller.nip.isNotBlank()) line("${l.nip}: ${seller.nip}", textPaint, 14f, colLeftX)
        if (seller.bankAccount.isNotBlank()) line("${l.bankAccount}: ${seller.bankAccount}", textPaint, 14f, colLeftX)
        val leftBottomY = y

        y = blockTopY
        line(l.buyer, sectionPaint, 17f, colRightX)
        line(buyerName, textPaint, 14f, colRightX)
        val buyerAddress = listOfNotNull(
            buyerStreet.ifBlank { null },
            listOf(buyerPostalCode, buyerCity).filter { it.isNotBlank() }.joinToString(" ").ifBlank { null }
        ).joinToString(", ")
        if (buyerAddress.isNotBlank()) line(buyerAddress, textPaint, 14f, colRightX)
        if (!isPhysicalPerson && !buyerNip.isNullOrBlank()) {
            line("${l.nip}: $buyerNip", textPaint, 14f, colRightX)
        } else {
            wrappedLines(l.buyerPrivate, 46, hintPaint, 12f, colRightX)
        }
        val rightBottomY = y

        y = maxOf(leftBottomY, rightBottomY) + 18f

        // --- Tabela pozycji ---
        val tableLeft = MARGIN
        val tableRight = PAGE_WIDTH - MARGIN
        val tableWidth = tableRight - tableLeft
        val colLp = tableLeft
        val colName = colLp + 28f
        val colUnit = colName + 232f
        val colQty = colUnit + 46f
        val colPrice = colQty + 46f
        val colTotal = colPrice + 72f
        val colStops = floatArrayOf(colLp, colName, colUnit, colQty, colPrice, colTotal, tableRight)

        newPageIfNeeded(70f)
        val headerRowTop = y - 10f
        val headerRowHeight = 20f
        canvas.drawRect(tableLeft, headerRowTop, tableRight, headerRowTop + headerRowHeight, headerFillPaint)
        val headerBaselineY = headerRowTop + headerRowHeight - 6f
        canvas.drawText(l.tableLp, colLp + 4f, headerBaselineY, tableHeaderPaint)
        canvas.drawText(l.tableName, colName + 4f, headerBaselineY, tableHeaderPaint)
        canvas.drawText(l.tableUnit, colUnit + 4f, headerBaselineY, tableHeaderPaint)
        canvas.drawText(l.tableQty, colQty + 4f, headerBaselineY, tableHeaderPaint)
        canvas.drawText(l.tablePrice, colPrice + 4f, headerBaselineY, tableHeaderPaint)
        canvas.drawText(l.tableTotal, colTotal + 4f, headerBaselineY, tableHeaderPaint)

        val dataRowTop = headerRowTop + headerRowHeight
        val dataRowHeight = 22f
        val dataBaselineY = dataRowTop + dataRowHeight - 7f
        canvas.drawText("1", colLp + 4f, dataBaselineY, tableCellPaint)
        canvas.drawText(serviceName.take(38), colName + 4f, dataBaselineY, tableCellPaint)
        canvas.drawText(l.unitPiece, colUnit + 4f, dataBaselineY, tableCellPaint)
        canvas.drawText("1", colQty + 4f, dataBaselineY, tableCellPaint)
        canvas.drawText(money(amount), colPrice + 4f, dataBaselineY, tableCellPaint)
        canvas.drawText(money(amount), colTotal + 4f, dataBaselineY, tableCellPaint)

        val totalRowTop = dataRowTop + dataRowHeight
        val totalRowHeight = 22f
        val totalBaselineY = totalRowTop + totalRowHeight - 7f
        canvas.drawText(l.sumLabel + ":", colPrice - 60f, totalBaselineY, sectionPaint)
        canvas.drawText(money(amount), colTotal + 4f, totalBaselineY, sectionPaint)

        val tableBottom = totalRowTop + totalRowHeight
        // Obramowanie tabeli i linii kolumn/wierszy.
        canvas.drawRect(tableLeft, headerRowTop, tableRight, tableBottom, linePaint.apply { style = Paint.Style.STROKE })
        canvas.drawLine(tableLeft, dataRowTop, tableRight, dataRowTop, linePaint)
        canvas.drawLine(tableLeft, totalRowTop, tableRight, totalRowTop, linePaint)
        for (i in 1 until colStops.size - 1) {
            canvas.drawLine(colStops[i], headerRowTop, colStops[i], totalRowTop, linePaint)
        }

        y = tableBottom + 26f

        // --- Status płatności / pieczątka ---
        newPageIfNeeded(40f)
        line("${l.paymentDateLabel}: ${dateFmt.format(Date(paymentDateMillis))}", textPaint, 16f)
        line(l.paymentStatusLine, textPaint, 20f)
        canvas.drawText("✓ ${l.paidStamp}", tableRight - 130f, y - 4f, stampPaint)
        y += 4f

        // --- Stopka ---
        y += 14f
        newPageIfNeeded(40f)
        wrappedLines(l.footer, 96, hintPaint, 12f)

        document.finishPage(page)
        document.writeTo(out)
        document.close()
    }
}
