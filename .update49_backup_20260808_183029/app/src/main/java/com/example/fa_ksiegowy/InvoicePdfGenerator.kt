package com.example.fa_ksiegowy

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Paint
import android.graphics.Rect
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
 * i pieczątką statusu płatności ("ZAPŁACONO" dla opłaconych, "OCZEKUJE NA
 * ZAPŁATĘ" + termin płatności dla nieopłaconych — patrz [InvoiceStatus]).
 * Wszystkie etykiety pochodzą z zasobów string — dokument jest w pełni w
 * języku aktualnie wybranym w aplikacji (kontekst przekazywany przez
 * wywołującego musi mieć już zastosowaną lokalizację, patrz
 * [BaseActivity]/[LocaleHelper] — nie używamy tu applicationContext).
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
        val pendingStamp: String,
        val paymentDateLabel: String,
        val dueDateLabel: String,
        val paymentMethodLabel: String,
        val paymentStatusLine: String,
        val tableNetto: String,
        val tableVatRate: String,
        val tableVatAmount: String,
        val tableBrutto: String,
        val receiptLabel: String
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
        pendingStamp = context.getString(R.string.invoice_pdf_pending_stamp),
        paymentDateLabel = context.getString(R.string.invoice_pdf_payment_date),
        dueDateLabel = context.getString(R.string.invoice_due_date_label),
        paymentMethodLabel = context.getString(R.string.payment_method_label),
        paymentStatusLine = context.getString(paymentMethod.paidLabelResId),
        tableNetto = context.getString(R.string.invoice_pdf_table_netto),
        tableVatRate = context.getString(R.string.invoice_pdf_table_vat_rate),
        tableVatAmount = context.getString(R.string.invoice_pdf_table_vat_amount),
        tableBrutto = context.getString(R.string.invoice_pdf_table_brutto),
        receiptLabel = context.getString(R.string.invoice_pdf_receipt_label)
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
        invoiceStatus: InvoiceStatus = InvoiceStatus.PAID,
        dueDateMillis: Long? = null,
        /** Позиции склада, выбранные для этой фактуры — если не пусто, таблица PDF
         *  рисует отдельную строку на каждую позицию (с реальным количеством) вместо
         *  одной строки на всю сумму. Если пусто — поведение как раньше: одна строка
         *  из serviceName/amount (ручной ввод без склада). */
        items: List<InvoiceItem> = emptyList(),
        /** Stawka VAT wybrana przy wystawianiu — niepusta tylko dla sprzedawców już
         *  zarejestrowanych jako podatnicy VAT (zob. VatComplianceHelper). Gdy podana,
         *  tabela pozycji pokazuje dodatkowo Cenę/Wartość netto, Stawkę VAT, Kwotę VAT
         *  i Wartość brutto (jak w oficjalnym wzorze faktury VAT), a kwota końcowa jest
         *  liczona brutto (netto + VAT). */
        vatRate: VatRate? = null,
        /** true, jeśli faktura jest jednocześnie wystawiana "do paragonu" z kasy fiskalnej. */
        isReceipt: Boolean = false,
        out: OutputStream
    ) {
        val isVatPayer = seller.nip.isNotBlank()
        val l = buildLabels(context, isVatPayer, paymentMethod)

        val document = PdfDocument()
        var pageNumber = 1
        var page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
        var canvas = page.canvas

        // Logo aplikacji w prawym górnym rogu — na KAŻDEJ wystawionej fakturze,
        // niezależnie od rodzaju działalności (zob. treść zgłoszenia funkcji).
        val logoBitmap: Bitmap? = try {
            BitmapFactory.decodeResource(context.resources, R.drawable.logo)
        } catch (e: Exception) {
            null
        }
        fun drawLogo() {
            if (logoBitmap == null) return
            val logoSize = 46f
            val scaled = Bitmap.createScaledBitmap(logoBitmap, logoSize.toInt(), logoSize.toInt(), true)
            canvas.drawBitmap(scaled, PAGE_WIDTH - MARGIN - logoSize, MARGIN - 20f, null)
        }
        drawLogo()

        val titlePaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 20f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val sectionPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 11.5f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val textPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 10.5f; isAntiAlias = true }
        val hintPaint = Paint().apply { color = 0xFF555555.toInt(); textSize = 9f; isAntiAlias = true }
        val tableHeaderPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 9.5f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val tableCellPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 10f; isAntiAlias = true }
        val stampPaint = Paint().apply { color = 0xFF1B7F3C.toInt(); textSize = 13f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val pendingStampPaint = Paint().apply { color = 0xFFCC6A00.toInt(); textSize = 13f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
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
                drawLogo()
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
        val qtyStr: (Double) -> String = { q -> if (q == q.toLong().toDouble()) q.toLong().toString() else q.toString() }
        val vatLabel: String = vatRate?.let { context.getString(it.labelResId) } ?: ""

        // Список строк таблицы: если переданы позиции склада — по строке на каждую
        // (с реальным количеством), иначе — одна строка на всю сумму (как раньше,
        // для счетов без привязки к складу).
        data class Row(val name: String, val qty: Double, val unitPrice: Double)
        val rows: List<Row> = if (items.isNotEmpty()) items.map { Row(it.name, it.quantity, it.unitPrice) }
            else listOf(Row(serviceName, 1.0, amount))
        val totalAmount = rows.sumOf { it.qty * it.unitPrice }

        val headerRowHeight = 20f
        val dataRowHeight = 22f
        val totalRowHeight = 22f

        newPageIfNeeded(70f)
        var segmentTop = y - 10f

        if (vatRate == null) {
            // --- Tabela bez VAT (zwolnienie podmiotowe / rachunek) — jak dotychczas. ---
            val colLp = tableLeft
            val colName = colLp + 28f
            val colUnit = colName + 232f
            val colQty = colUnit + 46f
            val colPrice = colQty + 46f
            val colTotal = colPrice + 72f
            val colStops = floatArrayOf(colLp, colName, colUnit, colQty, colPrice, colTotal, tableRight)

            fun drawHeaderRow() {
                canvas.drawRect(tableLeft, segmentTop, tableRight, segmentTop + headerRowHeight, headerFillPaint)
                val headerBaselineY = segmentTop + headerRowHeight - 6f
                canvas.drawText(l.tableLp, colLp + 4f, headerBaselineY, tableHeaderPaint)
                canvas.drawText(l.tableName, colName + 4f, headerBaselineY, tableHeaderPaint)
                canvas.drawText(l.tableUnit, colUnit + 4f, headerBaselineY, tableHeaderPaint)
                canvas.drawText(l.tableQty, colQty + 4f, headerBaselineY, tableHeaderPaint)
                canvas.drawText(l.tablePrice, colPrice + 4f, headerBaselineY, tableHeaderPaint)
                canvas.drawText(l.tableTotal, colTotal + 4f, headerBaselineY, tableHeaderPaint)
                y = segmentTop + headerRowHeight
                canvas.drawLine(tableLeft, y, tableRight, y, linePaint)
            }

            fun closeSegment(colLinesBottom: Float) {
                canvas.drawRect(tableLeft, segmentTop, tableRight, y, linePaint.apply { style = Paint.Style.STROKE })
                for (i in 1 until colStops.size - 1) {
                    canvas.drawLine(colStops[i], segmentTop, colStops[i], colLinesBottom, linePaint)
                }
            }

            drawHeaderRow()
            for ((idx, row) in rows.withIndex()) {
                // Оставляем место под итоговую строку на этой же странице — если не
                // помещается, закрываем таблицу на текущей странице и продолжаем с
                // новым заголовком на следующей (для счетов с большим числом позиций).
                if (y + dataRowHeight + totalRowHeight > PAGE_HEIGHT - MARGIN) {
                    closeSegment(y)
                    document.finishPage(page)
                    pageNumber++
                    page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
                    canvas = page.canvas
                    y = MARGIN
                    drawLogo()
                    segmentTop = y - 10f
                    drawHeaderRow()
                }
                val baselineY = y + dataRowHeight - 7f
                canvas.drawText((idx + 1).toString(), colLp + 4f, baselineY, tableCellPaint)
                canvas.drawText(row.name.take(38), colName + 4f, baselineY, tableCellPaint)
                canvas.drawText(l.unitPiece, colUnit + 4f, baselineY, tableCellPaint)
                canvas.drawText(qtyStr(row.qty), colQty + 4f, baselineY, tableCellPaint)
                canvas.drawText(money(row.unitPrice), colPrice + 4f, baselineY, tableCellPaint)
                canvas.drawText(money(row.qty * row.unitPrice), colTotal + 4f, baselineY, tableCellPaint)
                y += dataRowHeight
                canvas.drawLine(tableLeft, y, tableRight, y, linePaint)
            }

            val gridBottom = y
            val totalRowTop = y
            val totalBaselineY = totalRowTop + totalRowHeight - 7f
            canvas.drawText(l.sumLabel + ":", colPrice - 60f, totalBaselineY, sectionPaint)
            canvas.drawText(money(totalAmount), colTotal + 4f, totalBaselineY, sectionPaint)
            y = totalRowTop + totalRowHeight
            closeSegment(gridBottom)
        } else {
            // --- Tabela VAT (sprzedawca zarejestrowany jako podatnik VAT) —
            // Lp / Nazwa / Jm. / Ilość / Cena netto / Wartość netto / Stawka VAT /
            // Kwota VAT / Wartość brutto, zgodnie z oficjalnym wzorem faktury VAT.
            // Kolumny są węższe niż w wariancie bez VAT (mniejsza czcionka),
            // żeby wszystkie dziewięć kolumn zmieściło się na szerokości strony A4.
            val vatCellPaint = Paint(tableCellPaint).apply { textSize = 8.5f }
            val vatHeaderPaint = Paint(tableHeaderPaint).apply { textSize = 8f }
            val vatMoney: (Double) -> String = { String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") }

            val colLp = tableLeft
            val colName = colLp + 22f
            val colUnit = colName + 132f
            val colQty = colUnit + 28f
            val colNetPrice = colQty + 30f
            val colNetValue = colNetPrice + 58f
            val colVatRateCol = colNetValue + 58f
            val colVatAmount = colVatRateCol + 34f
            val colBrutto = colVatAmount + 58f
            val colStops = floatArrayOf(colLp, colName, colUnit, colQty, colNetPrice, colNetValue, colVatRateCol, colVatAmount, colBrutto, tableRight)

            fun drawHeaderRow() {
                canvas.drawRect(tableLeft, segmentTop, tableRight, segmentTop + headerRowHeight, headerFillPaint)
                val headerBaselineY = segmentTop + headerRowHeight - 6f
                canvas.drawText(l.tableLp, colLp + 3f, headerBaselineY, vatHeaderPaint)
                canvas.drawText(l.tableName, colName + 3f, headerBaselineY, vatHeaderPaint)
                canvas.drawText(l.tableUnit, colUnit + 3f, headerBaselineY, vatHeaderPaint)
                canvas.drawText(l.tableQty, colQty + 3f, headerBaselineY, vatHeaderPaint)
                canvas.drawText(l.tableNetto, colNetPrice + 3f, headerBaselineY, vatHeaderPaint)
                canvas.drawText(l.tableNetto, colNetValue + 3f, headerBaselineY, vatHeaderPaint)
                canvas.drawText(l.tableVatRate, colVatRateCol + 3f, headerBaselineY, vatHeaderPaint)
                canvas.drawText(l.tableVatAmount, colVatAmount + 3f, headerBaselineY, vatHeaderPaint)
                canvas.drawText(l.tableBrutto, colBrutto + 3f, headerBaselineY, vatHeaderPaint)
                y = segmentTop + headerRowHeight
                canvas.drawLine(tableLeft, y, tableRight, y, linePaint)
            }

            fun closeSegment(colLinesBottom: Float) {
                canvas.drawRect(tableLeft, segmentTop, tableRight, y, linePaint.apply { style = Paint.Style.STROKE })
                for (i in 1 until colStops.size - 1) {
                    canvas.drawLine(colStops[i], segmentTop, colStops[i], colLinesBottom, linePaint)
                }
            }

            drawHeaderRow()
            var vatSum = 0.0
            var bruttoSum = 0.0
            for ((idx, row) in rows.withIndex()) {
                if (y + dataRowHeight + totalRowHeight > PAGE_HEIGHT - MARGIN) {
                    closeSegment(y)
                    document.finishPage(page)
                    pageNumber++
                    page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
                    canvas = page.canvas
                    y = MARGIN
                    drawLogo()
                    segmentTop = y - 10f
                    drawHeaderRow()
                }
                val netValue = row.qty * row.unitPrice
                val vatAmount = vatRate.vatAmount(netValue)
                val bruttoValue = netValue + vatAmount
                vatSum += vatAmount
                bruttoSum += bruttoValue

                val baselineY = y + dataRowHeight - 7f
                canvas.drawText((idx + 1).toString(), colLp + 3f, baselineY, vatCellPaint)
                canvas.drawText(row.name.take(20), colName + 3f, baselineY, vatCellPaint)
                canvas.drawText(l.unitPiece, colUnit + 3f, baselineY, vatCellPaint)
                canvas.drawText(qtyStr(row.qty), colQty + 3f, baselineY, vatCellPaint)
                canvas.drawText(vatMoney(row.unitPrice), colNetPrice + 3f, baselineY, vatCellPaint)
                canvas.drawText(vatMoney(netValue), colNetValue + 3f, baselineY, vatCellPaint)
                canvas.drawText(vatLabel + "%".takeIf { vatRate.percent != null }.orEmpty(), colVatRateCol + 3f, baselineY, vatCellPaint)
                canvas.drawText(vatMoney(vatAmount), colVatAmount + 3f, baselineY, vatCellPaint)
                canvas.drawText(vatMoney(bruttoValue), colBrutto + 3f, baselineY, vatCellPaint)
                y += dataRowHeight
                canvas.drawLine(tableLeft, y, tableRight, y, linePaint)
            }

            val gridBottom = y
            val totalRowTop = y
            val totalBaselineY = totalRowTop + totalRowHeight - 7f
            canvas.drawText(l.sumLabel + ":", colNetPrice, totalBaselineY, sectionPaint)
            canvas.drawText(vatMoney(totalAmount), colNetValue + 3f, totalBaselineY, tableCellPaint.apply { textSize = 9f })
            canvas.drawText(vatMoney(vatSum), colVatAmount + 3f, totalBaselineY, tableCellPaint.apply { textSize = 9f })
            canvas.drawText(vatMoney(bruttoSum), colBrutto + 3f, totalBaselineY, tableCellPaint.apply { textSize = 9f })
            y = totalRowTop + totalRowHeight
            closeSegment(gridBottom)
        }

        y += 26f

        if (isReceipt) {
            line(l.receiptLabel, hintPaint, 16f)
        }

        // --- Status płatności / pieczątka ---
        // Dokument musi wiernie odzwierciedlać rzeczywisty status faktury:
        // dla PAID pokazujemy datę zapłaty i pieczątkę "ZAPŁACONO", a dla
        // PENDING — termin płatności i pieczątkę "OCZEKUJE NA ZAPŁATĘ".
        // Wcześniej PDF zawsze pokazywał "ZAPŁACONO" niezależnie od
        // rzeczywistego statusu faktury — to był błąd.
        newPageIfNeeded(40f)
        if (invoiceStatus == InvoiceStatus.PAID) {
            line("${l.paymentDateLabel}: ${dateFmt.format(Date(paymentDateMillis))}", textPaint, 16f)
            line(l.paymentStatusLine, textPaint, 20f)
            val stampText = "✓ ${l.paidStamp}"
            canvas.drawText(stampText, tableRight - stampPaint.measureText(stampText), y - 4f, stampPaint)
        } else {
            val due = dueDateMillis ?: paymentDateMillis
            line("${l.dueDateLabel}: ${dateFmt.format(Date(due))}", textPaint, 16f)
            line("${l.paymentMethodLabel}: ${context.getString(paymentMethod.labelResId)}", textPaint, 20f)
            val stampText = "⏳ ${l.pendingStamp}"
            canvas.drawText(stampText, tableRight - pendingStampPaint.measureText(stampText), y - 4f, pendingStampPaint)
        }
        y += 4f

        document.finishPage(page)
        document.writeTo(out)
        document.close()
    }
}

