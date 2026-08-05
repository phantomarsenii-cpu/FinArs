package com.example.fa_ksiegowy

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import java.io.OutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Строит PDF-"шпаргалку" для заполнения PIT-36 за выбранный год: личные данные,
 * itogovые Przychód/Koszty/Dochód, расчёт налога и подсказки, в какую строку/раздел
 * официального бланка PIT-36 их перенести.
 *
 * ВАЖНО: это НЕ сам официальный бланк PIT-36 и не готовая e-Deklaracja — номера
 * конкретных клеток бланка каждый год может менять Minister Finansów, поэтому
 * вместо "впишите в поле №105" тут используются названия раздела/строки бланка,
 * которые более стабильны из года в год. Отчёт исключительно информационный
 * (см. дисклеймер в конце документа).
 */
object Pit36PdfGenerator {

    private const val PAGE_WIDTH = 595
    private const val PAGE_HEIGHT = 842
    private const val MARGIN = 48f

    fun generate(context: Context, personal: PitPersonalData, result: Pit36Calculator.Result, out: OutputStream) {
        val document = PdfDocument()
        var pageNumber = 1
        var page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
        var canvas = page.canvas
        var y = MARGIN

        val titlePaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 18f; typeface = Typeface.DEFAULT_BOLD }
        val headerPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 13f; typeface = Typeface.DEFAULT_BOLD }
        val textPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 11f }
        val hintPaint = Paint().apply { color = 0xFF555555.toInt(); textSize = 9.5f }
        val lineGap = 16f

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
        val dateFmt = SimpleDateFormat("dd.MM.yyyy HH:mm", Locale.getDefault())

        line("FinArs — dane pomocnicze do ${result.activityType.formCode} za ${result.year} r.", titlePaint, 26f)
        line("Wygenerowano: ${dateFmt.format(Date())}", hintPaint, 20f)

        line("Dane podatnika", headerPaint, 20f)
        line("Imię i nazwisko: ${personal.firstName} ${personal.lastName}".trim())
        if (personal.pesel.isNotBlank()) line("PESEL: ${personal.pesel}")
        line("Adres: ${personal.street}, ${personal.postalCode} ${personal.city}".trim(' ', ','))
        line("Właściwy urząd skarbowy: ${personal.taxOffice}")
        line("Sposób rozliczenia: " + if (personal.jointWithSpouse) "Wspólnie z małżonkiem" else "Indywidualnie")
        y += 8f

        if (result.activityType.isRegisteredJdg) {
            line("Pozarolnicza działalność gospodarcza — sekcja E.1, wiersz 3", headerPaint, 20f)
            wrappedLines("Wiersz: „Pozarolnicza działalność gospodarcza”.")
        } else {
            line("Działalność nierejestrowana — sekcja E.1, wiersz 8", headerPaint, 20f)
            wrappedLines("Wiersz: „Działalność nierejestrowana, określona w art. 20 ust. 1ba ustawy”.")
        }
        y += 4f
        line("Przychód (kolumna „Przychód”):  ${money(result.przychod)}")
        line("Koszty uzyskania przychodów (kolumna „Koszty uzyskania przychodów”):  ${money(result.koszty)}")
        line("Dochód (kolumna „Dochód”, = Przychód − Koszty):  ${money(result.dochod)}")
        y += 8f

        line("Inne dochody i podatek", headerPaint, 20f)
        when (result.activityType) {
            ActivityType.NIEZAREJESTROWANA, ActivityType.JDG_SKALA -> {
                if (result.otherIncome > 0) {
                    line("Inne dochody podane w ustawieniach (np. PIT-11 z etatu): ${money(result.otherIncome)}")
                }
                line("Łączny dochód do opodatkowania: ${money(result.tax.totalTaxable)}")
                wrappedLines("Skala podatkowa (PIT-36): 0% do 30 000 zł, 12% od nadwyżki ponad 30 000 zł do 120 000 zł, 32% od nadwyżki ponad 120 000 zł.")
            }
            ActivityType.JDG_LINIOWY -> {
                wrappedLines("Podatek liniowy (PIT-36L): stała stawka 19% od całego dochodu, bez kwoty wolnej i bez progów.")
            }
            ActivityType.JDG_RYCZALT -> {
                wrappedLines("Ryczałt od przychodów ewidencjonowanych (PIT-28): podatek liczony od PRZYCHODU (bez pomniejszania o koszty) według stawki właściwej dla wykonywanej działalności (PKD) — ustaw ją w Ustawieniach.")
            }
        }
        line("Podatek przypadający na dochód z tej aplikacji (szacunkowo): ${money(result.tax.tax)}")
        y += 8f

        if (personal.childrenCount > 0 || personal.internetRelief > 0 || personal.ikzeContribution > 0 || personal.donations > 0) {
            line("Ulgi i odliczenia (załącznik PIT/O) — do weryfikacji z aktualnymi limitami", headerPaint, 20f)
            if (personal.childrenCount > 0) line("Liczba dzieci uprawniających do ulgi: ${personal.childrenCount}")
            if (personal.internetRelief > 0) line("Ulga internetowa (poniesiony wydatek): ${money(personal.internetRelief)}")
            if (personal.ikzeContribution > 0) line("Wpłaty na IKZE: ${money(personal.ikzeContribution)}")
            if (personal.donations > 0) line("Darowizny: ${money(personal.donations)}")
            wrappedLines("Kwoty te wpisuje się w załączniku PIT/O do PIT-36 — aplikacja nie pomniejsza automatycznie podatku o te ulgi, ponieważ każda z nich ma własne roczne limity i warunki.")
            y += 8f
        }

        newPageIfNeeded(90f)
        line("Ważne informacje", headerPaint, 20f)
        wrappedLines("• Przychód liczony jest metodą memoriałową (data sprzedaży/wykonania usługi), a Koszty metodą kasową (data faktycznej zapłaty) — zgodnie z zasadami działalności nierejestrowanej.")
        wrappedLines("• Jeśli w ciągu roku otrzymałeś(-aś) PIT-11 (np. z umowy o pracę), dochody z niego należy dodać do PIT-36 ręcznie lub przez kreator w portalu Twój e-PIT — ta aplikacja ich nie zawiera, chyba że zostały wpisane jako „Inne przychody” w ustawieniach.")
        wrappedLines("• Dokument ten nie jest oficjalnym formularzem PIT-36 ani e-Deklaracją — to wyłącznie pomocnicze zestawienie liczb do ręcznego przepisania na portalu podatki.gov.pl (Twój e-PIT) lub do papierowego formularza.")
        y += 6f
        wrappedLines("Aplikacja FinArs ma charakter pomocniczy i nie stanowi oficjalnej porady księgowej ani podatkowej. W razie wątpliwości skonsultuj się z doradcą podatkowym lub urzędem skarbowym.", 92, hintPaint, 13f)

        document.finishPage(page)
        document.writeTo(out)
        document.close()
    }
}
