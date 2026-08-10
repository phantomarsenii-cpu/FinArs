package com.example.fa_ksiegowy

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Paint
import android.graphics.RectF
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
 *
 * Update 49: wygląd dopasowany do kolorystyki aplikacji (accent_blue_dark /
 * accent_cyan z colors.xml), logo rysowane z pełnej rozdzielczości źródła
 * (bez ręcznego pomniejszania bitmapy — ostrzejszy druk), naprawiona tabela
 * VAT (kolumny nie nachodzą już na siebie, osobne etykiety "Cena netto" i
 * "Wartość netto"), numer dokumentu w formacie Numer/MM/RRRR, oraz poprawiony
 * opis przełącznika paragonu ("faktura do paragonu", nie "faktura jako paragon").
 */
object InvoicePdfGenerator {

    private const val PAGE_WIDTH = 595
    private const val PAGE_HEIGHT = 842
    private const val MARGIN = 48f

    // Paleta zgodna z app/src/main/res/values/colors.xml (accent_blue_dark,
    // accent_cyan, card_bg) — dokument ma być wizualnie spójny z aplikacją.
    private const val COLOR_TEXT = 0xFF12162E.toInt()
    private const val COLOR_ACCENT = 0xFF1230A8.toInt()
    private const val COLOR_ACCENT_LIGHT = 0xFF29B6F6.toInt()
    private const val COLOR_HEADER_FILL = 0xFFE9F2FE.toInt()
    private const val COLOR_ROW_ALT = 0xFFF6F9FE.toInt()
    private const val COLOR_HINT = 0xFF6B7094.toInt()
    private const val COLOR_GRID = 0xFFC7D3E8.toInt()

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
        val tablePriceNetto: String,
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
        tablePriceNetto = context.getString(R.string.invoice_pdf_table_price_netto),
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
        // niezależnie od rodzaju działalności. Dekodujemy bez przeskalowania
        // przez system (inScaled = false) i rysujemy bezpośrednio w docelowy
        // prostokąt przez drawBitmap(src, dst) — bez ręcznego tworzenia małej
        // kopii bitmapy (createScaledBitmap dawało rozmyty, "pikselowy" wydruk).
        val logoBitmap: Bitmap? = try {
            val opts = BitmapFactory.Options().apply { inScaled = false }
            BitmapFactory.decodeResource(context.resources, R.drawable.logo, opts)
        } catch (e: Exception) {
            null
        }
        val logoPaint = Paint().apply { isAntiAlias = true; isFilterBitmap = true }
        val topBarPaint = Paint().apply { color = COLOR_ACCENT }
        fun drawTopBar() {
            canvas.drawRect(0f, 0f, PAGE_WIDTH.toFloat(), 5f, topBarPaint)
        }
        fun drawLogo() {
            drawTopBar()
            if (logoBitmap == null) return
            val logoSize = 52f
            val left = PAGE_WIDTH - MARGIN - logoSize
            val top = MARGIN - 24f
            val dst = RectF(left, top, left + logoSize, top + logoSize)
            canvas.drawBitmap(logoBitmap, null, dst, logoPaint)
        }
        drawLogo()

