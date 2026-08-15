package com.example.fa_ksiegowy

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import android.view.View
import android.webkit.WebView
import android.webkit.WebViewClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.json.JSONArray
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

    private data class Row(val name: String, val qty: Double, val unitPrice: Double)

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

        val rows: List<Row> = if (items.isNotEmpty()) items.map { Row(it.name, it.quantity, it.unitPrice) }
            else listOf(Row(serviceName, 1.0, amount))
        val totalAmount = rows.sumOf { it.qty * it.unitPrice }

        val formattedNumber = "$invoiceNumber/${numberFmt.format(Date(issueDateMillis))}"
        val vatSuffix = if (isVatPayer) " VAT" else ""
        val docKind = context.getString(R.string.invoice_pdf_faktura)
        val docTitle = "$docKind$vatSuffix $formattedNumber"

        val datesHtml = "<b>${context.getString(R.string.invoice_pdf_issue_date)}:</b> ${dateFmt.format(Date(issueDateMillis))}" +
            "&nbsp;&nbsp;&nbsp;<b>${context.getString(R.string.invoice_pdf_sale_date)}:</b> ${dateFmt.format(Date(serviceDateMillis))}"

        val sellerHtml = buildSellerBody(context, seller, isVatPayer)
        val buyerHtml = buildBuyerBody(context, buyerName, buyerNip, buyerStreet, buyerPostalCode, buyerCity, isPhysicalPerson)

        val itemsTableHtml = buildItemsTable(context, null, rows, vatRate) +
            buildSumRow(context, totalAmount, vatRate != null)

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

        // Update 4 (техтребование): компактный футер для 3-5 позиций, чтобы уместилось на 1 страницу.
        val footerCompactClass = if (rows.size in 1..5) "compact-footer" else ""

        val html = loadTemplate(context)
            .replace("{{DOC_TITLE}}", esc(docTitle))
            .replace("{{SUBTITLE_LINE_HTML}}", "")
            .replace("{{DOC_DATES_HTML}}", datesHtml)
            .replace("{{LOGO_IMG_TAG}}", buildLogoImgTag(context))
            .replace("{{BRAND_NAME_HTML}}", "<div class=\"brand-name\">FinArs</div>")
            .replace("{{USER_ICON_SVG}}", USER_ICON)
            .replace("{{SELLER_BODY_HTML}}", sellerHtml)
            .replace("{{BUYER_BODY_HTML}}", buyerHtml)
            .replace("{{ITEMS_TABLES_HTML}}", itemsTableHtml)
            .replace("{{CORRECTION_BLOCK_HTML}}", "")
            .replace("{{FOOTER_COMPACT_CLASS}}", footerCompactClass)
            .replace("{{PAYMENT_INFO_LINES_HTML}}", paymentLinesHtml.toString())
            .replace("{{LEGAL_VAT_BLOCK_HTML}}", legalVatHtml)
            .replace("{{STATUS_CLASS}}", statusClass)
            .replace("{{STATUS_ICON_SVG}}", statusIcon)
            .replace("{{STATUS_TEXT}}", esc(statusText))
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
        vatRate: VatRate? = null
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

        // --- ta sama logika co w InvoicePdfGenerator.generateCorrection: "Przed korektą" ---
        // to oryginalne pozycje, "Po korekcie" to te same pozycje przeskalowane proporcjonalnie
        // do correctedAmount. Logika NIE zmieniona — tylko renderowana w nowym HTML/CSS.
        val fallbackLabel = "${context.getString(R.string.correction_pdf_to_invoice)} $originalFormattedNumber"
        val beforeRows: List<Row> = if (items.isNotEmpty()) items.map { Row(it.name, it.quantity, it.unitPrice) }
            else listOf(Row(fallbackLabel, 1.0, originalAmount))
        val scale = if (originalAmount != 0.0) correctedAmount / originalAmount else 1.0
        val afterRows: List<Row> = if (items.isNotEmpty()) items.map { Row(it.name, it.quantity, it.unitPrice * scale) }
            else listOf(Row(fallbackLabel, 1.0, correctedAmount))

        val tablesHtml = StringBuilder()
        tablesHtml.append(buildItemsTable(context, context.getString(R.string.correction_pdf_before_table_title), beforeRows, vatRate))
        tablesHtml.append(buildItemsTable(context, context.getString(R.string.correction_pdf_after_table_title), afterRows, vatRate))

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
        val rowsTotal = beforeRows.size + afterRows.size
        val footerCompactClass = if (rowsTotal in 1..5) "compact-footer" else ""

        val html = loadTemplate(context)
            .replace("{{DOC_TITLE}}", esc(docTitle))
            .replace("{{SUBTITLE_LINE_HTML}}", subtitle)
            .replace("{{DOC_DATES_HTML}}", datesHtml)
            .replace("{{LOGO_IMG_TAG}}", buildLogoImgTag(context))
            .replace("{{BRAND_NAME_HTML}}", "<div class=\"brand-name\">FinArs</div>")
            .replace("{{USER_ICON_SVG}}", USER_ICON)
            .replace("{{SELLER_BODY_HTML}}", sellerHtml)
            .replace("{{BUYER_BODY_HTML}}", buyerHtml)
            .replace("{{ITEMS_TABLES_HTML}}", tablesHtml.toString())
            .replace("{{CORRECTION_BLOCK_HTML}}", correctionBlockHtml)
            .replace("{{FOOTER_COMPACT_CLASS}}", footerCompactClass)
            // Faktura korygująca nie ma statusu płatności/terminu w oryginalnym generatorze —
            // zostawiamy blok podstawy prawnej VAT, a status pokazujemy jako neutralny placeholder.
            .replace("{{PAYMENT_INFO_LINES_HTML}}", "")
            .replace("{{LEGAL_VAT_BLOCK_HTML}}", legalVatHtml)
            .replace("{{STATUS_CLASS}}", "status-paid")
            .replace("{{STATUS_ICON_SVG}}", CHECK_ICON)
            .replace("{{STATUS_TEXT}}", esc(context.getString(R.string.correction_pdf_title)))
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
        <div class="legal-title">${esc(context.getString(R.string.invoice_pdf_legal_basis_title))}</div>
        <div class="legal-text">${esc(context.getString(R.string.invoice_pdf_legal_basis_text))}</div>
    """.trimIndent()

    private fun infoLine(icon: String?, text: String): String =
        "<div class=\"info-line\">${if (icon != null) "<span class=\"info-icon\">$icon</span>" else "<span class=\"info-icon\"></span>"}<span class=\"info-text\">${esc(text)}</span></div>"

    /** Buduje tabelę pozycji — bez VAT (Lp/Nazwa/Jedn./Ilość/Cena netto/Wartość netto, jak
     *  na dostarczonym makiecie) lub z VAT (dodatkowo Stawka VAT/Kwota VAT/Wartość brutto),
     *  dokładnie ta sama logika kolumn co w InvoicePdfGenerator — tylko jako <table> HTML. */
    private fun buildItemsTable(context: Context, title: String?, rows: List<Row>, vatRate: VatRate?): String {
        val qtyStr: (Double) -> String = { q -> if (q == q.toLong().toDouble()) q.toLong().toString() else q.toString() }
        val money: (Double) -> String = { String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") + " zł" }

        val sb = StringBuilder()
        if (title != null) sb.append("<div class=\"table-title\">${esc(title)}</div>")
        sb.append("<table class=\"items\"><thead><tr>")
        sb.append("<th class=\"col-lp\">${esc(context.getString(R.string.invoice_pdf_table_lp))}</th>")
        sb.append("<th class=\"col-name\">${esc(context.getString(R.string.invoice_pdf_table_name))}</th>")
        sb.append("<th class=\"col-unit\">${esc(context.getString(R.string.invoice_pdf_table_unit))}</th>")
        sb.append("<th class=\"col-qty num\">${esc(context.getString(R.string.invoice_pdf_table_qty))}</th>")
        if (vatRate == null) {
            sb.append("<th class=\"col-price num\">${esc(context.getString(R.string.invoice_pdf_table_price))}</th>")
            sb.append("<th class=\"col-total num\">${esc(context.getString(R.string.invoice_pdf_table_total))}</th>")
        } else {
            sb.append("<th class=\"num\">${esc(context.getString(R.string.invoice_pdf_table_price_netto))}</th>")
            sb.append("<th class=\"num\">${esc(context.getString(R.string.invoice_pdf_table_netto))}</th>")
            sb.append("<th class=\"num\">${esc(context.getString(R.string.invoice_pdf_table_vat_rate))}</th>")
            sb.append("<th class=\"num\">${esc(context.getString(R.string.invoice_pdf_table_vat_amount))}</th>")
            sb.append("<th class=\"num\">${esc(context.getString(R.string.invoice_pdf_table_brutto))}</th>")
        }
        sb.append("</tr></thead><tbody>")

        val vatRateShort = vatRate?.percent?.let { p -> val i = p.toInt(); if (i.toDouble() == p) "$i%" else "$p%" } ?: vatRate?.storageKey

        rows.forEachIndexed { idx, row ->
            sb.append("<tr>")
            sb.append("<td>${idx + 1}</td>")
            sb.append("<td>${esc(row.name)}</td>")
            sb.append("<td>${esc(context.getString(R.string.invoice_pdf_unit_piece))}</td>")
            sb.append("<td class=\"num\">${qtyStr(row.qty)}</td>")
            if (vatRate == null) {
                sb.append("<td class=\"num\">${money(row.unitPrice)}</td>")
                sb.append("<td class=\"num\">${money(row.qty * row.unitPrice)}</td>")
            } else {
                val netValue = row.qty * row.unitPrice
                val vatAmount = vatRate.vatAmount(netValue)
                val bruttoValue = netValue + vatAmount
                sb.append("<td class=\"num\">${money(row.unitPrice)}</td>")
                sb.append("<td class=\"num\">${money(netValue)}</td>")
                sb.append("<td class=\"num\">${vatRateShort}</td>")
                sb.append("<td class=\"num\">${money(vatAmount)}</td>")
                sb.append("<td class=\"num\">${money(bruttoValue)}</td>")
            }
            sb.append("</tr>")
        }
        sb.append("</tbody></table>")
        return sb.toString()
    }

    private fun buildSumRow(context: Context, totalAmount: Double, isVat: Boolean): String {
        val money: (Double) -> String = { String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") + " zł" }
        return """
            <div class="sum-row">
              <div class="sum-label-wrap">${esc(context.getString(R.string.invoice_pdf_sum_label))} DO ZAPŁATY</div>
              <div class="sum-amount">${money(totalAmount)}</div>
            </div>
        """.trimIndent()
    }

    // ============================= LOGO / QR (base64, offline) =============================

    /** Logo w lewym górnym rogu: jeśli użytkownik wgrał własne (patrz [InvoiceLogoStore]) —
     *  pokazujemy je (object-fit:contain, ograniczone przez CSS .brand img.logo), w
     *  przeciwnym razie domyślne logo FinArs (R.drawable.logo) — zgodnie z wymaganiem punktu 3. */
    private fun buildLogoImgTag(context: Context): String {
        val userLogoPath = InvoiceLogoStore.load(context)
        val bitmap: Bitmap? = if (!userLogoPath.isNullOrBlank()) {
            try { BitmapFactory.decodeFile(userLogoPath) } catch (e: Exception) { null }
        } else null
        val bmp = bitmap ?: try {
            BitmapFactory.decodeResource(context.resources, R.drawable.logo)
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

    // Szerokość renderu w px (arbitralna, dobrana pod ostrość); wysokość strony A4 liczona
    // z tej samej proporcji 210:297, żeby cięcie na strony odpowiadało realnym proporcjom A4.
    private const val RENDER_WIDTH_PX = 1000
    private const val A4_RATIO = 297f / 210f
    private val PAGE_HEIGHT_PX = (RENDER_WIDTH_PX * A4_RATIO).toInt()
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
     *  MUSI być wywołane z wątku głównego (WebView) — dlatego przełączamy dispatcher tutaj. */
    private suspend fun renderHtmlToPdf(context: Context, html: String): ByteArray = withContext(Dispatchers.Main) {
        val webView = WebView(context.applicationContext)
        // Ważne: bez software layer Bitmap z view.draw(canvas) często wychodzi pusty/biały,
        // bo WebView domyślnie renderuje się przez warstwę sprzętową powiązaną z oknem,
        // którego tu nie mamy (renderujemy off-screen).
        webView.setLayerType(View.LAYER_TYPE_SOFTWARE, null)
        webView.settings.javaScriptEnabled = true // potrzebne tylko do pomiaru wysokości/pozycji (własny HTML, bez zewnętrznych treści)
        webView.settings.useWideViewPort = false
        webView.settings.loadWithOverviewMode = false
        webView.settings.textZoom = 100

        val fullBitmap: Bitmap = suspendCancellableCoroutine { cont ->
            webView.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, url: String) {
                    // mały odstęp — daje WebView domalować base64-owe obrazy (logo/QR) i fonty
                    // po zdarzeniu onPageFinished, zanim zrobimy zrzut do Bitmapy
                    view.postDelayed({
                        view.evaluateJavascript("document.body.scrollHeight") { heightStr ->
                            val cssHeight = heightStr?.toFloatOrNull()?.toInt() ?: RENDER_WIDTH_PX
                            val totalHeightPx = maxOf(cssHeight, 1)
                            view.measure(
                                View.MeasureSpec.makeMeasureSpec(RENDER_WIDTH_PX, View.MeasureSpec.EXACTLY),
                                View.MeasureSpec.makeMeasureSpec(totalHeightPx, View.MeasureSpec.EXACTLY)
                            )
                            view.layout(0, 0, RENDER_WIDTH_PX, totalHeightPx)
                            val bmp = Bitmap.createBitmap(RENDER_WIDTH_PX, totalHeightPx, Bitmap.Config.ARGB_8888)
                            val canvas = Canvas(bmp)
                            canvas.drawColor(Color.WHITE)
                            view.draw(canvas)
                            if (cont.isActive) cont.resume(bmp)
                        }
                    }, 150)
                }
            }
            webView.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null)
        }

        // Zakresy [top, bottom] w px bitmapy, których NIE wolno przecinać cięciem strony
        val avoidRanges = getAvoidBreakRanges(webView)
        webView.destroy()

        val document = PdfDocument()
        var top = 0
        var pageNumber = 1
        val totalHeight = fullBitmap.height
        while (top < totalHeight) {
            var bottom = minOf(top + PAGE_HEIGHT_PX, totalHeight)
            for (range in avoidRanges) {
                if (top < range.first && bottom in (range.first + 1) until range.second) {
                    bottom = range.first
                    break
                }
            }
            if (bottom <= top) bottom = minOf(top + PAGE_HEIGHT_PX, totalHeight)

            val sliceHeight = bottom - top
            val slice = Bitmap.createBitmap(fullBitmap, 0, top, RENDER_WIDTH_PX, sliceHeight)

            val page = document.startPage(
                PdfDocument.PageInfo.Builder(PDF_PAGE_WIDTH_PT, PDF_PAGE_HEIGHT_PT, pageNumber).create()
            )
            val destHeight = sliceHeight.toFloat() * PDF_PAGE_WIDTH_PT / RENDER_WIDTH_PX
            page.canvas.drawBitmap(slice, null, RectF(0f, 0f, PDF_PAGE_WIDTH_PT.toFloat(), destHeight), null)
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
    }

    /** Zwraca listę [top, bottom] (w px bitmapy) dla każdego elementu .footer-wrap —
     *  używane do trzymania się z dala od cięcia strony w środku tego bloku. */
    private suspend fun getAvoidBreakRanges(webView: WebView): List<Pair<Int, Int>> = suspendCancellableCoroutine { cont ->
        val js = """
            (function(){
                var els = document.querySelectorAll('.footer-wrap');
                var out = [];
                for (var i=0;i<els.length;i++){
                    var r = els[i].getBoundingClientRect();
                    out.push([Math.round(r.top + window.scrollY), Math.round(r.bottom + window.scrollY)]);
                }
                return JSON.stringify(out);
            })();
        """.trimIndent()
        webView.evaluateJavascript(js) { result ->
            val ranges = try {
                val clean = (result ?: "[]").let {
                    var s = it.trim()
                    if (s.startsWith("\"") && s.endsWith("\"")) s = s.substring(1, s.length - 1)
                    s.replace("\\\"", "\"")
                }
                val arr = JSONArray(clean)
                (0 until arr.length()).map { idx ->
                    val pair = arr.getJSONArray(idx)
                    pair.getInt(0) to pair.getInt(1)
                }
            } catch (e: Exception) {
                emptyList()
            }
            if (cont.isActive) cont.resume(ranges)
        }
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
        <rect x="3" y="5" width="18" height="16" rx="2" stroke="#12162E" stroke-width="1.6"/>
        <path d="M3 9h18M8 3v4M16 3v4" stroke="#12162E" stroke-width="1.6" stroke-linecap="round"/>
        </svg>""".trimIndent()
}
