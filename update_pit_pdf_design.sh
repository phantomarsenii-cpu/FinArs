#!/data/data/com.termux/files/usr/bin/bash
# Обновление дизайна вспомогательных PIT-36 / PIT-36L / PIT-28 (табличная вёрстка).
# Запускать из корня репозитория FA_ksiegowy в Termux.
set -e

REPO_ROOT="$(pwd)"
TARGET="$REPO_ROOT/app/src/main/java/com/example/fa_ksiegowy/Pit36PdfGenerator.kt"

if [ ! -f "$TARGET" ]; then
  echo "Не найден файл: $TARGET"
  echo "Запусти скрипт из корня репозитория (там, где папка app/)."
  exit 1
fi

echo "Делаю резервную копию текущего файла..."
cp "$TARGET" "$TARGET.bak_$(date +%Y%m%d_%H%M%S)"

echo "Записываю новый дизайн (табличная вёрстка) в Pit36PdfGenerator.kt..."
cat > "$TARGET" << 'KOTLIN_EOF'
package com.example.fa_ksiegowy

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import java.io.OutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Строит PDF-"шпаргалку" для заполнения PIT-36 / PIT-36L / PIT-28 (в зависимости от
 * result.activityType) за выбранный год: личные данные, itogovые Przychód/Koszty/Dochód,
 * расчёт налога и подсказки, в какую строку/раздел официального бланка их перенести.
 *
 * Вёрстка табличная: каждое значение — отдельная ячейка с фиксированной шириной колонки,
 * поэтому цифры/подписи физически не могут наехать на линии сетки. Если текст не помещается
 * в ширину колонки, он переносится на несколько строк внутри той же ячейки (высота строки
 * таблицы увеличивается автоматически), а не выходит за границы.
 *
 * ВАЖНО: это НЕ сам официальный бланк и не готовая e-Deklaracja — номера конкретных клеток
 * бланка каждый год может менять Minister Finansów, поэтому вместо "впишите в поле №105" тут
 * используются названия раздела/строки бланка, которые более стабильны из года в год.
 * Отчёт исключительно информационный (см. дисклеймер в конце документа).
 */
object Pit36PdfGenerator {

    private const val PAGE_WIDTH = 595
    private const val PAGE_HEIGHT = 842
    private const val MARGIN = 40f
    private val CONTENT_WIDTH = PAGE_WIDTH - 2 * MARGIN

    // Палитра
    private const val COLOR_NAVY = 0xFF12162E.toInt()
    private const val COLOR_NAVY_SOFT = 0xFF1F2547.toInt()
    private const val COLOR_ACCENT = 0xFF2F6FED.toInt()
    private const val COLOR_LINE = 0xFFD8DCE6.toInt()
    private const val COLOR_ZEBRA = 0xFFF5F7FB.toInt()
    private const val COLOR_MUTED = 0xFF6B7280.toInt()
    private const val COLOR_HEADER_BG = 0xFFEEF2FB.toInt()
    private const val COLOR_TOTAL_BG = 0xFFEAF1FE.toInt()
    private const val COLOR_NOTE_BG = 0xFFF7F9FD.toInt()

    /** Описание одной колонки в строке таблицы. */
    private data class Col(
        val text: String,
        val weight: Float,
        val paint: Paint,
        val alignRight: Boolean = false
    )

