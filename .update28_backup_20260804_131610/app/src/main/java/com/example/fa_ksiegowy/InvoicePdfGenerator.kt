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
 * sprzedawca jest VAT-owcem, lub Rachunek, gdy nie jest) — bez pozycji NIP
 * nabywcy, z adnotacją o sposobie zapłaty.
 */
object InvoicePdfGenerator {

    private const val PAGE_WIDTH = 595
    private const val PAGE_HEIGHT = 842
    private const val MARGIN = 48f

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
        val document = PdfDocument()
        var pageNumber = 1
        var page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
        var canvas = page.canvas
        var y = MARGIN

        val titlePaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 20f; typeface = Typeface.DEFAULT_BOLD }
        val headerPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 13f; typeface = Typeface.DEFAULT_BOLD }
        val textPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 11.5f }
        val hintPaint = Paint().apply { color = 0xFF555555.toInt(); textSize = 9.5f }
        val lineGap = 17f

        fun newPageIfNeeded(needed: Float) {
            if (y + needed > PAGE_HEIGHT - MARGIN) {
                document.finishPage(page)
                pageNumber++
                page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
                canvas = page.canvas
                y = MARGIN
            }
        }

        fun line(text: String, paint: Paint = textPaint, gap: Float = lineGap) {
            newPageIfNeeded(gap)
            canvas.drawText(text, MARGIN, y, paint)
            y += gap
        }

        fun wrappedLines(text: String, maxCharsPerLine: Int = 92, paint: Paint = hintPaint, gap: Float = 13f) {
            val words = text.split(" ")
            var current = StringBuilder()
            for (w in words) {
                if (current.length + w.length + 1 > maxCharsPerLine) {
                    line(current.toString(), paint, gap)
                    current = StringBuilder()
                }
                if (current.isNotEmpty()) current.append(" ")
                current.append(w)
            }
            if (current.isNotEmpty()) line(current.toString(), paint, gap)
        }

        val money: (Double) -> String = {
            String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") + " zł"
        }
        val dateFmt = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())

        // Dokument bez NIP sprzedawcy to formalnie rachunek, a nie faktura VAT —
        // dobieramy nagłówek automatycznie, żeby nie wprowadzać w błąd.
        val docKind = if (seller.nip.isNotBlank()) "FAKTURA" else "RACHUNEK"
        line("$docKind nr $invoiceNumber", titlePaint, 28f)
        line("Data wystawienia: ${dateFmt.format(Date(issueDateMillis))}", hintPaint, 20f)

        line("Sprzedawca", headerPaint, 20f)
        if (seller.name.isNotBlank()) line(seller.name)
        val sellerAddress = listOfNotNull(
            seller.street.ifBlank { null },
            listOf(seller.postalCode, seller.city).filter { it.isNotBlank() }.joinToString(" ").ifBlank { null }
        ).joinToString(", ")
        if (sellerAddress.isNotBlank()) line(sellerAddress)
        if (seller.nip.isNotBlank()) line("NIP: ${seller.nip}")
        y += 8f

        line("Nabywca", headerPaint, 20f)
        line(buyerName)
        val buyerAddress = listOfNotNull(
            buyerStreet.ifBlank { null },
            listOf(buyerPostalCode, buyerCity).filter { it.isNotBlank() }.joinToString(" ").ifBlank { null }
        ).joinToString(", ")
        if (buyerAddress.isNotBlank()) line(buyerAddress)
        if (!isPhysicalPerson && !buyerNip.isNullOrBlank()) {
            line("NIP: $buyerNip")
        } else {
            wrappedLines("Osoba fizyczna nieprowadząca działalności gospodarczej (bez NIP).")
        }
        y += 10f

        line("Przedmiot sprzedaży", headerPaint, 20f)
        line(serviceName)
        line("Data sprzedaży / wykonania usługi: ${dateFmt.format(Date(serviceDateMillis))}")
        y += 4f
        line("Kwota brutto: ${money(amount)}", headerPaint, 22f)
        y += 4f

        val paymentLabel = context.getString(paymentMethod.paidLabelResId)
        line("Status płatności: $paymentLabel")
        line("Data zapłaty: ${dateFmt.format(Date(paymentDateMillis))}")

        y += 16f
        newPageIfNeeded(60f)
        wrappedLines(
            "Dokument wygenerowany w aplikacji FinArs. Nie stanowi oficjalnej porady księgowej ani podatkowej — " +
                "w razie wątpliwości skonsultuj się z doradcą podatkowym.",
            92, hintPaint, 13f
        )

        document.finishPage(page)
        document.writeTo(out)
        document.close()
    }
}
