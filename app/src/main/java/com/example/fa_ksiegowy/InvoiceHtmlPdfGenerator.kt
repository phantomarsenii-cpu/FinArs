package com.example.fa_ksiegowy

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.coroutines.resume

/**
 * Generuje PDF fatur/korekt na podstawie assets/invoice_template.html (pixel-perfect
 * wzór dostarczony przez użytkownika), renderowany przez ukryty WebView. PDF budowany jest
 * z jednego długiego zrzutu Bitmapy całego dokumentu, ciętego ręcznie na strony A4 —
 * android.print.PrintDocumentAdapter NIE jest tu używany (jego LayoutResultCallback/
 * WriteResultCallback mają konstruktory package-private i nie da się ich podklasować spoza
 * pakietu android.print — to twardy limit kompilatora, nie coś do obejścia).
 *
 * Zamiennik dla InvoicePdfGenerator (rysowanie na Canvas) — ten sam zestaw parametrów
 * wejściowych i ta sama logika biznesowa (pozycje, VAT, korekta), inny silnik renderowania.
 * WAŻNE: WebView musi być tworzony i obsługiwany na wątku głównym — dlatego generate()/
 * generateCorrection() są funkcjami suspend, które same przełączają się na
 * Dispatchers.Main tylko na czas renderowania, i zwracają gotowe bajty PDF (do zapisania
 * przez wywołującego, tak jak dotychczas, przez InvoiceFileStorage).
 */
object InvoiceHtmlPdfGenerator {

    private const val TEMPLATE_ASSET = "invoice_template.html"

    // --- Kolory zgodne z InvoicePdfGenerator / colors.xml, używane też w SVG ikonach ---
    private const val ICON_WHITE = "#FFFFFF"

    // Update 63: Row ma teraz WLASNA stawke VAT (wczesniej jedna stawka byla wspolna dla
    // calej faktury) — rozne pozycje moga miec rozne stawki (towar 23%, ksiazka 5% itd.),
    // dokladnie jak w prawdziwej fakturze VAT z wieloma stawkami na jednym dokumencie.
    private data class Row(val name: String, val qty: Double, val unitPrice: Double, val vatRate: VatRate? = null)

    // ============================= PUBLICZNE API =============================

    suspend fun generate(
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
        items: List<InvoiceItem> = emptyList(),
        vatRate: VatRate? = null,
        isReceipt: Boolean = false
    ): ByteArray {
        val isVatPayer = seller.nip.isNotBlank()
        val dateFmt = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())
        val numberFmt = SimpleDateFormat("MM/yyyy", Locale.US)

        // Update 63: kazda pozycja ma teraz WLASNA stawke VAT (InvoiceItem.vatRate) —
        // rozne towary/uslugi na jednej fakturze moga byc opodatkowane roznymi stawkami.
        // Parametr vatRate ponizej to juz tylko FALLBACK dla przypadku brzegowego (items
        // puste, pojedyncza pozycja z serviceName/amount) — w normalnym przebiegu (zawsze,
        // patrz AddInvoiceActivity) items nie jest puste.
        val rows: List<Row> = if (items.isNotEmpty()) items.map { Row(it.name, it.quantity, it.unitPrice, VatRate.fromStorageKeyOrNull(it.vatRate)) }
            else listOf(Row(serviceName, 1.0, amount, vatRate))
        val netTotal = rows.sumOf { it.qty * it.unitPrice }
        val vatTotal = rows.sumOf { row -> row.vatRate?.vatAmount(row.qty * row.unitPrice) ?: 0.0 }

        val formattedNumber = "$invoiceNumber/${numberFmt.format(Date(issueDateMillis))}"
        val vatSuffix = if (isVatPayer) " VAT" else ""
        val docKind = context.getString(R.string.invoice_pdf_faktura)
        val docTitle = "$docKind$vatSuffix $formattedNumber"

        val datesHtml = "<div>${context.getString(R.string.invoice_pdf_issue_date)}: ${dateFmt.format(Date(issueDateMillis))}</div>" +
            "<div>${context.getString(R.string.invoice_pdf_sale_date)}: ${dateFmt.format(Date(serviceDateMillis))}</div>"

        val sellerHtml = buildSellerBody(context, seller, isVatPayer)
        val buyerHtml = buildBuyerBody(context, buyerName, buyerNip, buyerStreet, buyerPostalCode, buyerCity, isPhysicalPerson)

        val itemsTableHtml = "<div class=\"table-with-total\">" +
            buildItemsTable(context, null, rows) +
            buildSumRow(context, netTotal, vatTotal, rows.any { it.vatRate != null }) +
            "</div>"

        val receiptBadge = if (isReceipt)
            "<div style=\"color:#1230A8;font-weight:700;font-size:8.5pt;margin-bottom:3mm;\">&#9679; ${esc(context.getString(R.string.invoice_pdf_receipt_label))}</div>"
        else ""

        val paymentLinesHtml = StringBuilder()
        paymentLinesHtml.append(receiptBadge)
        if (invoiceStatus == InvoiceStatus.PAID) {
            paymentLinesHtml.append(infoLine(CALENDAR_ICON, "${context.getString(R.string.invoice_pdf_payment_date)}: ${dateFmt.format(Date(paymentDateMillis))}"))
            paymentLinesHtml.append(infoLine(null, context.getString(paymentMethod.paidLabelResId)))
        } else {
            val due = dueDateMillis ?: paymentDateMillis
            paymentLinesHtml.append(infoLine(CALENDAR_ICON, "${context.getString(R.string.invoice_due_date_label)}: ${dateFmt.format(Date(due))}"))
            paymentLinesHtml.append(infoLine(null, "${context.getString(R.string.payment_method_label)}: ${context.getString(paymentMethod.labelResId)}"))
        }

        val legalVatHtml = if (!isVatPayer) buildLegalVatBlock(context) else ""

        val statusClass = if (invoiceStatus == InvoiceStatus.PAID) "status-paid" else "status-pending"
        val statusText = if (invoiceStatus == InvoiceStatus.PAID)
            context.getString(R.string.invoice_pdf_paid_stamp) else context.getString(R.string.invoice_pdf_pending_stamp)
        val statusIcon = if (invoiceStatus == InvoiceStatus.PAID) CHECK_ICON else CLOCK_ICON

        // Update 4 (техтребование): компактный документ для 1-5 позиций, чтобы уместилось на 1 страницу.
        val pageCompactClass = if (rows.size in 1..5) "compact" else ""