    fun generate(context: Context, personal: PitPersonalData, result: Pit36Calculator.Result, out: OutputStream) {
        val document = PdfDocument()
        var pageNumber = 1
        var page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
        var canvas: Canvas = page.canvas
        var y = MARGIN

        // ---- Paints ----
        val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = COLOR_NAVY; textSize = 16f; typeface = Typeface.DEFAULT_BOLD }
        val subPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = COLOR_MUTED; textSize = 9f }
        val sectionPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; textSize = 10.5f; typeface = Typeface.DEFAULT_BOLD }
        val sectionRefPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFFC7D2FE.toInt(); textSize = 8.5f; typeface = Typeface.DEFAULT_BOLD }
        val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = COLOR_MUTED; textSize = 9.5f }
        val valuePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = COLOR_NAVY; textSize = 9.5f; typeface = Typeface.DEFAULT_BOLD }
        val headerCellPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = COLOR_NAVY; textSize = 8.5f; typeface = Typeface.DEFAULT_BOLD }
        val totalLabelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = COLOR_NAVY; textSize = 9.5f; typeface = Typeface.DEFAULT_BOLD }
        val totalValuePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = COLOR_ACCENT; textSize = 10.5f; typeface = Typeface.DEFAULT_BOLD }
        val hintPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF33384A.toInt(); textSize = 9f }
        val disclaimerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = COLOR_MUTED; textSize = 8f }
        val badgeTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; textSize = 9f; typeface = Typeface.DEFAULT_BOLD }

        val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = COLOR_LINE; style = Paint.Style.STROKE; strokeWidth = 0.8f }
        val zebraFill = Paint().apply { color = COLOR_ZEBRA; style = Paint.Style.FILL }
        val headerFill = Paint().apply { color = COLOR_HEADER_BG; style = Paint.Style.FILL }
        val totalFill = Paint().apply { color = COLOR_TOTAL_BG; style = Paint.Style.FILL }
        val sectionFill = Paint().apply { color = COLOR_NAVY_SOFT; style = Paint.Style.FILL }
        val noteFill = Paint().apply { color = COLOR_NOTE_BG; style = Paint.Style.FILL }
        val noteAccentFill = Paint().apply { color = COLOR_ACCENT; style = Paint.Style.FILL }
        val badgeFill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = COLOR_ACCENT; style = Paint.Style.FILL }
        val dashedPaint = Paint().apply {
            color = COLOR_LINE; style = Paint.Style.STROKE; strokeWidth = 0.8f
            pathEffect = DashPathEffect(floatArrayOf(3f, 2f), 0f)
        }

        fun newPageIfNeeded(needed: Float) {
            if (y + needed > PAGE_HEIGHT - MARGIN) {
                document.finishPage(page)
                pageNumber++
                page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
                canvas = page.canvas
                y = MARGIN
            }
        }

        /** Разбивает текст на строки так, чтобы каждая помещалась в maxWidth (по словам). */
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

        val cellPad = 6f
        val lineH = 11.5f

        /** Рисует одну строку таблицы с произвольным числом колонок (по весам). Строка может
         * разбиться переносом на следующую страницу целиком, чтобы не резать ячейку пополам. */
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
            // Границы ячейки: контур строки + внутренние вертикальные разделители
            canvas.drawRect(MARGIN, top, MARGIN + CONTENT_WIDTH, bottom, borderPaint)
            var vx = MARGIN
            for (i in 0 until cols.size - 1) {
                vx += widths[i]
                canvas.drawLine(vx, top, vx, bottom, borderPaint)
            }
            y = bottom
        }

        fun dataTable(rows: List<Pair<String, String>>) {
            rows.forEachIndexed { idx, (label, value) ->
                tableRow(
                    listOf(Col(label, 0.42f, labelPaint), Col(value, 0.58f, valuePaint, alignRight = true)),
                    bg = if (idx % 2 == 1) zebraFill else null
                )
            }
        }

        fun sectionHeader(title: String, formRef: String? = null) {
            newPageIfNeeded(18f + 6f)
            y += 6f
            val h = 18f
            newPageIfNeeded(h)
            canvas.drawRect(MARGIN, y, MARGIN + CONTENT_WIDTH, y + h, sectionFill)
            canvas.drawText(title, MARGIN + 8f, y + h - 5.5f, sectionPaint)
            if (formRef != null) {
                val w = sectionRefPaint.measureText(formRef)
                canvas.drawText(formRef, MARGIN + CONTENT_WIDTH - 8f - w, y + h - 5.5f, sectionRefPaint)
            }
            y += h
        }

        fun noteBox(text: String) {
            val innerWidth = CONTENT_WIDTH - 14f - 2 * cellPad
            val lines = wrap(text, hintPaint, innerWidth)
            val boxH = lines.size * lineH + 2 * cellPad
            newPageIfNeeded(boxH + 6f)
            y += 4f
            newPageIfNeeded(boxH)
            canvas.drawRect(MARGIN, y, MARGIN + CONTENT_WIDTH, y + boxH, noteFill)
            canvas.drawRect(MARGIN, y, MARGIN + 3f, y + boxH, noteAccentFill)
            var ty = y + cellPad + lineH - 3f
            for (l in lines) {
                canvas.drawText(l, MARGIN + 14f, ty, hintPaint)
                ty += lineH
            }
            y += boxH
        }

        val money: (Double) -> String = {
            String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") + " zł"
        }
        val dateFmt = SimpleDateFormat("dd.MM.yyyy HH:mm", Locale.getDefault())

        // ---- Шапка документа ----
        val badgeText = "${result.activityType.formCode} · ${result.year}"
        val badgeW = badgeTextPaint.measureText(badgeText) + 16f
        canvas.drawRoundRect(RectF(MARGIN + CONTENT_WIDTH - badgeW, y, MARGIN + CONTENT_WIDTH, y + 16f), 3f, 3f, badgeFill)
        canvas.drawText(badgeText, MARGIN + CONTENT_WIDTH - badgeW + 8f, y + 11.5f, badgeTextPaint)
        y += 24f

        canvas.drawText("FA Księgowy — dane pomocnicze do ${result.activityType.formCode} za ${result.year} r.", MARGIN, y, titlePaint)
        y += 14f
        canvas.drawText("Wygenerowano: ${dateFmt.format(Date())} · dokument pomocniczy, nie jest oficjalnym formularzem", MARGIN, y, subPaint)
        y += 10f

        // ---- Dane podatnika ----
        sectionHeader("Dane podatnika")
        val personalRows = mutableListOf(
            "Imię i nazwisko" to "${personal.firstName} ${personal.lastName}".trim(),
        )
        if (personal.pesel.isNotBlank()) personalRows.add("PESEL" to personal.pesel)
        personalRows.add("Adres" to "${personal.street}, ${personal.postalCode} ${personal.city}".trim(' ', ','))
        personalRows.add("Właściwy urząd skarbowy" to personal.taxOffice)

        val allowsJointFiling = result.activityType == ActivityType.NIEZAREJESTROWANA ||
            result.activityType == ActivityType.JDG_SKALA
        val hasSpouseData = personal.jointWithSpouse &&
            (personal.spouseFirstName.isNotBlank() || personal.spouseLastName.isNotBlank() || personal.spouseId.isNotBlank())
        val showSpouseSection = allowsJointFiling && hasSpouseData

        personalRows.add(
            "Sposób rozliczenia" to if (showSpouseSection) "Wspólnie z małżonkiem" else "Indywidualnie"
        )
        dataTable(personalRows)

        if (personal.jointWithSpouse && !allowsJointFiling) {
            noteBox("Zaznaczono „rozliczenie wspólne”, ale przy tej formie opodatkowania (${result.activityType.formCode}) przepisy nie pozwalają na wspólne rozliczenie z małżonkiem — dane małżonka nie są tu uwzględniane.")
        }

        if (showSpouseSection) {
            sectionHeader("Dane małżonka", "rozliczenie wspólne")
            val idLabel = if (personal.spouseIsNip) "NIP" else "PESEL"
            val spouseRows = mutableListOf(
                "Imię i nazwisko" to "${personal.spouseFirstName} ${personal.spouseLastName}".trim(),
                idLabel to personal.spouseId
            )
            if (personal.spouseBirthDate.isNotBlank()) spouseRows.add("Data urodzenia" to personal.spouseBirthDate)
            if (personal.spouseIncome > 0) spouseRows.add("Dochód małżonka (informacyjnie)" to money(personal.spouseIncome))
            dataTable(spouseRows)
        }

        // ---- Rozliczenie działalności ----
        if (result.activityType.isRegisteredJdg) {
            sectionHeader("Rozliczenie działalności", "sekcja E.1, wiersz 3")
        } else {
            sectionHeader("Rozliczenie działalności", "sekcja E.1, wiersz 8")
        }
        tableRow(listOf(Col("Pozycja", 0.55f, headerCellPaint), Col("Kwota", 0.45f, headerCellPaint, alignRight = true)), bg = headerFill)
        dataTable(
            listOf(
                "Przychód" to money(result.przychod),
                "Koszty uzyskania przychodów" to money(result.koszty)
            )
        )
        tableRow(
            listOf(
                Col("Dochód (Przychód − Koszty)", 0.55f, totalLabelPaint),
                Col(money(result.dochod), 0.45f, totalValuePaint, alignRight = true)
            ),
            bg = totalFill
        )

        // ---- Podatek ----
        sectionHeader("Podatek", if (showSpouseSection) "dane orientacyjne, iloraz małżeński" else null)
        when (result.activityType) {
            ActivityType.NIEZAREJESTROWANA, ActivityType.JDG_SKALA -> {
                val rows = mutableListOf<Pair<String, String>>()
                if (result.otherIncome > 0) rows.add("Inne dochody (np. PIT-11 z etatu)" to money(result.otherIncome))
                rows.add("Łączny dochód do opodatkowania" to money(result.tax.totalTaxable))
                if (rows.isNotEmpty()) dataTable(rows)
                tableRow(
                    listOf(
                        Col("Podatek przypadający na dochód z tej aplikacji (szacunkowo)", 0.62f, totalLabelPaint),
                        Col(money(result.tax.tax), 0.38f, totalValuePaint, alignRight = true)
                    ),
                    bg = totalFill
                )
                y += 4f
                tableRow(listOf(Col("Próg dochodu", 0.55f, headerCellPaint), Col("Stawka", 0.45f, headerCellPaint, alignRight = true)), bg = headerFill)
                dataTable(
                    listOf(
                        "do 30 000 zł" to "0%",
                        "30 000 – 120 000 zł" to "12% od nadwyżki",
                        "powyżej 120 000 zł" to "32% od nadwyżki"
                    )
                )
                if (showSpouseSection) {
                    noteBox("Podatek liczony przy ilorazie małżeńskim (dochody obojga małżonków dzielone na dwa) aplikacja nie oblicza automatycznie — to wymaga pełnych danych obojga małżonków za rok. Powyższa kwota to podatek wyłącznie od dochodu z tej aplikacji; ostateczne rozliczenie wspólne najlepiej zweryfikować w usłudze Twój e-PIT.")
                }
            }
            ActivityType.JDG_LINIOWY -> {
                tableRow(
                    listOf(
                        Col("Podatek liniowy (19% × dochód)", 0.62f, totalLabelPaint),
                        Col(money(result.tax.tax), 0.38f, totalValuePaint, alignRight = true)
                    ),
                    bg = totalFill
                )
                noteBox("Podatek liniowy PIT-36L: stała stawka 19% od całego dochodu, bez kwoty wolnej, bez progów podatkowych i bez możliwości wspólnego rozliczenia z małżonkiem.")
            }
            ActivityType.JDG_RYCZALT -> {
                tableRow(listOf(Col("Stawka ryczałtu", 0.35f, headerCellPaint), Col("Przychód", 0.35f, headerCellPaint, alignRight = true), Col("Ryczałt", 0.30f, headerCellPaint, alignRight = true)), bg = headerFill)
                tableRow(
                    listOf(
                        Col("wg PKD (Ustawienia)", 0.35f, valuePaint),
                        Col(money(result.przychod), 0.35f, valuePaint, alignRight = true),
                        Col(money(result.tax.tax), 0.30f, totalValuePaint, alignRight = true)
                    ),
                    bg = totalFill
                )
                noteBox("Ryczałt od przychodów ewidencjonowanych (PIT-28) liczony jest od PRZYCHODU, bez pomniejszania o koszty, wg stawki właściwej dla wykonywanej działalności (PKD) ustawionej w Ustawieniach aplikacji. Wspólne rozliczenie z małżonkiem nie jest tu możliwe.")
            }
        }

        // ---- Ulgi i odliczenia ----
        if (personal.childrenCount > 0 || personal.internetRelief > 0 || personal.ikzeContribution > 0 || personal.donations > 0) {
            sectionHeader("Ulgi i odliczenia", "załącznik PIT/O")
            val reliefRows = mutableListOf<Pair<String, String>>()
            if (personal.childrenCount > 0) reliefRows.add("Liczba dzieci uprawniających do ulgi" to personal.childrenCount.toString())
            if (personal.internetRelief > 0) reliefRows.add("Ulga internetowa (poniesiony wydatek)" to money(personal.internetRelief))
            if (personal.ikzeContribution > 0) reliefRows.add("Wpłaty na IKZE" to money(personal.ikzeContribution))
            if (personal.donations > 0) reliefRows.add("Darowizny" to money(personal.donations))
            dataTable(reliefRows)
            noteBox("Kwoty te wpisuje się w załączniku PIT/O — aplikacja nie pomniejsza automatycznie podatku o te ulgi, ponieważ każda z nich ma własne roczne limity i warunki, które warto zweryfikować przed wysyłką deklaracji.")
        }

        // ---- Ważne informacje ----
        sectionHeader("Ważne informacje")
        noteBox("Przychód liczony jest metodą memoriałową (data sprzedaży/wykonania usługi), a Koszty metodą kasową (data faktycznej zapłaty).")
        noteBox("Jeśli w ciągu roku otrzymałeś(-aś) PIT-11 (np. z umowy o pracę), dochody z niego należy dodać do deklaracji ręcznie lub przez kreator w portalu Twój e-PIT — ta aplikacja ich nie zawiera, chyba że zostały wpisane jako „Inne przychody” w ustawieniach.")
        noteBox("Dokument ten nie jest oficjalnym formularzem ani e-Deklaracją — to wyłącznie pomocnicze zestawienie liczb do ręcznego przepisania na portalu podatki.gov.pl (Twój e-PIT) lub do papierowego formularza.")

        // ---- Disclaimer ----
        newPageIfNeeded(28f)
        y += 4f
        canvas.drawLine(MARGIN, y, MARGIN + CONTENT_WIDTH, y, dashedPaint)
        y += 10f
        val disclaimerLines = wrap(
            "Aplikacja FA Księgowy ma charakter pomocniczy i nie stanowi oficjalnej porady księgowej ani podatkowej. W razie wątpliwości skonsultuj się z doradcą podatkowym lub urzędem skarbowym.",
            disclaimerPaint, CONTENT_WIDTH
        )
        for (l in disclaimerLines) {
            newPageIfNeeded(11f)
            canvas.drawText(l, MARGIN, y, disclaimerPaint)
            y += 11f
        }

        document.finishPage(page)
        document.writeTo(out)
        document.close()
    }
}

KOTLIN_EOF

echo "Готово. Файл обновлён: $TARGET"

echo "git add / commit..."
git add "$TARGET"
git commit -m "PIT PDF: новый табличный дизайн вспомогательных PIT-36/36L/28 (границы ячеек, авто-перенос текста, блок супруга при совместном рассчитывании)"

echo ""
echo "Коммит создан локально. Чтобы отправить на GitHub, выполни:"
echo "  git push"
