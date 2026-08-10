package com.example.fa_ksiegowy

import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.regex.Pattern
import kotlin.coroutines.resume

/** Одна позиция (товар/услуга) с чека. price = null, если цену не удалось выделить отдельно. */
data class ReceiptItem(val name: String, val price: Double?)

data class ReceiptOcrResult(
    val amount: Double?,
    val dateMillis: Long?,
    val sellerName: String?,
    val items: List<ReceiptItem>,
    val rawText: String
)

/**
 * Распознавание чека по фото: сумма, дата, продавец и построчный список купленных
 * позиций (название + цена) — чтобы их не приходилось переписывать в комментарий
 * вручную. Используется латинский распознаватель ML Kit (Google не выпускает
 * on-device модель для кириллицы) — но цифры (сумма/дата/цены) он читает
 * одинаково хорошо независимо от языка чека, так что автозаполнение суммы и
 * даты работает и на русскоязычных чеках. Название продавца и позиций,
 * написанное кириллицей, может распознаваться менее точно — в этом случае
 * пользователь просто донабирает недостающее руками. Всё выполняется на
 * устройстве, интернет не нужен.
 */
object ReceiptOcrHelper {

    suspend fun recognize(bitmap: Bitmap): ReceiptOcrResult {
        val text = recognizeText(bitmap)
        return ReceiptOcrResult(
            amount = extractAmount(text),
            dateMillis = extractDate(text),
            sellerName = extractSeller(text),
            items = extractItems(text),
            rawText = text
        )
    }