        val html = loadTemplate(context)
            .replace("{{DOC_TITLE}}", esc(docTitle))
            .replace("{{SUBTITLE_LINE_HTML}}", "")
            .replace("{{DOC_DATES_HTML}}", datesHtml)
            .replace("{{LOGO_IMG_TAG}}", buildLogoImgTag(context))
            .replace("{{WAVE_TOP_IMG}}", buildWaveImgTag(context, "wave_top.png", "waves-top"))
            .replace("{{WAVE_BOTTOM_LEFT_IMG}}", buildWaveImgTag(context, "wave_bottom_left.png", "waves-bottom-left"))
            .replace("{{WAVE_BOTTOM_RIGHT_IMG}}", buildWaveImgTag(context, "wave_bottom_right.png", "waves-bottom-right"))
            .replace("{{BRAND_NAME_HTML}}", "")
            .replace("{{USER_ICON_SVG}}", USER_ICON)
            .replace("{{SELLER_BODY_HTML}}", sellerHtml)
            .replace("{{BUYER_BODY_HTML}}", buyerHtml)
            .replace("{{ITEMS_TABLES_HTML}}", itemsTableHtml)
            .replace("{{CORRECTION_BLOCK_HTML}}", "")
            .replace("{{PAGE_COMPACT_CLASS}}", pageCompactClass)
            .replace("{{PAGE_FILLER_BG_STYLE}}", buildPageFillerBgStyle(context))
            .replace("{{PAYMENT_INFO_LINES_HTML}}", paymentLinesHtml.toString())
            .replace("{{LEGAL_VAT_BLOCK_HTML}}", legalVatHtml)
            .replace("{{STATUS_BOX_HTML}}", buildStatusBoxHtml(statusClass, statusIcon, statusText))
            .replace("{{SIGN_ISSUED_LABEL}}", esc(context.getString(R.string.invoice_pdf_signature_issued_by)))
            .replace("{{SIGN_ISSUED_CAPTION}}", esc(context.getString(R.string.invoice_pdf_signature_issued_by_caption)))
            .replace("{{SIGN_RECEIVED_LABEL}}", esc(context.getString(R.string.invoice_pdf_signature_received_by)))
            .replace("{{SIGN_RECEIVED_CAPTION}}", esc(context.getString(R.string.invoice_pdf_signature_received_by_caption)))
            .replace("{{QR_IMG_TAG}}", buildQrImgTag(context))

