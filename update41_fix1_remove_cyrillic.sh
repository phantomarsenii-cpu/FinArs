#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=== Update 41 fix 1: убираю несуществующую зависимость com.google.mlkit:text-recognition-cyrillic ==="
echo "У Google ML Kit нет on-device распознавателя для кириллицы (только Latin/Chinese/Japanese/Korean/Devanagari)."
echo "Оставляю только латинский распознаватель — цифры (сумма, дата) он читает нормально на любом чеке."
echo ""

if [ ! -f "settings.gradle" ] || [ ! -f "app/src/main/java/com/example/fa_ksiegowy/ReceiptOcrHelper.kt" ]; then
    echo "!!! Запусти скрипт из корня проекта FA_ksiegowy (там, где settings.gradle)"
    exit 1
fi

BACKUP_DIR=".update41_fix1_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR/app/src/main/java/com/example/fa_ksiegowy"
cp app/build.gradle "$BACKUP_DIR/app/build.gradle"
cp app/src/main/java/com/example/fa_ksiegowy/ReceiptOcrHelper.kt "$BACKUP_DIR/app/src/main/java/com/example/fa_ksiegowy/ReceiptOcrHelper.kt"
echo "--- Бэкап сохранён в $BACKUP_DIR ---"

python3 - << 'PYEOF_U41FIX1_GRADLE'
path = "app/build.gradle"
text = open(path, encoding="utf-8").read()
old = '''    // Update 41: OCR чеков (ML Kit, работает на устройстве, без интернета)
    implementation "com.google.mlkit:text-recognition:16.0.0"
    implementation "com.google.mlkit:text-recognition-cyrillic:16.0.0"
'''
new = '''    // Update 41: OCR чеков (ML Kit, работает на устройстве, без интернета).
    // Примечание: у Google ML Kit нет on-device модели для кириллицы, поэтому
    // используется только латинский распознаватель (он же нормально читает цифры).
    implementation "com.google.mlkit:text-recognition:16.0.0"
'''
if old not in text:
    raise SystemExit("ANCHOR NOT FOUND in app/build.gradle — возможно, уже пофикшено")
text = text.replace(old, new, 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF_U41FIX1_GRADLE
echo "OK: app/build.gradle"

cat > app/src/main/java/com/example/fa_ksiegowy/ReceiptOcrHelper.kt << 'EOF_U41FIX1_RECEIPTOCRHELPER_KT'
package com.example.fa_ksiegowy

import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.TextRecognizerOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.regex.Pattern
import kotlin.coroutines.resume

data class ReceiptOcrResult(
    val amount: Double?,
    val dateMillis: Long?,
    val sellerName: String?,
    val rawText: String
)

/**
 * Распознавание чека по фото: сумма, дата, название продавца (первая строка чека).
 * Используется латинский распознаватель ML Kit (Google не выпускает on-device
 * модель для кириллицы) — но цифры (сумма/дата) он читает одинаково хорошо
 * независимо от языка чека, так что автозаполнение суммы и даты работает и на
 * русскоязычных чеках. Название продавца, написанное кириллицей, может
 * распознаваться менее точно — в этом случае пользователь просто впишет его сам.
 * Всё выполняется на устройстве, интернет не нужен.
 */
object ReceiptOcrHelper {

    suspend fun recognize(bitmap: Bitmap): ReceiptOcrResult {
        val text = recognizeText(bitmap)
        return ReceiptOcrResult(
            amount = extractAmount(text),
            dateMillis = extractDate(text),
            sellerName = extractSeller(text),
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

    private val AMOUNT_KEYWORDS = listOf("SUMA", "RAZEM", "ИТОГО", "ИТОГ", "TOTAL", "DO ZAPLATY", "DO ZAPŁATY", "ZAPŁATA", "К ОПЛАТЕ")
    private val amountPattern: Pattern = Pattern.compile("(\\d{1,6}[.,]\\d{2})")

    private fun extractAmount(text: String): Double? {
        for (line in text.lines()) {
            val upper = line.uppercase(Locale.ROOT)
            if (AMOUNT_KEYWORDS.any { upper.contains(it) }) {
                val m = amountPattern.matcher(line)
                if (m.find()) return normalizeNumber(m.group(1))
            }
        }
        val m = amountPattern.matcher(text)
        var max: Double? = null
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

    private fun extractSeller(text: String): String? =
        text.lines().map { it.trim() }.firstOrNull { it.isNotBlank() && it.length in 3..40 }
}
EOF_U41FIX1_RECEIPTOCRHELPER_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/ReceiptOcrHelper.kt"

echo ""
echo "=== Готово. Дальше: ==="
echo "git add -A && git commit -m 'fix: remove non-existent ML Kit cyrillic dependency' && git push"