    private suspend fun recognizeText(bitmap: Bitmap): String {
        val image = InputImage.fromBitmap(bitmap, 0)
        return runRecognizer(TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS), image)
    }

    private suspend fun runRecognizer(recognizer: TextRecognizer, image: InputImage): String =
        suspendCancellableCoroutine { cont ->
            recognizer.process(image)
                .addOnSuccessListener { visionText -> if (cont.isActive) cont.resume(visionText.text) }
                .addOnFailureListener { if (cont.isActive) cont.resume("") }
        }

    // Ключевые слова, однозначно указывающие на итог "к оплате" — самые надёжные,
    // им отдаётся приоритет перед более общими "SUMA"/"RAZEM" (те могут встречаться
    // и в промежуточных строках разбивки по ставкам НДС/PTU, а не только в итоге).
    private val STRONG_TOTAL_KEYWORDS = listOf(
        "DO ZAPLATY", "DO ZAPŁATY", "ZAPŁATA", "SUMA PLN", "К ОПЛАТЕ", "ИТОГО"
    )
    private val WEAK_TOTAL_KEYWORDS = listOf("SUMA", "RAZEM", "TOTAL", "ИТОГ", "WARTOSC", "WARTOŚĆ")
    private val amountPattern: Pattern = Pattern.compile("(\\d{1,6}[.,]\\d{2})")

    /**
     * Сумма чека. Сначала ищем строки с самыми однозначными ключевыми словами
     * ("do zapłaty" и т.п.) — среди них берём последнее совпадение по тексту чека
     * (финальный итог печатается ниже промежуточных сумм). Если таких строк нет —
     * то же самое для более общих слов (RAZEM/SUMA/TOTAL). Если и их нет — берём
     * наибольшее число на чеке (эвристика: итоговая сумма обычно больше цены
     * любой отдельной позиции).
     */
    private fun extractAmount(text: String): Double? {
        var strong: Double? = null
        var weak: Double? = null
        for (line in text.lines()) {
            val upper = line.uppercase(Locale.ROOT)
            val m = amountPattern.matcher(line)
            if (!m.find()) continue
            val value = normalizeNumber(m.group(1)) ?: continue
            when {
                STRONG_TOTAL_KEYWORDS.any { upper.contains(it) } -> strong = value
                WEAK_TOTAL_KEYWORDS.any { upper.contains(it) } -> weak = value
            }
        }
        if (strong != null) return strong
        if (weak != null) return weak
        var max: Double? = null
        val m = amountPattern.matcher(text)
        while (m.find()) {
            val v = normalizeNumber(m.group(1))
            if (v != null && (max == null || v > max!!)) max = v
        }
        return max
    }

    private fun normalizeNumber(raw: String): Double? = raw.replace(",", ".").toDoubleOrNull()

    private val DATE_PATTERNS = listOf(
        "dd.MM.yyyy" to Pattern.compile("(\\d{2}[.]\\d{2}[.]\\d{4})"),
        "dd-MM-yyyy" to Pattern.compile("(\\d{2}-\\d{2}-\\d{4})"),
        "yyyy-MM-dd" to Pattern.compile("(\\d{4}-\\d{2}-\\d{2})")
    )

    private fun extractDate(text: String): Long? {
        for ((format, pattern) in DATE_PATTERNS) {
            val m = pattern.matcher(text)
            if (m.find()) {
                return try {
                    SimpleDateFormat(format, Locale.getDefault()).parse(m.group(1))?.time
                } catch (e: Exception) {
                    null
                }
            }
        }
        return null
    }

    // Строки чека, которые точно НЕ название продавца и НЕ отдельная позиция товара:
    // номер документа/paragonu, NIP, телефон, касса/кассир, дата, способ оплаты и т.п.
    private val SELLER_SKIP_KEYWORDS = listOf(
        "PARAGON", "NR.", "NR:", " NR ", "NIP", "TEL", "TEL.", "TEL:", "KASA", "KASJER",
        "FISKALNY", "FISKALNA", "NUMER", "ID:", "REGON", "ADRES", "SIEDZIB", "UL.",
        "ЧЕК", "КАССА", "КАССИР", "НОМЕР", "ИНН", "ТЕЛ"
    )
    private val DATE_LIKE: Pattern = Pattern.compile("\\d{1,4}[./-]\\d{1,2}[./-]\\d{1,4}")
    private val POSTAL_CODE_LIKE: Pattern = Pattern.compile("\\d{2}-\\d{3}")
    private val MOSTLY_DIGITS: Pattern = Pattern.compile("^[\\s0-9:\\-./#]+$")

    /** Ищет наиболее похожую на название продавца строку чека: пропускает номера
     *  документа/NIP/телефона/адреса/даты и строки, где цифр больше, чем букв. */
    private fun extractSeller(text: String): String? {
        for (rawLine in text.lines()) {
            val line = rawLine.trim()
            if (line.length !in 3..40) continue
            val upper = line.uppercase(Locale.ROOT)
            if (SELLER_SKIP_KEYWORDS.any { upper.contains(it) }) continue
            if (STRONG_TOTAL_KEYWORDS.any { upper.contains(it) } || WEAK_TOTAL_KEYWORDS.any { upper.contains(it) }) continue
            if (MOSTLY_DIGITS.matcher(line).matches()) continue
            if (DATE_LIKE.matcher(line).find()) continue
            if (POSTAL_CODE_LIKE.matcher(line).find()) continue
            val letters = line.count { it.isLetter() }
            if (letters < line.length / 2) continue
            return line
        }
        return null
    }

    // Строки, которые встречаются в "подвале"/"шапке" чека и точно не являются
    // купленным товаром/услугой (итоги, налоги, способ оплаты, реквизиты,
    // благодарности и т.п.) — такие строки пропускаем при поиске позиций покупки.
    private val ITEM_SKIP_KEYWORDS = SELLER_SKIP_KEYWORDS + STRONG_TOTAL_KEYWORDS + WEAK_TOTAL_KEYWORDS + listOf(
        "PTU", "VAT", "PODATEK", "GOTOWKA", "GOTÓWKA", "KARTA", "RESZTA", "SPRZEDAWCA",
        "SPRZEDAJACY", "SPRZEDAJĄCY", "DZIEKUJEMY", "DZIĘKUJEMY", "ZAPRASZAMY", "WYDANO",
        "PODPIS", "MIASTO", "%",
        "НАЛИЧНЫМИ", "БЕЗНАЛИЧНЫМИ", "КАРТОЙ", "СДАЧА", "ПРОДАВЕЦ", "СПАСИБО", "НАЛОГ",
        // Добавлено после разбора реального чека Lidl: строки разбивки продаж по
        // ставке НДС ("SPRZEDAŻ OPODATKOWANA A"), скидка отдельной строкой ("OPUST"),
        // блок программы лояльности ("zaoszczędzono ...") — раньше эти строки
        // ошибочно попадали в список товаров.
        "OPODATKOWAN", "OPUST", "ZAOSZCZ", "ROZLICZENIE", "PLATNOSCI", "PŁATNOŚCI",
        "NIEFISKALNY", "WAZNA DO", "WAŻNA DO", "CONTACTLESS", "MASTERCARD", "VISA", "DEBIT"
    )

    // Строка вида "название товара ... цена" — цена (формат 0,00) в конце строки,
    // опционально с валютой (zł/PLN) и/или буквой ставки НДС сразу после. Так
    // распознаются позиции чеков без явного количества, например
    // "Chleb pszenny            4,50 B".
    private val itemLinePattern: Pattern =
        Pattern.compile("^(.{2,45}?)\\s+(\\d{1,4}[.,]\\d{2})\\s*(?:zl|zł|PLN|pln)?\\s*[A-Za-z]?\\*?$", Pattern.CASE_INSENSITIVE)

    // Строка вида "название [код_НДС] количество xцена_за_шт  сумма[код_НДС]" —
    // самый частый формат польских фискальных чеков (Lidl, Biedronka, Żabka и
    // т.п.), например "Arbuz luz    F    4,524 x3,99  18,05C" или
    // "Chleb Baltonowski  F  1 x2,29    2,29C". Проверяется ПЕРВЫМ, так как
    // раньше именно такие строки не распознавались вовсе (не было паттерна под
    // "количество x цена"), и в комментарий попадала не позиция чека, а мусор.
    private val itemQtyLinePattern: Pattern = Pattern.compile(
        "^(.{2,40}?)\\s+[A-Za-z]?\\s*\\d+[.,]?\\d*\\s*[xX×]\\s*\\d{1,4}[.,]\\d{2}\\s+(\\d{1,4}[.,]\\d{2})\\s*(?:zl|zł|PLN|pln)?\\s*[A-Za-z]?\\*?$",
        Pattern.CASE_INSENSITIVE
    )
    private val LEADING_QTY: Pattern = Pattern.compile("^\\d+[.,]?\\d*\\s*(x|X|szt\\.?|×)\\s*")

    /**
     * Построчно вытаскивает позиции покупки (название + цена) — то, что раньше
     * приходилось переписывать в комментарий вручную. Сначала пробуем формат
     * "количество x цена" (самый частый на реальных чеках), затем — формат
     * без количества (просто цена в конце строки). Строки-итоги/налоги/реквизиты
     * отфильтровываются по ключевым словам, поэтому итоговая сумма чека не
     * попадает в список как отдельный "товар".
     */
    private fun extractItems(text: String): List<ReceiptItem> {
        val amountTotal = extractAmount(text)
        val items = mutableListOf<ReceiptItem>()
        for (rawLine in text.lines()) {
            val line = rawLine.trim()
            if (line.length !in 5..60) continue
            val upper = line.uppercase(Locale.ROOT)
            if (ITEM_SKIP_KEYWORDS.any { upper.contains(it) }) continue

            val qtyMatch = itemQtyLinePattern.matcher(line)
            val m = if (qtyMatch.matches()) qtyMatch else itemLinePattern.matcher(line).takeIf { it.matches() }
            if (m == null) continue

            val price = normalizeNumber(m.group(2)) ?: continue
            var name = m.group(1).trim().trimEnd('*', '-', ':', '.', ' ')
            name = LEADING_QTY.matcher(name).replaceFirst("").trim()
            if (name.isBlank()) name = m.group(1).trim()
            if (name.length < 2) continue
            val letters = name.count { it.isLetter() }
            if (letters < 2) continue
            // Если итоговая строка ("Suma PLN 188,54") не попала под ключевые слова
            // из-за опечатки OCR, но цена совпадает с общей суммой чека, а "название" —
            // короткий цифро-буквенный мусор, это почти наверняка итог, а не товар.
            if (amountTotal != null && price == amountTotal && letters <= 3) continue
            items.add(ReceiptItem(name, price))
        }
        return items
    }
}