        return renderHtmlToPdf(context, html)
    }

    suspend fun generateCorrection(
        context: Context,
        seller: InvoiceSellerData,
        correctionNumber: Int,
        issueDateMillis: Long,
        originalInvoiceNumber: Int,
        originalIssueDateMillis: Long,
        buyerName: String,
        buyerNip: String?,
        buyerStreet: String,
        buyerPostalCode: String,
        buyerCity: String,
        originalAmount: Double,
        correctedAmount: Double,
        reason: String,
        items: List<InvoiceItem> = emptyList(),
        vatRate: VatRate? = null,
        // Update 62: gdy faktura ma >1 pozycji i użytkownik wybrał JEDNĄ LUB WIĘCEJ
        // konkretnych pozycji do korekty (AddInvoiceCorrectionActivity) — correctedItems
        // to mapa indeks-w-`items` -> nowa wartość (ilość*cena) TEJ pozycji. Pozostałe
        // pozycje (nieobecne w mapie) zostają BEZ ZMIAN zamiast (jak wcześniej)
        // proporcjonalnego przeskalowania wszystkich pozycji razem. Pusta mapa = stare
        // zachowanie (korekta całej faktury, proporcjonalne przeskalowanie) — dotyczy
        // faktur z 0-1 pozycją.
        correctedItems: Map<Int, Double> = emptyMap()
    ): ByteArray {
        val isVatPayer = seller.nip.isNotBlank()
        val dateFmt = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())
        val numberFmt = SimpleDateFormat("MM/yyyy", Locale.US)

        val formattedNumber = "$correctionNumber/${numberFmt.format(Date(issueDateMillis))}"
        val originalFormattedNumber = "$originalInvoiceNumber/${numberFmt.format(Date(originalIssueDateMillis))}"
        val docTitle = "${context.getString(R.string.correction_pdf_title)} $formattedNumber"
        val subtitle = "<div class=\"doc-subtitle\">${esc(context.getString(R.string.correction_pdf_to_invoice))} $originalFormattedNumber</div>"
        val datesHtml = "<b>${context.getString(R.string.invoice_pdf_issue_date)}:</b> ${dateFmt.format(Date(issueDateMillis))}"

        val sellerHtml = buildSellerBody(context, seller, isVatPayer)
        val buyerHtml = buildBuyerBody(context, buyerName, buyerNip, buyerStreet, buyerPostalCode, buyerCity, buyerNip.isNullOrBlank())

        // "Przed korektą" to zawsze oryginalne pozycje bez zmian. "Po korekcie": jeśli
        // wybrano co najmniej jedną pozycję (correctedItems niepuste) — zmieniają się TYLKO
        // zaznaczone pozycje (każda wg swojej własnej nowej wartości), reszta zostaje
        // identyczna; w przeciwnym razie (korekta całej faktury, 0-1 pozycji) — stare
        // zachowanie: proporcjonalne przeskalowanie.
        val fallbackLabel = "${context.getString(R.string.correction_pdf_to_invoice)} $originalFormattedNumber"
        // Update 63: stawka VAT KAZDEJ pozycji (item.vatRate) nie zmienia sie przy korekcie —
        // korekta zmienia tylko kwote, dlatego before/after rows dziedziczy te sama stawke
        // co oryginalna pozycja.
        val beforeRows: List<Row> = if (items.isNotEmpty()) items.map { Row(it.name, it.quantity, it.unitPrice, VatRate.fromStorageKeyOrNull(it.vatRate)) }
            else listOf(Row(fallbackLabel, 1.0, originalAmount, vatRate))

        val afterRows: List<Row> = when {
            correctedItems.isNotEmpty() -> {
                items.mapIndexed { idx, item ->
                    val itemVat = VatRate.fromStorageKeyOrNull(item.vatRate)
                    val newValue = correctedItems[idx]
                    if (newValue != null) {
                        val newUnitPrice = if (item.quantity != 0.0) newValue / item.quantity else newValue
                        Row(item.name, item.quantity, newUnitPrice, itemVat)
                    } else {
                        Row(item.name, item.quantity, item.unitPrice, itemVat)
                    }
                }
            }
            items.isNotEmpty() -> {
                val scale = if (originalAmount != 0.0) correctedAmount / originalAmount else 1.0
                items.map { Row(it.name, it.quantity, it.unitPrice * scale, VatRate.fromStorageKeyOrNull(it.vatRate)) }
            }
            else -> listOf(Row(fallbackLabel, 1.0, correctedAmount, vatRate))
        }

        val tablesHtml = StringBuilder()
        tablesHtml.append("<div class=\"table-title\">${esc(context.getString(R.string.correction_pdf_before_table_title))}</div>")
        tablesHtml.append("<div class=\"table-frame\">").append(buildItemsTable(context, null, beforeRows)).append("</div>")
        tablesHtml.append("<div class=\"table-title\">${esc(context.getString(R.string.correction_pdf_after_table_title))}</div>")
        tablesHtml.append("<div class=\"table-frame\">").append(buildItemsTable(context, null, afterRows)).append("</div>")

        val delta = correctedAmount - originalAmount
        val deltaSign = if (delta >= 0) "+" else ""
        val deltaClass = if (delta >= 0) "positive" else "negative"
        val moneyFmt: (Double) -> String = { String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") + " zł" }
        val correctionBlockHtml = """
            <div class="reason-block">
              <div class="reason-title">${esc(context.getString(R.string.correction_pdf_reason_label))}</div>
              <div class="reason-text">${esc(reason.ifBlank { "—" })}</div>
            </div>
            <div class="delta-block">
              <div class="delta-chip">${esc(context.getString(R.string.correction_pdf_before_label))}<b>${moneyFmt(originalAmount)}</b></div>
              <div class="delta-chip">${esc(context.getString(R.string.correction_pdf_after_label))}<b>${moneyFmt(correctedAmount)}</b></div>
              <div class="delta-chip $deltaClass">${esc(context.getString(R.string.correction_pdf_delta_label))}<b>$deltaSign${moneyFmt(delta)}</b></div>
            </div>
        """.trimIndent()

        val legalVatHtml = if (!isVatPayer) buildLegalVatBlock(context) else ""
        // Update: próg "kompaktowego" dokumentu liczony wg liczby POZYCJI (nie sumy wierszy
        // obu tabel, co wcześniej podwajało licznik) — do 5 pozycji = "niewiele", zgodnie z
        // oczekiwaniem, że korekta z max. 5 pozycjami zawsze mieści się na 1 stronie.
        val positionsCount = maxOf(beforeRows.size, afterRows.size)
        val pageCompactClass = if (positionsCount in 1..5) "compact" else ""

        val html = loadTemplate(context)
            .replace("{{DOC_TITLE}}", esc(docTitle))
            .replace("{{SUBTITLE_LINE_HTML}}", subtitle)
            .replace("{{DOC_DATES_HTML}}", datesHtml)
            .replace("{{LOGO_IMG_TAG}}", buildLogoImgTag(context))
            .replace("{{WAVE_TOP_IMG}}", buildWaveImgTag(context, "wave_top.png", "waves-top"))
            .replace("{{WAVE_BOTTOM_LEFT_IMG}}", buildWaveImgTag(context, "wave_bottom_left.png", "waves-bottom-left"))
            .replace("{{WAVE_BOTTOM_RIGHT_IMG}}", buildWaveImgTag(context, "wave_bottom_right.png", "waves-bottom-right"))
            .replace("{{BRAND_NAME_HTML}}", "")
            .replace("{{USER_ICON_SVG}}", USER_ICON)
            .replace("{{SELLER_BODY_HTML}}", sellerHtml)
            .replace("{{BUYER_BODY_HTML}}", buyerHtml)
            .replace("{{ITEMS_TABLES_HTML}}", tablesHtml.toString())
            .replace("{{CORRECTION_BLOCK_HTML}}", correctionBlockHtml)
            .replace("{{PAGE_COMPACT_CLASS}}", pageCompactClass)
            .replace("{{PAGE_FILLER_BG_STYLE}}", buildPageFillerBgStyle(context))
            // Faktura korygująca nie ma statusu płatności/terminu w oryginalnym generatorze —
            // zostawiamy blok podstawy prawnej VAT, a status pokazujemy jako neutralny placeholder.
            // Update: faktura korygująca NIE pokazuje plakietki STATUS — nie ma tu statusu
            // płatności w takim sensie jak zwykła faktura, plakietka wprowadzała w błąd.
            .replace("{{PAYMENT_INFO_LINES_HTML}}", "")
            .replace("{{LEGAL_VAT_BLOCK_HTML}}", legalVatHtml)
            .replace("{{STATUS_BOX_HTML}}", "")
            .replace("{{SIGN_ISSUED_LABEL}}", esc(context.getString(R.string.invoice_pdf_signature_issued_by)))
            .replace("{{SIGN_ISSUED_CAPTION}}", esc(context.getString(R.string.invoice_pdf_signature_issued_by_caption)))
            .replace("{{SIGN_RECEIVED_LABEL}}", esc(context.getString(R.string.invoice_pdf_signature_received_by)))
            .replace("{{SIGN_RECEIVED_CAPTION}}", esc(context.getString(R.string.invoice_pdf_signature_received_by_caption)))
            .replace("{{QR_IMG_TAG}}", buildQrImgTag(context))

        return renderHtmlToPdf(context, html)
    }

    // ============================= BUDOWA FRAGMENTÓW HTML =============================

    private fun buildSellerBody(context: Context, seller: InvoiceSellerData, isVatPayer: Boolean): String {
        val sb = StringBuilder()
        if (seller.name.isNotBlank()) sb.append("<div class=\"party-name\">${esc(seller.name)}</div>")
        val address = listOfNotNull(
            seller.street.ifBlank { null },
            listOf(seller.postalCode, seller.city).filter { it.isNotBlank() }.joinToString(" ").ifBlank { null }
        ).joinToString(", ")
        if (address.isNotBlank()) sb.append("<div class=\"party-line\">${esc(address)}</div>")
        if (seller.nip.isNotBlank()) sb.append("<div class=\"party-line\">${esc(context.getString(R.string.invoice_pdf_nip))}: ${esc(seller.nip)}</div>")
        if (seller.bankAccount.isNotBlank()) sb.append("<div class=\"party-line\">${esc(context.getString(R.string.invoice_pdf_bank_account))}: ${esc(seller.bankAccount)}</div>")
        if (!isVatPayer) sb.append("<div class=\"party-note\">${esc(context.getString(R.string.invoice_pdf_seller_nierejestrowana_note))}</div>")
        return sb.toString()
    }

    private fun buildBuyerBody(
        context: Context, buyerName: String, buyerNip: String?, buyerStreet: String,
        buyerPostalCode: String, buyerCity: String, isPhysicalPerson: Boolean
    ): String {
        val sb = StringBuilder()
        sb.append("<div class=\"party-name\">${esc(buyerName)}</div>")
        val address = listOfNotNull(
            buyerStreet.ifBlank { null },
            listOf(buyerPostalCode, buyerCity).filter { it.isNotBlank() }.joinToString(" ").ifBlank { null }
        ).joinToString(", ")
        if (address.isNotBlank()) sb.append("<div class=\"party-line\">${esc(address)}</div>")
        if (!isPhysicalPerson && !buyerNip.isNullOrBlank()) {
            sb.append("<div class=\"party-line\">${esc(context.getString(R.string.invoice_pdf_nip))}: ${esc(buyerNip)}</div>")
        } else {
            sb.append("<div class=\"party-note\">${esc(context.getString(R.string.invoice_pdf_buyer_private))}</div>")
        }
        return sb.toString()
    }

    private fun buildLegalVatBlock(context: Context): String = """
        <div class="info-line">
          <span class="info-icon">$PERCENT_ICON</span>
          <span class="info-text">
            <div class="legal-title">${esc(context.getString(R.string.invoice_pdf_legal_basis_title))}</div>
            <div class="legal-text">${esc(context.getString(R.string.invoice_pdf_legal_basis_text))}</div>
          </span>
        </div>
    """.trimIndent()

    private fun infoLine(icon: String?, text: String): String =
        "<div class=\"info-line\">${if (icon != null) "<span class=\"info-icon\">$icon</span>" else "<span class=\"info-icon\"></span>"}<span class=\"info-text\">${esc(text)}</span></div>"

    /** Buduje tabelę pozycji — bez VAT (Lp/Nazwa/Jedn./Ilość/Cena netto/Wartość netto, jak
     *  na dostarczonym makiecie) lub z VAT (dodatkowo Stawka VAT/Kwota VAT/Wartość brutto).
     *  Update 63: stawka VAT jest teraz WŁASNOŚCIĄ KAŻDEJ POZYCJI (row.vatRate) zamiast
     *  jednej wspólnej stawki na całą fakturę — różne towary/usługi mogą mieć różne stawki
     *  na jednym dokumencie. Tabela pokazuje kolumny VAT, jeśli CHOĆ JEDNA pozycja ma
     *  ustawioną stawkę. Gdy wśród pozycji występuje więcej niż jedna różna stawka VAT,
     *  pod pozycjami dodawany jest blok "W tym" (podsumowanie netto/VAT/brutto osobno dla
     *  każdej stawki) oraz wiersz "Razem" (łączne netto/VAT/brutto) — dokładnie jak w
     *  standardowej fakturze VAT z wieloma stawkami. */
    private fun buildItemsTable(context: Context, title: String?, rows: List<Row>): String {
        val qtyStr: (Double) -> String = { q -> if (q == q.toLong().toDouble()) q.toLong().toString() else q.toString() }
        val money: (Double) -> String = { String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") + " zł" }
        val vatLabel: (VatRate?) -> String = { rate ->
            if (rate == null) "—"
            else rate.percent?.let { p -> val i = p.toInt(); if (i.toDouble() == p) "$i%" else "$p%" } ?: rate.storageKey
        }

        val hasVat = rows.any { it.vatRate != null }

        val sb = StringBuilder()
        if (title != null) sb.append("<div class=\"table-title\">${esc(title)}</div>")
        sb.append("<table class=\"items\"><thead><tr>")
        sb.append("<th class=\"col-lp\">${esc(context.getString(R.string.invoice_pdf_table_lp))}</th>")
        sb.append("<th class=\"col-name\">${esc(context.getString(R.string.invoice_pdf_table_name))}</th>")
        sb.append("<th class=\"col-unit\">${esc(context.getString(R.string.invoice_pdf_table_unit))}</th>")
        sb.append("<th class=\"col-qty num\">${esc(context.getString(R.string.invoice_pdf_table_qty))}</th>")
        if (!hasVat) {
            sb.append("<th class=\"col-price num\">${esc(context.getString(R.string.invoice_pdf_table_price_netto))}</th>")
            sb.append("<th class=\"col-total num\">${esc(context.getString(R.string.invoice_pdf_table_netto))}</th>")
        } else {
            sb.append("<th class=\"num\">${esc(context.getString(R.string.invoice_pdf_table_price_netto))}</th>")
            sb.append("<th class=\"num\">${esc(context.getString(R.string.invoice_pdf_table_netto))}</th>")
            sb.append("<th class=\"num\">${esc(context.getString(R.string.invoice_pdf_table_vat_rate))}</th>")
            sb.append("<th class=\"num\">${esc(context.getString(R.string.invoice_pdf_table_vat_amount))}</th>")
            sb.append("<th class=\"num\">${esc(context.getString(R.string.invoice_pdf_table_brutto))}</th>")
        }
        sb.append("</tr></thead><tbody>")

        var sumNet = 0.0
        var sumVat = 0.0
        // Suma wg stawki VAT — do bloku "W tym" (klucz = etykieta stawki, np. "23%").
        val byRate = LinkedHashMap<String, DoubleArray>()

        rows.forEachIndexed { idx, row ->
            val netValue = row.qty * row.unitPrice
            sumNet += netValue
            sb.append("<tr>")
            sb.append("<td>${idx + 1}</td>")
            sb.append("<td>${esc(row.name)}</td>")
            sb.append("<td>${esc(context.getString(R.string.invoice_pdf_unit_piece))}</td>")
            sb.append("<td class=\"num\">${qtyStr(row.qty)}</td>")
            if (!hasVat) {
                sb.append("<td class=\"num\">${money(row.unitPrice)}</td>")
                sb.append("<td class=\"num\">${money(netValue)}</td>")
            } else {
                val vatAmount = row.vatRate?.vatAmount(netValue) ?: 0.0
                val bruttoValue = netValue + vatAmount
                sumVat += vatAmount
                val rateLabel = vatLabel(row.vatRate)
                sb.append("<td class=\"num\">${money(row.unitPrice)}</td>")
                sb.append("<td class=\"num\">${money(netValue)}</td>")
                sb.append("<td class=\"num\">${rateLabel}</td>")
                sb.append("<td class=\"num\">${money(vatAmount)}</td>")
                sb.append("<td class=\"num\">${money(bruttoValue)}</td>")
                val bucket = byRate.getOrPut(rateLabel) { DoubleArray(3) }
                bucket[0] += netValue; bucket[1] += vatAmount; bucket[2] += bruttoValue
            }
            sb.append("</tr>")
        }
        sb.append("</tbody>")

        if (hasVat) {
            // Blok "W tym": tylko gdy pozycje faktycznie mają różne stawki — przy jednej
            // wspólnej stawce dublowałby wiersz "Razem" poniżej bez żadnej nowej informacji.
            if (byRate.size > 1) {
                var first = true
                for ((rateLabel, sums) in byRate) {
                    sb.append("<tr class=\"vat-breakdown-row\">")
                    sb.append("<td colspan=\"4\"></td>")
                    sb.append("<td>${if (first) esc(context.getString(R.string.invoice_pdf_vat_breakdown_label)) else ""}</td>")
                    sb.append("<td class=\"num\">${money(sums[0])}</td>")
                    sb.append("<td class=\"num\">${rateLabel}</td>")
                    sb.append("<td class=\"num\">${money(sums[1])}</td>")
                    sb.append("<td class=\"num\">${money(sums[2])}</td>")
                    sb.append("</tr>")
                    first = false
                }
            }
            val grossTotal = sumNet + sumVat
            sb.append("<tr class=\"vat-total-row\">")
            sb.append("<td colspan=\"4\"></td>")
            sb.append("<td>${esc(context.getString(R.string.invoice_pdf_table_total))}</td>")
            sb.append("<td class=\"num\">${money(sumNet)}</td>")
            sb.append("<td></td>")
            sb.append("<td class=\"num\">${money(sumVat)}</td>")
            sb.append("<td class=\"num\">${money(grossTotal)}</td>")
            sb.append("</tr>")
        }

        sb.append("</table>")
        return sb.toString()
    }

    private fun buildSumRow(context: Context, netTotal: Double, vatTotal: Double, hasVat: Boolean): String {
        val money: (Double) -> String = { String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") + " zł" }
        val grossTotal = netTotal + vatTotal
        // Update 63: gdy VAT obowiązuje, "DO ZAPŁATY" to kwota BRUTTO (netto+VAT) — wcześniej
        // ten pasek zawsze pokazywał samo netto, nawet dla faktur z VAT, co było błędem
        // (kupujący płaci netto+VAT, nie samo netto). Trzy linijki netto/VAT/brutto nad
        // paskiem pokazują pełne rozliczenie, tak jak w dostarczonym wzorze.
        val breakdownHtml = if (hasVat) """
            <div class="totals-breakdown">
              <div class="totals-line"><span>${esc(context.getString(R.string.invoice_pdf_table_netto))}</span><b>${money(netTotal)}</b></div>
              <div class="totals-line"><span>${esc(context.getString(R.string.invoice_pdf_table_vat_amount))}</span><b>${money(vatTotal)}</b></div>
              <div class="totals-line"><span>${esc(context.getString(R.string.invoice_pdf_table_brutto))}</span><b>${money(grossTotal)}</b></div>
            </div>
        """.trimIndent() else ""
        return """
            $breakdownHtml
            <div class="sum-row">
              <div class="sum-label-wrap">${esc(context.getString(R.string.invoice_pdf_sum_label))} DO ZAPŁATY</div>
              <div class="sum-amount">${money(if (hasVat) grossTotal else netTotal)}</div>
            </div>
        """.trimIndent()
    }

    /** Plakietka STATUS (ZAPŁACONO/OCZEKUJE NA ZAPŁATĘ) — tylko dla zwykłej faktury.
     *  Faktura korygująca jej nie ma (patrz generateCorrection) — przekazuje pustą wartość. */
    private fun buildStatusBoxHtml(statusClass: String, statusIconSvg: String, statusText: String): String {
        return """
            <div class="status-box $statusClass">
              <span class="status-icon">$statusIconSvg</span>
              <div>
                <div class="status-label">STATUS</div>
                <div class="status-text">${esc(statusText)}</div>
              </div>
            </div>
        """.trimIndent()
    }

    // ============================= LOGO / QR (base64, offline) =============================

    /** Logo w lewym górnym rogu: jeśli użytkownik wgrał własne (patrz [InvoiceLogoStore]) —
     *  pokazujemy je (object-fit:contain, ograniczone przez CSS .brand img.logo), w
     *  przeciwnym razie logo wycięte 1:1 z zatwierdzonego REFERENCE (R.drawable.logo_reference,
     *  NIE domyślne R.drawable.logo aplikacji — kolory/kształt/napis "FinArs" niezmienione,
     *  tylko wycięte z oryginalnego pliku i podbite w rozdzielczości pod druk). */
    private fun buildLogoImgTag(context: Context): String {
        val userLogoPath = InvoiceLogoStore.load(context)
        val bitmap: Bitmap? = if (!userLogoPath.isNullOrBlank()) {
            try { BitmapFactory.decodeFile(userLogoPath) } catch (e: Exception) { null }
        } else null
        val bmp = bitmap ?: try {
            BitmapFactory.decodeResource(context.resources, R.drawable.logo_reference)
        } catch (e: Exception) { null }
        val base64 = bmp?.let { bitmapToBase64Png(it) }
        return if (base64 != null) "<img class=\"logo\" src=\"data:image/png;base64,$base64\"/>" else ""
    }

    /** QR z pliku dostarczonego przez użytkownika — umieść go jako
     *  app/src/main/res/drawable/qr_download.png (patrz notatka integracyjna). */
    private fun buildQrImgTag(context: Context): String {
        val resId = context.resources.getIdentifier("qr_download", "drawable", context.packageName)
        if (resId == 0) return ""
        val bmp = try { BitmapFactory.decodeResource(context.resources, resId) } catch (e: Exception) { null } ?: return ""
        val base64 = bitmapToBase64Png(bmp)
        return "<img class=\"qr\" src=\"data:image/png;base64,$base64\"/>"
    }

    /** Dekoracyjne fale (tło nagłówka/stopki) — wycięte 1:1 z zatwierdzonego REFERENCE
     *  (assets/wave_top.png, wave_bottom_left.png, wave_bottom_right.png), NIE rysowane
     *  jako przybliżenie SVG. cssClass odpowiada pozycjonowaniu zdefiniowanemu w CSS
     *  (.waves-top / .waves-bottom-left / .waves-bottom-right). */
    private fun buildWaveImgTag(context: Context, assetName: String, cssClass: String): String {
        val base64 = loadAssetBase64(context, assetName) ?: return ""
        return "<img class=\"$cssClass\" src=\"data:image/png;base64,$base64\"/>"
    }

    /** Wczytuje plik z assets/ i zwraca jego zawartość jako base64 (offline, wbudowane w HTML —
     *  bez tego WebView renderowany off-screen bez podłączenia do sieci nie wczytałby obrazka
     *  spod zwykłego względnego URL-a). Wspólne dla fal narożnikowych (.waves-*) i dekoracji
     *  w .page-filler (patrz buildPageFillerBgStyle) — jeden plik, jedno miejsce ładowania. */
    private fun loadAssetBase64(context: Context, assetName: String): String? = try {
        context.assets.open(assetName).use { it.readBytes() }
    } catch (e: Exception) {
        null
    }?.let { android.util.Base64.encodeToString(it, android.util.Base64.NO_WRAP) }

    /** Dekoracja wewnątrz .page-filler (patrz szablon HTML) — TEN SAM obrazek fal co w narożnikach
     *  strony, ustawiony jako background-image (a nie <img>), żeby mógł się czysto rozciągnąć do
     *  DOWOLNEJ wysokości ustawianej dynamicznie z JS (patrz renderHtmlToPdf) bez szwów/kaflowania.
     *  Płynne pojawianie/zanikanie krawędzi zapewnia mask-image w CSS (.page-filler). */
    private fun buildPageFillerBgStyle(context: Context): String {
        val base64 = loadAssetBase64(context, "wave_top.png") ?: return ""
        return "background-image:url('data:image/png;base64,$base64');"
    }

    private fun bitmapToBase64Png(bitmap: Bitmap): String {
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        return android.util.Base64.encodeToString(stream.toByteArray(), android.util.Base64.NO_WRAP)
    }

    private fun loadTemplate(context: Context): String =
        context.assets.open(TEMPLATE_ASSET).bufferedReader(Charsets.UTF_8).use { it.readText() }

    private fun esc(text: String): String = text
        .replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

    // ============================= RENDER: WebView -> PDF bajty =============================

    // 794 CSS-px = 210mm (210 * 96/25.4) — MUSI być zgodne z <meta name="viewport"
    // content="width=794..."> w invoice_template.html. To jest szerokość w "referencyjnych"
    // pikselach CSS, NIE w surowych pikselach Androida — te dwie wartości różnią się o
    // gęstość ekranu (density), patrz komentarz w renderHtmlToPdf().
    private const val PAGE_CSS_WIDTH_PX = 794
    private const val A4_RATIO = 297f / 210f
    private const val PDF_PAGE_WIDTH_PT = 595
    private const val PDF_PAGE_HEIGHT_PT = 842

    /** Renderuje gotowy HTML do PDF BEZ systemowego dialogu drukowania.
     *
     *  UWAGA: android.print.PrintDocumentAdapter.LayoutResultCallback/WriteResultCallback
     *  mają konstruktory package-private — nie da się ich podklasować spoza pakietu
     *  android.print (to nie jest hack do obejścia, to twardy limit Kotlina/Javy przy
     *  kompilacji), więc "ręczne" sterowanie PrintDocumentAdapter z kodu aplikacji jest
     *  niemożliwe. Zamiast tego renderujemy WebView do jednego długiego Bitmapu (cała
     *  wysokość dokumentu), a następnie TNIEMY go ręcznie na strony A4 w Kotlinie —
     *  pilnując przez getBoundingClientRect(), żeby cięcie nie wypadło w środku bloku
     *  .footer-wrap (to zastępuje CSS page-break-inside:avoid, którego przeglądarka i tak
     *  nie stosuje poza prawdziwym silnikiem druku).
     *
     *  WAŻNE (gęstość ekranu): WebView/Chromium liczy CSS-px względem gęstości ekranu
     *  (density) kontekstu, z którym został utworzony — 1 CSS-px odpowiada `density`
     *  surowym pikselom Androida. Nasz <meta viewport width=794> deklaruje 794 CSS-px,
     *  więc View/Bitmap MUSZĄ mieć szerokość 794*density surowych pikseli, inaczej
     *  dostępna przestrzeń wyjdzie węższa niż zadeklarowana i treść zostanie ucięta z
     *  prawej strony (a nie przeskalowana) — to była przyczyna wcześniejszego błędu.
     *  Z tego samego powodu wszystkie pomiary z JS (scrollHeight, getBoundingClientRect)
     *  zwracają CSS-px i też trzeba je przemnożyć przez density przed użyciem w Bitmapie.
     *
     *  WAŻNE (attach): WebView MUSI być rzeczywiście dołączony do okna (attached), inaczej
     *  onPageFinished/evaluateJavascript/draw(canvas) potrafią nigdy się nie zakończyć albo
     *  dać pustą bitmapę — dlatego wymagamy tu kontekstu Activity (nie applicationContext)
     *  i na czas renderu dokładamy WebView do decorView poza widocznym obszarem ekranu.
     *  Cały proces owinięty jest w withTimeout — jeśli coś jednak "zawiśnie", dostaniemy
     *  jasny wyjątek zamiast zamrożonego UI na czas nieokreślony.
     *
     *  MUSI być wywołane z wątku głównego (WebView) — dlatego przełączamy dispatcher tutaj. */
    /** Wynik pomiaru JS layoutu dokumentu: całkowita wysokość (document.body.scrollHeight) i
     *  zakresy [top,bottom] każdego .footer-wrap — wszystko w CSS-px (NIE surowych px Bitmapy),
     *  czyli niezależnie od gęstości ekranu urządzenia. */
    private data class Measurement(val cssHeightPx: Float, val footersCss: List<Pair<Float, Float>>)

    private fun parseMeasurement(resultStr: String?, fallbackHeightCss: Float): Measurement {
        var cssHeight = fallbackHeightCss
        var footers: List<Pair<Float, Float>> = emptyList()
        try {
            val clean = (resultStr ?: "").let {
                var s = it.trim()
                if (s.startsWith("\"") && s.endsWith("\"")) s = s.substring(1, s.length - 1)
                s.replace("\\\"", "\"")
            }
            val obj = org.json.JSONObject(clean)
            cssHeight = obj.optDouble("height", cssHeight.toDouble()).toFloat()
            val arr = obj.optJSONArray("footers") ?: org.json.JSONArray()
            footers = (0 until arr.length()).map { idx ->
                val pair = arr.getJSONArray(idx)
                pair.getInt(0).toFloat() to pair.getInt(1).toFloat()
            }
        } catch (e: Exception) {
            // Bezpieczny fallback — bez ochrony przed cięciem stopki / bez wypełniacza,
            // ale przynajmniej dalej renderujemy (lepsze niż całkiem przerwać generowanie PDF).
        }
        return Measurement(cssHeight, footers)
    }


    private suspend fun renderHtmlToPdf(context: Context, html: String): ByteArray = withContext(Dispatchers.Main) {
        val activity = resolveActivity(context)
            ?: throw IllegalStateException(
                "InvoiceHtmlPdfGenerator wymaga kontekstu Activity (nie applicationContext) — " +
                "WebView musi być dołączony do okna, żeby renderowanie działało niezawodnie."
            )
        val decor = activity.window.decorView as ViewGroup

        val density = activity.resources.displayMetrics.density.let { if (it > 0f) it else 1f }
        val renderWidthPx = (PAGE_CSS_WIDTH_PX * density).toInt().coerceAtLeast(1)
        val pageHeightPx = (renderWidthPx * A4_RATIO).toInt()

        val webView = WebView(activity)
        webView.setLayerType(View.LAYER_TYPE_SOFTWARE, null)
        webView.settings.javaScriptEnabled = true // potrzebne tylko do pomiaru wysokości/pozycji (własny HTML, bez zewnętrznych treści)
        // Krytyczne dla poprawnego skalowania: useWideViewPort=false IGNOROWAŁO nasz
        // <meta name="viewport">, a WebView sam zgadywał szerokość na podstawie gęstości
        // ekranu — stąd wcześniejszy błąd "przybliżonej"/obciętej strony w PDF.
        webView.settings.useWideViewPort = true
        webView.settings.loadWithOverviewMode = true
        webView.settings.textZoom = 100
        webView.setInitialScale(0) // 0 = auto, niech przeglądarka sama dopasuje wg meta viewport

        // Update: WRAP_CONTENT jako wysokość startowa dawał Chromium bardzo mały surface na
        // starcie, po czym musieliśmy go gwałtownie powiększać (measure/layout niżej) do pełnej
        // wysokości dokumentu — a to WŁAŚNIE ten moment, w którym silnik renderujący w trybie
        // software (LAYER_TYPE_SOFTWARE) potrafi zostawić "stare"/zduplikowane kafelki w
        // Bitmapie (widoczne np. jako powtórzone wiersze tabeli albo osierocona pojedyncza
        // linijka spod stopki). Start od razu z dużą, stałą wysokością (kilka stron A4) prawie
        // zawsze eliminuje ten skok całkowicie dla typowych dokumentów.
        val initialHeightPx = pageHeightPx * 4

        // Dołączamy off-screen (daleko poza ekranem), żeby user nic nie widział, ale WebView
        // miał prawdziwe okno/surface do renderowania.
        val params = FrameLayout.LayoutParams(renderWidthPx, initialHeightPx)
        webView.layoutParams = params
        webView.translationX = -100000f
        decor.addView(webView, params)

        try {
            var avoidRangesResult: List<Pair<Int, Int>> = emptyList()

            // Rozmiar strony i górny margines w jednostkach CSS-px (NIEZALEŻNE od gęstości
            // ekranu — te same wartości niezależnie od urządzenia, bo <meta viewport>
            // deklaruje stałą szerokość 794 CSS-px) — przekazywane do skryptu JS niżej, który
            // na ich podstawie decyduje, czy stopka potrzebuje dosunięcia/dekoracji.
            val pageHeightCss = PAGE_CSS_WIDTH_PX * A4_RATIO
            val topMarginPtLocal = 14f * 72f / 25.4f
            val topMarginCss = topMarginPtLocal * PAGE_CSS_WIDTH_PX / PDF_PAGE_WIDTH_PT
            // Próg "warto dekorować": mniejsza pusta przestrzeń niż to po prostu zostaje pusta
            // (naturalny, niewielki margines na końcu strony — nie wymaga dekoracji). Tylko
            // wyraźnie duża, rzucająca się w oczy pustka dostaje wypełniacz.
            val minGapFillerCss = 25f * PAGE_CSS_WIDTH_PX / 210f // ~25mm, przeliczone na CSS-px

            val fullBitmap: Bitmap = withTimeout(20_000) {
                suspendCancellableCoroutine { cont ->
                    webView.webViewClient = object : WebViewClient() {
                        override fun onPageFinished(view: WebView, url: String) {
                            // mały odstęp — daje WebView domalować base64-owe obrazy (logo/QR) i fonty
                            // po zdarzeniu onPageFinished, zanim zaczniemy mierzyć layout
                            view.postDelayed({
                                if (!cont.isActive) return@postDelayed

                                // WAŻNE: to WSZYSTKO dzieje się w JEDNYM, synchronicznym wywołaniu
                                // JS — pomiar naturalnego layoutu, decyzja o wypełniaczu, sama
                                // mutacja DOM-u (#page-filler) i pomiar PO mutacji — wszystko w
                                // jednym wykonaniu silnika JS, bez żadnego "postDelayed" pomiędzy
                                // krokami. To celowe: wcześniejsza wersja robiła to w DWÓCH
                                // osobnych, asynchronicznych przebiegach (evaluateJavascript +
                                // postDelayed + evaluateJavascript), co w praktyce potrafiło dać
                                // nieaktualny odczyt wysokości i w efekcie: obciętą/zniknięcą
                                // stopkę na długich fakturach, oraz niepotrzebne wypchnięcie
                                // korekty na 3. stronę zamiast 2. Jedno zsynchronizowane
                                // wykonanie JS eliminuje tę klasę błędów całkowicie — getBoundingClientRect
                                // po mutacji DOM w tym samym skrypcie ZAWSZE zwraca świeży layout
                                // (przeglądarka robi synchroniczny "reflow" na żądanie).
                                val js = """
                                    (function(){
                                        function measure(){
                                            var els = document.querySelectorAll('.footer-wrap');
                                            var footers = [];
                                            for (var i=0;i<els.length;i++){
                                                var r = els[i].getBoundingClientRect();
                                                footers.push([Math.round(r.top + window.scrollY), Math.round(r.bottom + window.scrollY)]);
                                            }
                                            return { height: document.body.scrollHeight, footers: footers };
                                        }

                                        var pageHeight = $pageHeightCss;
                                        var topMargin = $topMarginCss;
                                        var minGap = $minGapFillerCss;

                                        var m1 = measure();
                                        var filler = document.getElementById('page-filler');

                                        if (filler && m1.footers.length > 0) {
                                            var footerTop = m1.footers[0][0];
                                            var footerBottom = m1.footers[0][1];
                                            var footerHeight = footerBottom - footerTop;

                                            if (footerHeight > 0 && footerHeight < pageHeight) {
                                                // Symuluje TĘ SAMĄ regułę "avoid-cut", którą stosuje
                                                // finalne cięcie bitmapy na strony w Kotlinie (patrz
                                                // pętla `while (top < totalHeight)` niżej) — żeby
                                                // ustalić, na KTÓREJ stronie (0 = pierwsza) wyląduje
                                                // stopka w NATURALNYM układzie (bez żadnej ingerencji).
                                                var top = 0, total = m1.height, idx = -1, pageTop = 0;
                                                var i = 0;
                                                while (top < total && i < 500) {
                                                    var isFirst = (i === 0);
                                                    var avail = isFirst ? pageHeight : (pageHeight - topMargin);
                                                    var bottom = Math.min(top + avail, total);
                                                    if (top < footerTop && bottom > footerTop && bottom < footerBottom) {
                                                        bottom = footerTop;
                                                    }
                                                    if (bottom <= top) bottom = Math.min(top + avail, total);
                                                    if (footerTop >= top - 0.5 && footerTop < bottom + 0.5) {
                                                        idx = i; pageTop = top;
                                                        break;
                                                    }
                                                    top = bottom;
                                                    i++;
                                                }

                                                // Stopka jest dosuwana do dołu strony TYLKO gdy ląduje
                                                // na 2. lub kolejnej stronie (idx > 0) — dokument, który
                                                // mieści się cały na stronie 1, kończy się naturalnie,
                                                // z ewentualnym marginesem na dole strony (to normalne,
                                                // nie wymaga dekoracji ani dosuwania).
                                                if (idx > 0) {
                                                    // ~20mm marginesu bezpieczeństwa (w CSS-px) — ta
                                                    // dekoracja jest czysto kosmetyczna, więc zawsze
                                                    // wolimy zostawić trochę niewykorzystanej przestrzeni
                                                    // niż zaryzykować (nawet przy drobnych rozbieżnościach
                                                    // zaokrągleń między tym szacunkiem a finalnym cięciem
                                                    // bitmapy w Kotlinie) "wypchnięcie" stopki na
                                                    // niepotrzebną kolejną stronę.
                                                    var safety = 75;
                                                    var fullBottom = pageTop + (pageHeight - topMargin) - safety;
                                                    var gap = fullBottom - footerBottom;
                                                    if (gap > minGap) {
                                                        filler.style.display = 'block';
                                                        filler.style.height = Math.min(gap, pageHeight) + 'px';
                                                    }
                                                }
                                            }
                                        }

                                        var m2 = measure();
                                        return JSON.stringify(m2);
                                    })();
                                """.trimIndent()

                                view.evaluateJavascript(js) { resultStr ->
                                    if (!cont.isActive) return@evaluateJavascript
                                    val m = parseMeasurement(resultStr, pageHeightCss)
                                    val avoidRangesLocal = m.footersCss.map { (a, b) -> (a * density).toInt() to (b * density).toInt() }
                                    avoidRangesResult = avoidRangesLocal
                                    val totalHeightPx = maxOf((m.cssHeightPx * density).toInt(), 1)
                                    view.measure(
                                        View.MeasureSpec.makeMeasureSpec(renderWidthPx, View.MeasureSpec.EXACTLY),
                                        View.MeasureSpec.makeMeasureSpec(totalHeightPx, View.MeasureSpec.EXACTLY)
                                    )
                                    view.layout(0, 0, renderWidthPx, totalHeightPx)
                                    view.invalidate()
                                    // KRYTYCZNE: bez tego opóźnienia view.draw(canvas) potrafi
                                    // złapać częściowo NIEOD-rysowaną klatkę — Chromium nie
                                    // zdążył jeszcze zrasteryzować nowo odsłoniętego obszaru po
                                    // powiększeniu View, przez co w Bitmapie pojawiają się stare/
                                    // zduplikowane kafelki (np. nagłówek powtórzony niżej zamiast
                                    // prawdziwej treści stopki). Druga klatka (post -> post)
                                    // dodatkowo czeka na zakończenie bieżącego cyklu rysowania.
                                    view.postDelayed({
                                        if (!cont.isActive) return@postDelayed
                                        view.invalidate()
                                        view.post {
                                            if (!cont.isActive) return@post
                                            val bmp = Bitmap.createBitmap(renderWidthPx, totalHeightPx, Bitmap.Config.ARGB_8888)
                                            val canvas = Canvas(bmp)
                                            canvas.drawColor(Color.WHITE)
                                            view.draw(canvas)
                                            if (cont.isActive) cont.resume(bmp)
                                        }
                                    }, 500)
                                }
                            }, 150)
                        }
                    }
                    webView.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null)
                }
            }

            // Zakresy [top, bottom] w px bitmapy, których NIE wolno przecinać cięciem strony —
            // zmierzone wcześniej, w tym samym wywołaniu JS co scrollHeight (patrz wyżej).
            val avoidRanges = avoidRangesResult

            // Zabezpieczenie przed "widmową" prawie pustą ostatnią stroną: jeśli całkowita
            // wysokość dokumentu przekracza wielokrotność pageHeightPx tylko o drobny margines
            // (np. zaokrąglenia modelu pudełkowego CSS przy min-height:271mm), a w tym
            // nadmiarze NIE ma żadnej treści chronionej przed cięciem (.footer-wrap), po prostu
            // przycinamy nadmiar zamiast tworzyć dodatkową, praktycznie pustą stronę.
            val rawTotalHeight = fullBitmap.height
            val pageCountFloor = rawTotalHeight / pageHeightPx
            val remainder = rawTotalHeight - pageCountFloor * pageHeightPx
            val trimThreshold = maxOf((pageHeightPx * 0.03).toInt(), 15)
            val floorBoundary = pageCountFloor * pageHeightPx
            val overlapsProtectedContent = avoidRanges.any { (first, second) -> second > floorBoundary && first < rawTotalHeight }
            val totalHeight = if (pageCountFloor > 0 && remainder in 1 until trimThreshold && !overlapsProtectedContent) {
                floorBoundary
            } else {
                rawTotalHeight
            }

            // Górny margines strony (mm), wstrzykiwany ręcznie dla stron 2+ — pierwsza strona
            // ma go już "wypieczonego" w bitmapie (bo .page ma padding-top w CSS), ale każda
            // kolejna strona zaczyna się dokładnie tam, gdzie skończyła się poprzednia (środek
            // ciągłego dokumentu), więc bez tego treść zaczynałaby się od samej krawędzi papieru.
            val topMarginPt = 14f * 72f / 25.4f
            val topMarginPx = (topMarginPt * renderWidthPx / PDF_PAGE_WIDTH_PT).toInt()

            val document = PdfDocument()
            var top = 0
            var pageNumber = 1
            while (top < totalHeight) {
                val isFirstPage = (top == 0)
                val availableHeightPx = if (isFirstPage) pageHeightPx else pageHeightPx - topMarginPx
                var bottom = minOf(top + availableHeightPx, totalHeight)
                for (range in avoidRanges) {
                    if (top < range.first && bottom in (range.first + 1) until range.second) {
                        bottom = range.first
                        break
                    }
                }
                if (bottom <= top) bottom = minOf(top + availableHeightPx, totalHeight)

                val sliceHeight = bottom - top
                val slice = Bitmap.createBitmap(fullBitmap, 0, top, renderWidthPx, sliceHeight)

                val page = document.startPage(
                    PdfDocument.PageInfo.Builder(PDF_PAGE_WIDTH_PT, PDF_PAGE_HEIGHT_PT, pageNumber).create()
                )
                val destHeight = sliceHeight.toFloat() * PDF_PAGE_WIDTH_PT / renderWidthPx
                val destTop = if (isFirstPage) 0f else topMarginPt
                page.canvas.drawBitmap(slice, null, RectF(0f, destTop, PDF_PAGE_WIDTH_PT.toFloat(), destTop + destHeight), null)
                document.finishPage(page)
                slice.recycle()

                top = bottom
                pageNumber++
            }

            val out = ByteArrayOutputStream()
            document.writeTo(out)
            document.close()
            fullBitmap.recycle()
            out.toByteArray()
        } finally {
            decor.removeView(webView)
            webView.destroy()
        }
    }

    /** Context przekazany przez wywołującego bywa Activity bezpośrednio albo ContextWrapper
     *  wokół niej — rozwijamy warstwy, żeby dostać się do prawdziwej Activity (i jej okna). */
    private fun resolveActivity(context: Context): Activity? {
        var c = context
        while (c is android.content.ContextWrapper) {
            if (c is Activity) return c
            c = c.baseContext
        }
        return c as? Activity
    }

    // ============================= SVG ikony (inline, bez zasobów sieciowych) =============================

    private val USER_ICON = """<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <circle cx="12" cy="8" r="4" fill="$ICON_WHITE"/>
        <path d="M4 20c0-4.4 3.6-8 8-8s8 3.6 8 8" stroke="$ICON_WHITE" stroke-width="2" stroke-linecap="round"/>
        </svg>""".trimIndent()

    private val CHECK_ICON = """<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M5 13l4 4L19 7" stroke="$ICON_WHITE" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>""".trimIndent()

    private val CLOCK_ICON = """<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <circle cx="12" cy="12" r="8.5" stroke="$ICON_WHITE" stroke-width="2"/>
        <path d="M12 7v5l3.5 2" stroke="$ICON_WHITE" stroke-width="2" stroke-linecap="round"/>
        </svg>""".trimIndent()

    private val CALENDAR_ICON = """<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <rect x="3" y="5" width="18" height="16" rx="2" stroke="#FFFFFF" stroke-width="1.8"/>
        <path d="M3 9h18M8 3v4M16 3v4" stroke="#FFFFFF" stroke-width="1.8" stroke-linecap="round"/>
        </svg>""".trimIndent()

    private val PERCENT_ICON = """<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <circle cx="7" cy="7" r="3" stroke="#FFFFFF" stroke-width="1.8"/>
        <circle cx="17" cy="17" r="3" stroke="#FFFFFF" stroke-width="1.8"/>
        <path d="M5 19L19 5" stroke="#FFFFFF" stroke-width="1.8" stroke-linecap="round"/>
        </svg>""".trimIndent()
}