        val titlePaint = Paint().apply { color = COLOR_ACCENT; textSize = 20f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val sectionPaint = Paint().apply { color = COLOR_ACCENT; textSize = 11.5f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val textPaint = Paint().apply { color = COLOR_TEXT; textSize = 10.5f; isAntiAlias = true }
        val hintPaint = Paint().apply { color = COLOR_HINT; textSize = 9f; isAntiAlias = true }
        val tableHeaderPaint = Paint().apply { color = COLOR_ACCENT; textSize = 9.5f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val tableCellPaint = Paint().apply { color = COLOR_TEXT; textSize = 10f; isAntiAlias = true }
        val stampPaint = Paint().apply { color = 0xFF1B7F3C.toInt(); textSize = 13f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val pendingStampPaint = Paint().apply { color = 0xFFCC6A00.toInt(); textSize = 13f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val linePaint = Paint().apply { color = COLOR_GRID; strokeWidth = 0.75f; isAntiAlias = true }
        val headerFillPaint = Paint().apply { color = COLOR_HEADER_FILL }
        val rowAltPaint = Paint().apply { color = COLOR_ROW_ALT }
        val accentLinePaint = Paint().apply { color = COLOR_ACCENT_LIGHT; strokeWidth = 1.3f; isAntiAlias = true }
        val receiptBadgePaint = Paint().apply { color = COLOR_ACCENT; textSize = 9.5f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }

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
        val numberFmt = SimpleDateFormat("MM/yyyy", Locale.US)

        // --- Nagłówek: "FAKTURA VAT 3/08/2026" / "RACHUNEK 3/08/2026" —
        // numer dokumentu w formacie Numer/Miesiąc/Rok, tak jak w oficjalnych
        // wzorach faktur (zob. treść zgłoszenia funkcji, przykładowe zdjęcie). ---
        val formattedNumber = "$invoiceNumber/${numberFmt.format(Date(issueDateMillis))}"
        val vatSuffix = if (isVatPayer) " VAT" else ""
        val titleText = "${l.docKind}$vatSuffix $formattedNumber"
        line(titleText, titlePaint, 24f)
        val titleUnderlineY = y - 24f + 6f
        canvas.drawLine(MARGIN, titleUnderlineY, MARGIN + titlePaint.measureText(titleText), titleUnderlineY, accentLinePaint)
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

        // Список строк таблицы: если переданы позиции склада — по строке на каждую
        // (с реальным количеством), иначе — одна строка на всю сумму (как раньше,
        // для счетов без привязки к складу).
        data class Row(val name: String, val qty: Double, val unitPrice: Double)
        val rows: List<Row> = if (items.isNotEmpty()) items.map { Row(it.name, it.quantity, it.unitPrice) }
            else listOf(Row(serviceName, 1.0, amount))
        val totalAmount = rows.sumOf { it.qty * it.unitPrice }

        val headerRowHeight = if (vatRate != null) 24f else 20f
        val dataRowHeight = 22f
        val totalRowHeight = 22f

        newPageIfNeeded(70f)
        var segmentTop = y - 10f

        /** Rysuje treść nagłówka kolumny — jeśli tekst nie mieści się w szerokości
         *  kolumny, a zawiera spację, dzieli go na dwie linie (np. "Stawka VAT"
         *  -> "Stawka" / "VAT"). Zapobiega nachodzeniu nagłówków wąskich kolumn
         *  na sąsiednie kolumny (błąd zgłoszony w update 49). */
        fun drawHeaderCell(text: String, x: Float, colWidth: Float, paint: Paint, top: Float, rowHeight: Float) {
            val available = colWidth - 6f
            if (paint.measureText(text) <= available || !text.contains(" ")) {
                canvas.drawText(text, x + 3f, top + rowHeight - 6f, paint)
            } else {
                val words = text.split(" ")
                val line1 = words.first()
                val line2 = words.drop(1).joinToString(" ")
                canvas.drawText(line1, x + 3f, top + rowHeight / 2f - 1f, paint)
                canvas.drawText(line2, x + 3f, top + rowHeight - 4f, paint)
            }
        }

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
                val borderPaint = Paint(linePaint).apply { style = Paint.Style.STROKE; color = COLOR_ACCENT; strokeWidth = 1f }
                canvas.drawRect(tableLeft, segmentTop, tableRight, y, borderPaint)
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
                if (idx % 2 == 1) canvas.drawRect(tableLeft, y, tableRight, y + dataRowHeight, rowAltPaint)
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
            canvas.drawRect(tableLeft, totalRowTop, tableRight, totalRowTop + totalRowHeight, headerFillPaint)
            val totalBaselineY = totalRowTop + totalRowHeight - 7f
            canvas.drawText(l.sumLabel + ":", colPrice - 60f, totalBaselineY, sectionPaint)
            canvas.drawText(money(totalAmount), colTotal + 4f, totalBaselineY, sectionPaint)
            y = totalRowTop + totalRowHeight
            closeSegment(gridBottom)
        } else {
            // --- Tabela VAT (sprzedawca zarejestrowany jako podatnik VAT) —
            // Lp / Nazwa / Jm. / Ilość / Cena netto / Wartość netto / Stawka VAT /
            // Kwota VAT / Wartość brutto, zgodnie z oficjalnym wzorem faktury VAT.
            // Szerokości kolumn dobrane proporcjonalnie do typowego wzoru (mm),
            // żeby żaden nagłówek/wartość nie nachodził na sąsiednią kolumnę —
            // wcześniej kolumna "Stawka VAT" miała zaledwie 34pt szerokości, co
            // powodowało nakładanie się tekstu (błąd zgłoszony w update 49).
            val vatCellPaint = Paint(tableCellPaint).apply { textSize = 8.3f }
            val vatHeaderPaint = Paint(tableHeaderPaint).apply { textSize = 7.6f }
            val vatMoney: (Double) -> String = { String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") }

            val colLp = tableLeft
            val colName = colLp + 23f
            val colUnit = colName + 142f
            val colQty = colUnit + 28f
            val colNetPrice = colQty + 34f
            val colNetValue = colNetPrice + 57f
            val colVatRateCol = colNetValue + 57f
            val colVatAmount = colVatRateCol + 40f
            val colBrutto = colVatAmount + 57f
            val colStops = floatArrayOf(colLp, colName, colUnit, colQty, colNetPrice, colNetValue, colVatRateCol, colVatAmount, colBrutto, tableRight)
            val colWidths = FloatArray(colStops.size - 1) { i -> colStops[i + 1] - colStops[i] }

            fun drawHeaderRow() {
                canvas.drawRect(tableLeft, segmentTop, tableRight, segmentTop + headerRowHeight, headerFillPaint)
                drawHeaderCell(l.tableLp, colLp, colWidths[0], vatHeaderPaint, segmentTop, headerRowHeight)
                drawHeaderCell(l.tableName, colName, colWidths[1], vatHeaderPaint, segmentTop, headerRowHeight)
                drawHeaderCell(l.tableUnit, colUnit, colWidths[2], vatHeaderPaint, segmentTop, headerRowHeight)
                drawHeaderCell(l.tableQty, colQty, colWidths[3], vatHeaderPaint, segmentTop, headerRowHeight)
                drawHeaderCell(l.tablePriceNetto, colNetPrice, colWidths[4], vatHeaderPaint, segmentTop, headerRowHeight)
                drawHeaderCell(l.tableNetto, colNetValue, colWidths[5], vatHeaderPaint, segmentTop, headerRowHeight)
                drawHeaderCell(l.tableVatRate, colVatRateCol, colWidths[6], vatHeaderPaint, segmentTop, headerRowHeight)
                drawHeaderCell(l.tableVatAmount, colVatAmount, colWidths[7], vatHeaderPaint, segmentTop, headerRowHeight)
                drawHeaderCell(l.tableBrutto, colBrutto, colWidths[8], vatHeaderPaint, segmentTop, headerRowHeight)
                y = segmentTop + headerRowHeight
                canvas.drawLine(tableLeft, y, tableRight, y, linePaint)
            }

            fun closeSegment(colLinesBottom: Float) {
                val borderPaint = Paint(linePaint).apply { style = Paint.Style.STROKE; color = COLOR_ACCENT; strokeWidth = 1f }
                canvas.drawRect(tableLeft, segmentTop, tableRight, y, borderPaint)
                for (i in 1 until colStops.size - 1) {
                    canvas.drawLine(colStops[i], segmentTop, colStops[i], colLinesBottom, linePaint)
                }
            }

            // Krótki zapis stawki w komórce danych — pełny opisowy label (np.
            // "23% (podstawowa)") jest za długi na wąską kolumnę, w komórce
            // pokazujemy tylko wartość liczbową ("23%"), a pełny opis jest już
            // czytelny w wyborze stawki w aplikacji.
            val vatRateShort: String = vatRate.percent?.let { p ->
                val asInt = p.toInt()
                if (asInt.toDouble() == p) "$asInt%" else "$p%"
            } ?: vatRate.storageKey

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

                if (idx % 2 == 1) canvas.drawRect(tableLeft, y, tableRight, y + dataRowHeight, rowAltPaint)
                val baselineY = y + dataRowHeight - 7f
                canvas.drawText((idx + 1).toString(), colLp + 3f, baselineY, vatCellPaint)
                canvas.drawText(row.name.take(22), colName + 3f, baselineY, vatCellPaint)
                canvas.drawText(l.unitPiece, colUnit + 3f, baselineY, vatCellPaint)
                canvas.drawText(qtyStr(row.qty), colQty + 3f, baselineY, vatCellPaint)
                canvas.drawText(vatMoney(row.unitPrice), colNetPrice + 3f, baselineY, vatCellPaint)
                canvas.drawText(vatMoney(netValue), colNetValue + 3f, baselineY, vatCellPaint)
                canvas.drawText(vatRateShort, colVatRateCol + 3f, baselineY, vatCellPaint)
                canvas.drawText(vatMoney(vatAmount), colVatAmount + 3f, baselineY, vatCellPaint)
                canvas.drawText(vatMoney(bruttoValue), colBrutto + 3f, baselineY, vatCellPaint)
                y += dataRowHeight
                canvas.drawLine(tableLeft, y, tableRight, y, linePaint)
            }

            val gridBottom = y
            val totalRowTop = y
            canvas.drawRect(tableLeft, totalRowTop, tableRight, totalRowTop + totalRowHeight, headerFillPaint)
            val totalBaselineY = totalRowTop + totalRowHeight - 7f
            canvas.drawText(l.sumLabel + ":", colNetPrice, totalBaselineY, Paint(sectionPaint).apply { textSize = 9f })
            canvas.drawText(vatMoney(totalAmount), colNetValue + 3f, totalBaselineY, Paint(tableCellPaint).apply { textSize = 9f })
            canvas.drawText(vatMoney(vatSum), colVatAmount + 3f, totalBaselineY, Paint(tableCellPaint).apply { textSize = 9f })
            canvas.drawText(vatMoney(bruttoSum), colBrutto + 3f, totalBaselineY, Paint(tableCellPaint).apply { textSize = 9f })
            y = totalRowTop + totalRowHeight
            closeSegment(gridBottom)
        }

        y += 26f

        if (isReceipt) {
            newPageIfNeeded(18f)
            canvas.drawText("● ${l.receiptLabel}", MARGIN, y, receiptBadgePaint)
            y += 18f
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
