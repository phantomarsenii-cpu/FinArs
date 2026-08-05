#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=== Обновление 26: раздел Faktury/Rachunki (счета для физлиц) ==="
echo "Добавляет: форму выставления счёта/рахунку с данными продавца и покупателя,"
echo "генерацию PDF, сохранение в Documents/FinArs/Invoices, кнопку на главном экране,"
echo "учёт лимита наличных расчётов с физлицами (20 000 zl/год)."
echo ""

# --- Проверка, что скрипт запущен из корня проекта ---
if [ ! -f "settings.gradle" ] || [ ! -d "app/src/main/java/com/example/fa_ksiegowy" ]; then
    echo "!!! Запусти скрипт из корня проекта FA_ksiegowy-main (там, где settings.gradle)"
    exit 1
fi

# --- Бэкап файлов, которые будут изменены (не новых) ---
BACKUP_DIR=".update26_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
for f in \
    "app/src/main/AndroidManifest.xml" \
    "app/src/main/java/com/example/fa_ksiegowy/AppDatabase.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/FileNaming.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/MineActivity.kt" \
    "app/src/main/res/layout/activity_mine.xml" \
    "app/src/main/res/values/strings.xml" \
    "app/src/main/res/values/themes.xml" \
    "app/src/main/res/values-pl/strings.xml" \
    "app/src/main/res/values-ru/strings.xml" \
    "app/src/main/res/xml/file_paths.xml"
do
    if [ -f "$f" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$f")"
        cp "$f" "$BACKUP_DIR/$f"
    fi
done
echo "--- Бэкап изменяемых файлов сохранён в $BACKUP_DIR ---"

# ============================================================
# 1) Новые файлы (создаются с нуля)
# ============================================================

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/CashLimitHelper.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/CashLimitHelper.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_CASHLIMITHELPER_KT'
package com.example.fa_ksiegowy

import android.content.Context
import java.util.Calendar

/**
 * Kontrola rocznego limitu 20 000 PLN sprzedaży gotówkowej na rzecz osób
 * fizycznych nieprowadzących działalności gospodarczej (art. 111 ust. 1
 * ustawy o VAT wraz z rozporządzeniem w sprawie zwolnień z kasy fiskalnej).
 * Po przekroczeniu limitu powstaje obowiązek posiadania kasy fiskalnej.
 * Płatności bezgotówkowe (przelew, BLIK) NIE wliczają się do tego limitu.
 */
object CashLimitHelper {

    const val LIMIT = 20000.0
    const val WARNING_RATIO = 0.8 // 16 000 PLN

    data class Status(val currentCashSum: Double) {
        val ratio: Double get() = (currentCashSum / LIMIT).coerceAtLeast(0.0)
        val percent: Int get() = (ratio * 100).toInt()
        val nearLimit: Boolean get() = ratio >= WARNING_RATIO
        val exceeded: Boolean get() = currentCashSum > LIMIT
    }

    private fun yearRange(year: Int): Pair<Long, Long> {
        val start = Calendar.getInstance().apply {
            set(year, Calendar.JANUARY, 1, 0, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val end = (start.clone() as Calendar).apply { add(Calendar.YEAR, 1) }
        return start.timeInMillis to (end.timeInMillis - 1)
    }

    /** Suma gotówki dla osób fizycznych w bieżącym roku kalendarzowym, bez [excludingInvoiceId] (edycja). */
    suspend fun computeCurrentYear(context: Context, excludingInvoiceId: Long? = null): Status {
        val db = AppDatabase.getInstance(context)
        val year = Calendar.getInstance().get(Calendar.YEAR)
        val (from, to) = yearRange(year)
        val invoices = db.invoiceDao().getBetween(from, to)
        val sum = invoices
            .filter { it.id != excludingInvoiceId }
            .filter { it.isPhysicalPerson && it.paymentMethod.countsTowardCashLimit }
            .sumOf { it.amount }
        return Status(sum)
    }
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_CASHLIMITHELPER_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/CashLimitHelper.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/Converters.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/Converters.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_CONVERTERS_KT'
package com.example.fa_ksiegowy

import androidx.room.TypeConverter

/** Room nie wspiera enumów natywnie (w wersji 2.5.0) — zapisujemy jako String. */
class Converters {
    @TypeConverter
    fun fromPaymentMethod(value: PaymentMethod): String = value.name

    @TypeConverter
    fun toPaymentMethod(value: String): PaymentMethod =
        PaymentMethod.values().firstOrNull { it.name == value } ?: PaymentMethod.CASH
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_CONVERTERS_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/Converters.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/Invoice.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/Invoice.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICE_KT'
package com.example.fa_ksiegowy

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Faktura imienna / Rachunek wystawiony klientowi — osobie fizycznej
 * (bez NIP) lub firmie (z NIP). Przechowuje dane nabywcy, kwotę, sposób
 * płatności (potrzebny do kontroli limitu 20 000 PLN gotówki) oraz ścieżkę
 * (URI z MediaStore) do zapisanego pliku PDF.
 */
@Entity(tableName = "invoices")
data class Invoice(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    /** Kolejny numer dokumentu (1, 2, 3…), używany też w nazwie pliku PDF. */
    val invoiceNumber: Int,
    /** Data wystawienia dokumentu (moment utworzenia w aplikacji). */
    val issueDateMillis: Long,
    /** Data faktycznej zapłaty. */
    val paymentDateMillis: Long,
    /** Data wykonania usługi / sprzedaży towaru. */
    val serviceDateMillis: Long,

    val isPhysicalPerson: Boolean,
    val buyerName: String,
    val buyerNip: String?,
    val buyerStreet: String,
    val buyerPostalCode: String,
    val buyerCity: String,

    val serviceName: String,
    val amount: Double,
    val paymentMethod: PaymentMethod,

    /** Content URI (MediaStore) lub ścieżka do zapisanego pliku PDF. */
    val pdfFilePath: String,
    val pdfFileName: String
)
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICE_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/Invoice.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/InvoiceDao.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/InvoiceDao.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEDAO_KT'
package com.example.fa_ksiegowy

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update

@Dao
interface InvoiceDao {
    @Insert
    suspend fun insert(invoice: Invoice): Long

    @Update
    suspend fun update(invoice: Invoice)

    @Delete
    suspend fun delete(invoice: Invoice)

    @Query("SELECT * FROM invoices WHERE id = :id LIMIT 1")
    suspend fun getById(id: Long): Invoice?

    @Query("SELECT * FROM invoices ORDER BY issueDateMillis DESC")
    suspend fun getAll(): List<Invoice>

    @Query("SELECT MAX(invoiceNumber) FROM invoices")
    suspend fun getMaxInvoiceNumber(): Int?

    /**
     * Suma sprzedaży gotówkowej (paymentMethod = CASH) dla osób fizycznych
     * w danym roku — podstawa kontrolki limitu 20 000 PLN (kasa fiskalna).
     * Filtrowanie po isPhysicalPerson i paymentMethod robimy w Kotlinie
     * (patrz CashLimitHelper), tu pobieramy tylko zakres dat, by uniknąć
     * przechowywania enuma jako String w zapytaniu SQL.
     */
    @Query("SELECT * FROM invoices WHERE issueDateMillis BETWEEN :from AND :to ORDER BY issueDateMillis ASC")
    suspend fun getBetween(from: Long, to: Long): List<Invoice>
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEDAO_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/InvoiceDao.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/InvoiceFileStorage.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/InvoiceFileStorage.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEFILESTORAGE_KT'
package com.example.fa_ksiegowy

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import androidx.core.content.FileProvider
import java.io.File
import java.io.OutputStream

/**
 * Zapisuje wygenerowane PDF-y faktur/rachunków w publicznym, wspólnym dla
 * wszystkich aplikacji katalogu Documents/FinArs/Invoices, tak by klient
 * mógł je łatwo znaleźć dowolnym menedżerem plików i wysłać dalej.
 *
 * Android 10+ (API 29+): zapis przez MediaStore (Scoped Storage) —
 * aplikacja NIE potrzebuje uprawnienia WRITE_EXTERNAL_STORAGE.
 * Android 8–9 (API 26–28): bezpośredni zapis pliku do publicznego katalogu
 * Documents (wymaga WRITE_EXTERNAL_STORAGE, zadeklarowanego w Manifest
 * z maxSdkVersion="28" — na nowszych wersjach jest ignorowane/niepotrzebne).
 */
object InvoiceFileStorage {

    private const val RELATIVE_FOLDER = "FinArs/Invoices"
    private const val MIME_PDF = "application/pdf"

    data class SavedPdf(val uri: Uri, val displayPath: String)

    /**
     * Zapisuje PDF pod wskazaną nazwą, wywołując [writer] z otwartym
     * OutputStream. Zwraca URI (do otwierania/udostępniania) i ścieżkę
     * do wyświetlenia użytkownikowi.
     */
    fun savePdf(context: Context, fileName: String, writer: (OutputStream) -> Unit): SavedPdf {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(context, fileName, writer)
        } else {
            saveViaLegacyFile(context, fileName, writer)
        }
    }

    private fun saveViaMediaStore(context: Context, fileName: String, writer: (OutputStream) -> Unit): SavedPdf {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, MIME_PDF)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOCUMENTS}/$RELATIVE_FOLDER")
            // Podczas zapisu plik jest "niedokończony" dla innych aplikacji — zdejmujemy
            // flagę dopiero po zapisaniu zawartości (patrz niżej).
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore insert failed for $fileName")

        try {
            resolver.openOutputStream(uri)?.use { out -> writer(out) }
                ?: throw IllegalStateException("Could not open output stream for $uri")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            // Sprzątamy niedokończony wpis, żeby nie zostawiać "ducha" w MediaStore.
            resolver.delete(uri, null, null)
            throw e
        }

        return SavedPdf(uri, "Documents/$RELATIVE_FOLDER/$fileName")
    }

    private fun saveViaLegacyFile(context: Context, fileName: String, writer: (OutputStream) -> Unit): SavedPdf {
        @Suppress("DEPRECATION")
        val documentsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)
        val targetDir = File(documentsDir, RELATIVE_FOLDER)
        if (!targetDir.exists()) targetDir.mkdirs()
        val file = File(targetDir, fileName)
        file.outputStream().use { out -> writer(out) }
        // file:// URI-ów nie wolno przekazywać do innych aplikacji od API 24 (FileUriExposedException) —
        // używamy FileProvider, tak jak przy udostępnianiu czeków/raportów w reszcie aplikacji.
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        return SavedPdf(uri, file.absolutePath)
    }

    /** Intent do otwarcia zapisanego PDF w systemowej przeglądarce PDF. */
    fun viewIntent(uri: Uri): Intent =
        Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, MIME_PDF)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }

    /** Intent do wysłania PDF przez inną aplikację (WhatsApp, Telegram, e-mail…). */
    fun shareIntent(uri: Uri): Intent =
        Intent(Intent.ACTION_SEND).apply {
            type = MIME_PDF
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

    /**
     * Best-effort otwarcie katalogu Documents/FinArs/Invoices w systemowym
     * menedżerze plików. Nie wszystkie menedżery plików obsługują otwieranie
     * konkretnego podkatalogu przez Intent — jeśli się nie uda, wywołujący
     * powinien złapać ActivityNotFoundException i pokazać ścieżkę tekstem.
     */
    fun openFolderIntent(): Intent {
        val docId = "primary:${Environment.DIRECTORY_DOCUMENTS}/$RELATIVE_FOLDER"
        val folderUri = DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", docId)
        return Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(folderUri, DocumentsContract.Document.MIME_TYPE_DIR)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    val displayFolderPath: String get() = "Documents/$RELATIVE_FOLDER"
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEFILESTORAGE_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/InvoiceFileStorage.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/InvoicePdfGenerator.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/InvoicePdfGenerator.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEPDFGENERATOR_KT'
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
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEPDFGENERATOR_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/InvoicePdfGenerator.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/InvoiceSellerData.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/InvoiceSellerData.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICESELLERDATA_KT'
package com.example.fa_ksiegowy

import android.content.Context

/**
 * Dane sprzedawcy (mojej firmy) wyświetlane w nagłówku faktury/rachunku.
 * Przy pierwszym użyciu podpowiadane z danych podatnika (PitPersonalData),
 * ale przechowywane osobno i edytowalne na ekranie wystawiania dokumentu —
 * nie każdy sprzedawca ma NIP (np. działalność nierejestrowana).
 */
data class InvoiceSellerData(
    val name: String = "",
    val nip: String = "",
    val street: String = "",
    val postalCode: String = "",
    val city: String = ""
)

object InvoiceSellerDataStore {
    private const val PREFS = "invoice_seller_data"

    fun load(context: Context): InvoiceSellerData {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val hasSaved = p.contains("name")
        if (!hasSaved) {
            // Pierwsze użycie — podpowiadamy z danych podatnika z sekcji PIT.
            val pit = PitDataStore.load(context)
            if (pit.firstName.isNotBlank() || pit.lastName.isNotBlank()) {
                return InvoiceSellerData(
                    name = "${pit.firstName} ${pit.lastName}".trim(),
                    nip = "",
                    street = listOf(pit.street, pit.houseNumber).filter { it.isNotBlank() }.joinToString(" "),
                    postalCode = pit.postalCode,
                    city = pit.city
                )
            }
        }
        return InvoiceSellerData(
            name = p.getString("name", "") ?: "",
            nip = p.getString("nip", "") ?: "",
            street = p.getString("street", "") ?: "",
            postalCode = p.getString("postalCode", "") ?: "",
            city = p.getString("city", "") ?: ""
        )
    }

    fun save(context: Context, data: InvoiceSellerData) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("name", data.name)
            .putString("nip", data.nip)
            .putString("street", data.street)
            .putString("postalCode", data.postalCode)
            .putString("city", data.city)
            .apply()
    }
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICESELLERDATA_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/InvoiceSellerData.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/PaymentMethod.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/PaymentMethod.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_PAYMENTMETHOD_KT'
package com.example.fa_ksiegowy

/**
 * Sposób płatności za fakturę/rachunek.
 *
 * Tylko CASH (Gotówka) wlicza się do rocznego limitu 20 000 PLN sprzedaży
 * gotówkowej dla osób fizycznych (art. 111 ust. 1 ustawy o VAT — obowiązek
 * kasy fiskalnej po przekroczeniu limitu). TRANSFER i BLIK jako płatności
 * bezgotówkowe nie są wliczane do tego limitu.
 */
enum class PaymentMethod {
    CASH,
    TRANSFER,
    BLIK;

    val countsTowardCashLimit: Boolean get() = this == CASH

    val labelResId: Int
        get() = when (this) {
            CASH -> R.string.payment_method_cash
            TRANSFER -> R.string.payment_method_transfer
            BLIK -> R.string.payment_method_blik
        }

    /** Fraza dopisywana na dokumencie przy płatności bezgotówkowej, np. "Zapłacono przelewem". */
    val paidLabelResId: Int
        get() = when (this) {
            CASH -> R.string.payment_paid_cash
            TRANSFER -> R.string.payment_paid_transfer
            BLIK -> R.string.payment_paid_blik
        }
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_PAYMENTMETHOD_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/PaymentMethod.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_ADDINVOICEACTIVITY_KT'
package com.example.fa_ksiegowy

import android.app.DatePickerDialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.ProgressBar
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Ekran wystawiania faktury imiennej / rachunku dla klienta (osoby fizycznej
 * bez NIP lub firmy z NIP): formularz danych, kontrola rocznego limitu
 * 20 000 PLN gotówki, generowanie PDF (zapis do Documents/FinArs/Invoices
 * przez MediaStore) oraz otwarcie/udostępnienie wygenerowanego pliku.
 */
class AddInvoiceActivity : BaseActivity() {

    private var isPhysicalPerson: Boolean = true
    private var paymentMethod: PaymentMethod = PaymentMethod.CASH
    private var serviceDateMillis: Long = System.currentTimeMillis()
    private var paymentDateMillis: Long = System.currentTimeMillis()
    private var lastSavedUri: Uri? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_add_invoice)

        setupPaymentMethodToggle()
        findViewById<Button>(R.id.btn_service_date).setOnClickListener { showDatePicker(isServiceDate = true) }
        findViewById<Button>(R.id.btn_payment_date).setOnClickListener { showDatePicker(isServiceDate = false) }
        updateDateButtons()

        findViewById<Switch>(R.id.sw_physical_person).setOnCheckedChangeListener { _, checked ->
            isPhysicalPerson = checked
            findViewById<EditText>(R.id.et_buyer_nip).visibility = if (checked) View.GONE else View.VISIBLE
        }

        findViewById<Button>(R.id.btn_generate).setOnClickListener { generateInvoice() }
        findViewById<Button>(R.id.btn_open_pdf).setOnClickListener { openLastPdf() }
        findViewById<Button>(R.id.btn_share).setOnClickListener { shareLastPdf() }
        findViewById<Button>(R.id.btn_open_folder).setOnClickListener { openInvoicesFolder() }

        loadSellerData()
        refreshCashLimit()
    }

    private fun loadSellerData() {
        CoroutineScope(Dispatchers.IO).launch {
            val seller = InvoiceSellerDataStore.load(applicationContext)
            withContext(Dispatchers.Main) {
                findViewById<EditText>(R.id.et_seller_name).setText(seller.name)
                findViewById<EditText>(R.id.et_seller_nip).setText(seller.nip)
                findViewById<EditText>(R.id.et_seller_street).setText(seller.street)
                findViewById<EditText>(R.id.et_seller_postal).setText(seller.postalCode)
                findViewById<EditText>(R.id.et_seller_city).setText(seller.city)
            }
        }
    }

    private fun refreshCashLimit() {
        CoroutineScope(Dispatchers.IO).launch {
            val status = CashLimitHelper.computeCurrentYear(applicationContext)
            withContext(Dispatchers.Main) {
                findViewById<TextView>(R.id.tv_cash_limit_label).text = getString(
                    R.string.cash_limit_label,
                    formatMoney(status.currentCashSum),
                    formatMoney(CashLimitHelper.LIMIT)
                )
                findViewById<ProgressBar>(R.id.pb_cash_limit).progress = status.percent.coerceAtMost(100)
                val warning = findViewById<TextView>(R.id.tv_cash_limit_warning)
                when {
                    status.exceeded -> {
                        warning.text = getString(R.string.cash_limit_exceeded_warning)
                        warning.visibility = View.VISIBLE
                    }
                    status.nearLimit -> {
                        warning.text = getString(R.string.cash_limit_warning)
                        warning.visibility = View.VISIBLE
                    }
                    else -> warning.visibility = View.GONE
                }
            }
        }
    }

    private fun setupPaymentMethodToggle() {
        applyPaymentMethodUi()
        findViewById<Button>(R.id.btn_payment_cash).setOnClickListener {
            paymentMethod = PaymentMethod.CASH; applyPaymentMethodUi(); refreshCashLimit()
        }
        findViewById<Button>(R.id.btn_payment_transfer).setOnClickListener {
            paymentMethod = PaymentMethod.TRANSFER; applyPaymentMethodUi(); refreshCashLimit()
        }
        findViewById<Button>(R.id.btn_payment_blik).setOnClickListener {
            paymentMethod = PaymentMethod.BLIK; applyPaymentMethodUi(); refreshCashLimit()
        }
    }

    private fun applyPaymentMethodUi() {
        val cash = findViewById<Button>(R.id.btn_payment_cash)
        val transfer = findViewById<Button>(R.id.btn_payment_transfer)
        val blik = findViewById<Button>(R.id.btn_payment_blik)
        cash.setBackgroundResource(if (paymentMethod == PaymentMethod.CASH) R.drawable.btn_pill_primary else R.drawable.btn_pill_outline)
        transfer.setBackgroundResource(if (paymentMethod == PaymentMethod.TRANSFER) R.drawable.btn_pill_primary else R.drawable.btn_pill_outline)
        blik.setBackgroundResource(if (paymentMethod == PaymentMethod.BLIK) R.drawable.btn_pill_primary else R.drawable.btn_pill_outline)
    }

    private fun showDatePicker(isServiceDate: Boolean) {
        val current = if (isServiceDate) serviceDateMillis else paymentDateMillis
        val cal = Calendar.getInstance().apply { timeInMillis = current }
        DatePickerDialog(
            this,
            { _, year, month, dayOfMonth ->
                val picked = Calendar.getInstance().apply {
                    set(year, month, dayOfMonth, 12, 0, 0)
                    set(Calendar.MILLISECOND, 0)
                }
                if (isServiceDate) serviceDateMillis = picked.timeInMillis else paymentDateMillis = picked.timeInMillis
                updateDateButtons()
            },
            cal.get(Calendar.YEAR), cal.get(Calendar.MONTH), cal.get(Calendar.DAY_OF_MONTH)
        ).show()
    }

    private fun updateDateButtons() {
        val sdf = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())
        findViewById<Button>(R.id.btn_service_date).text =
            getString(R.string.service_date_label) + ": " + sdf.format(serviceDateMillis)
        findViewById<Button>(R.id.btn_payment_date).text =
            getString(R.string.payment_date_label) + ": " + sdf.format(paymentDateMillis)
    }

    private fun generateInvoice() {
        val sellerName = findViewById<EditText>(R.id.et_seller_name).text.toString().trim()
        val sellerNip = findViewById<EditText>(R.id.et_seller_nip).text.toString().trim()
        val sellerStreet = findViewById<EditText>(R.id.et_seller_street).text.toString().trim()
        val sellerPostal = findViewById<EditText>(R.id.et_seller_postal).text.toString().trim()
        val sellerCity = findViewById<EditText>(R.id.et_seller_city).text.toString().trim()

        val buyerName = findViewById<EditText>(R.id.et_buyer_name).text.toString().trim()
        val buyerNip = findViewById<EditText>(R.id.et_buyer_nip).text.toString().trim()
        val buyerStreet = findViewById<EditText>(R.id.et_buyer_street).text.toString().trim()
        val buyerPostal = findViewById<EditText>(R.id.et_buyer_postal).text.toString().trim()
        val buyerCity = findViewById<EditText>(R.id.et_buyer_city).text.toString().trim()

        val serviceName = findViewById<EditText>(R.id.et_service_name).text.toString().trim()
        val amount = findViewById<EditText>(R.id.et_amount).text.toString().toDoubleOrNull()

        if (buyerName.isBlank() || serviceName.isBlank() || amount == null || amount <= 0.0) {
            Toast.makeText(this, getString(R.string.invoice_fill_required_fields), Toast.LENGTH_SHORT).show()
            return
        }

        findViewById<Button>(R.id.btn_generate).isEnabled = false
        val seller = InvoiceSellerData(sellerName, sellerNip, sellerStreet, sellerPostal, sellerCity)
        val issueDateMillis = System.currentTimeMillis()

        CoroutineScope(Dispatchers.IO).launch {
            try {
                InvoiceSellerDataStore.save(applicationContext, seller)
                val dao = AppDatabase.getInstance(applicationContext).invoiceDao()
                val invoiceNumber = (dao.getMaxInvoiceNumber() ?: 0) + 1
                val fileName = FileNaming.invoiceFileName(invoiceNumber, issueDateMillis)

                val saved = InvoiceFileStorage.savePdf(applicationContext, fileName) { out ->
                    InvoicePdfGenerator.generate(
                        context = applicationContext,
                        seller = seller,
                        invoiceNumber = invoiceNumber,
                        issueDateMillis = issueDateMillis,
                        paymentDateMillis = paymentDateMillis,
                        serviceDateMillis = serviceDateMillis,
                        isPhysicalPerson = isPhysicalPerson,
                        buyerName = buyerName,
                        buyerNip = if (isPhysicalPerson) null else buyerNip,
                        buyerStreet = buyerStreet,
                        buyerPostalCode = buyerPostal,
                        buyerCity = buyerCity,
                        serviceName = serviceName,
                        amount = amount,
                        paymentMethod = paymentMethod,
                        out = out
                    )
                }

                dao.insert(
                    Invoice(
                        invoiceNumber = invoiceNumber,
                        issueDateMillis = issueDateMillis,
                        paymentDateMillis = paymentDateMillis,
                        serviceDateMillis = serviceDateMillis,
                        isPhysicalPerson = isPhysicalPerson,
                        buyerName = buyerName,
                        buyerNip = if (isPhysicalPerson) null else buyerNip,
                        buyerStreet = buyerStreet,
                        buyerPostalCode = buyerPostal,
                        buyerCity = buyerCity,
                        serviceName = serviceName,
                        amount = amount,
                        paymentMethod = paymentMethod,
                        pdfFilePath = saved.uri.toString(),
                        pdfFileName = fileName
                    )
                )

                withContext(Dispatchers.Main) {
                    lastSavedUri = saved.uri
                    findViewById<Button>(R.id.btn_generate).isEnabled = true
                    findViewById<View>(R.id.row_after_generate).visibility = View.VISIBLE
                    Toast.makeText(
                        this@AddInvoiceActivity,
                        getString(R.string.invoice_generated_toast, fileName),
                        Toast.LENGTH_LONG
                    ).show()
                    refreshCashLimit()
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    findViewById<Button>(R.id.btn_generate).isEnabled = true
                    Toast.makeText(
                        this@AddInvoiceActivity,
                        getString(R.string.invoice_error_toast, e.message ?: e.javaClass.simpleName),
                        Toast.LENGTH_LONG
                    ).show()
                }
            }
        }
    }

    private fun openLastPdf() {
        val uri = lastSavedUri ?: return
        try {
            startActivity(InvoiceFileStorage.viewIntent(uri))
        } catch (e: ActivityNotFoundException) {
            Toast.makeText(this, getString(R.string.open_folder_error, InvoiceFileStorage.displayFolderPath), Toast.LENGTH_LONG).show()
        }
    }

    private fun shareLastPdf() {
        val uri = lastSavedUri ?: return
        startActivity(Intent.createChooser(InvoiceFileStorage.shareIntent(uri), getString(R.string.share_invoice_button)))
    }

    private fun openInvoicesFolder() {
        try {
            startActivity(InvoiceFileStorage.openFolderIntent())
        } catch (e: ActivityNotFoundException) {
            Toast.makeText(this, getString(R.string.open_folder_error, InvoiceFileStorage.displayFolderPath), Toast.LENGTH_LONG).show()
        }
    }

    private fun formatMoney(v: Double): String = String.format(Locale.getDefault(), "%.2f", v)
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_ADDINVOICEACTIVITY_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt"

mkdir -p "$(dirname "app/src/main/res/layout/activity_add_invoice.xml")"
cat > app/src/main/res/layout/activity_add_invoice.xml << 'EOF_APP_SRC_MAIN_RES_LAYOUT_ACTIVITY_ADD_INVOICE_XML'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:fillViewport="true">

<LinearLayout
    android:orientation="vertical"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:padding="24dp">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="12dp"
        android:layout_marginBottom="20dp"
        android:text="@string/invoice_form_title"
        android:textColor="@color/accent_cyan"
        android:textSize="24sp"
        android:textStyle="bold"/>

    <!-- Sprzedawca -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:background="@drawable/card_bg"
        android:padding="16dp"
        android:layout_marginBottom="16dp">

        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="@string/invoice_seller_section"
            android:textColor="@color/text_secondary"
            android:textSize="11sp"
            android:textStyle="bold"
            android:letterSpacing="0.08"
            android:layout_marginBottom="12dp"/>

        <EditText android:id="@+id/et_seller_name" style="@style/InvoiceInput" android:hint="@string/seller_name" android:inputType="textPersonName"/>
        <EditText android:id="@+id/et_seller_nip" style="@style/InvoiceInput" android:hint="@string/seller_nip" android:inputType="number"/>
        <EditText android:id="@+id/et_seller_street" style="@style/InvoiceInput" android:hint="@string/seller_address_street" android:inputType="textPostalAddress"/>

        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:weightSum="2" android:baselineAligned="false">
            <EditText android:id="@+id/et_seller_postal" style="@style/InvoiceInputHalfStart" android:hint="@string/seller_address_postal" android:inputType="text"/>
            <EditText android:id="@+id/et_seller_city" style="@style/InvoiceInputHalfEnd" android:hint="@string/seller_address_city" android:inputType="text"/>
        </LinearLayout>

    </LinearLayout>

    <!-- Nabywca -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:background="@drawable/card_bg"
        android:padding="16dp"
        android:layout_marginBottom="16dp">

        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="@string/invoice_buyer_section"
            android:textColor="@color/text_secondary"
            android:textSize="11sp"
            android:textStyle="bold"
            android:letterSpacing="0.08"
            android:layout_marginBottom="12dp"/>

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical"
            android:layout_marginBottom="14dp">
            <Switch
                android:id="@+id/sw_physical_person"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:checked="true"/>
            <TextView
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:layout_weight="1"
                android:layout_marginStart="10dp"
                android:text="@string/buyer_physical_person_switch"
                android:textColor="@color/text_primary"
                android:textSize="14sp"/>
        </LinearLayout>

        <EditText android:id="@+id/et_buyer_name" style="@style/InvoiceInput" android:hint="@string/buyer_name" android:inputType="textPersonName"/>
        <EditText android:id="@+id/et_buyer_nip" style="@style/InvoiceInput" android:hint="@string/buyer_nip" android:inputType="number" android:visibility="gone"/>
        <EditText android:id="@+id/et_buyer_street" style="@style/InvoiceInput" android:hint="@string/buyer_address_street" android:inputType="textPostalAddress"/>

        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:weightSum="2" android:baselineAligned="false">
            <EditText android:id="@+id/et_buyer_postal" style="@style/InvoiceInputHalfStart" android:hint="@string/buyer_address_postal" android:inputType="text"/>
            <EditText android:id="@+id/et_buyer_city" style="@style/InvoiceInputHalfEnd" android:hint="@string/buyer_address_city" android:inputType="text"/>
        </LinearLayout>

    </LinearLayout>

    <!-- Usługa / towar -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:background="@drawable/card_bg"
        android:padding="16dp"
        android:layout_marginBottom="16dp">

        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="@string/invoice_service_section"
            android:textColor="@color/text_secondary"
            android:textSize="11sp"
            android:textStyle="bold"
            android:letterSpacing="0.08"
            android:layout_marginBottom="12dp"/>

        <EditText android:id="@+id/et_service_name" style="@style/InvoiceInput" android:hint="@string/service_name" android:inputType="text"/>
        <EditText android:id="@+id/et_amount" style="@style/InvoiceInput" android:hint="@string/service_amount" android:inputType="numberDecimal"/>

        <Button
            android:id="@+id/btn_service_date"
            android:layout_width="match_parent"
            android:layout_height="56dp"
            android:layout_marginBottom="14dp"
            android:background="@drawable/input_field_bg"
            android:text="@string/service_date_label"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="15sp"
            android:gravity="start|center_vertical"
            android:paddingStart="18dp"
            android:paddingEnd="18dp"/>

        <Button
            android:id="@+id/btn_payment_date"
            android:layout_width="match_parent"
            android:layout_height="56dp"
            android:layout_marginBottom="14dp"
            android:background="@drawable/input_field_bg"
            android:text="@string/payment_date_label"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="15sp"
            android:gravity="start|center_vertical"
            android:paddingStart="18dp"
            android:paddingEnd="18dp"/>

        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="@string/payment_method_label"
            android:textColor="@color/text_secondary"
            android:textSize="12sp"
            android:layout_marginBottom="8dp"/>

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:weightSum="3" android:baselineAligned="false">

            <Button
                android:id="@+id/btn_payment_cash"
                android:layout_width="0dp" android:layout_height="46dp" android:layout_weight="1"
                android:layout_marginEnd="6dp"
                android:background="@drawable/btn_pill_primary"
                android:text="@string/payment_method_cash"
                android:textAllCaps="false" android:textColor="@color/text_primary" android:textSize="13sp"/>

            <Button
                android:id="@+id/btn_payment_transfer"
                android:layout_width="0dp" android:layout_height="46dp" android:layout_weight="1"
                android:layout_marginStart="3dp" android:layout_marginEnd="3dp"
                android:background="@drawable/btn_pill_outline"
                android:text="@string/payment_method_transfer"
                android:textAllCaps="false" android:textColor="@color/text_primary" android:textSize="13sp"/>

            <Button
                android:id="@+id/btn_payment_blik"
                android:layout_width="0dp" android:layout_height="46dp" android:layout_weight="1"
                android:layout_marginStart="6dp"
                android:background="@drawable/btn_pill_outline"
                android:text="@string/payment_method_blik"
                android:textAllCaps="false" android:textColor="@color/text_primary" android:textSize="13sp"/>

        </LinearLayout>

    </LinearLayout>

    <!-- Limit gotówki -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:background="@drawable/card_bg"
        android:padding="16dp"
        android:layout_marginBottom="20dp">

        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="@string/cash_limit_title"
            android:textColor="@color/text_secondary"
            android:textSize="11sp"
            android:textStyle="bold"
            android:letterSpacing="0.08"
            android:layout_marginBottom="10dp"/>

        <TextView android:id="@+id/tv_cash_limit_label" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:textColor="@color/text_primary" android:textSize="13sp" android:layout_marginBottom="4dp"/>
        <ProgressBar android:id="@+id/pb_cash_limit" style="?android:attr/progressBarStyleHorizontal"
            android:layout_width="match_parent" android:layout_height="8dp" android:max="100"/>

        <TextView
            android:id="@+id/tv_cash_limit_warning"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="10dp"
            android:textColor="#FF6B6B"
            android:textSize="12sp"
            android:visibility="gone"/>

    </LinearLayout>

    <Button
        android:id="@+id/btn_generate"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:layout_marginBottom="14dp"
        android:background="@drawable/btn_pill_primary"
        android:text="@string/generate_invoice_button"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="17sp"
        android:textStyle="bold"/>

    <LinearLayout
        android:id="@+id/row_after_generate"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:weightSum="2"
        android:baselineAligned="false"
        android:layout_marginBottom="14dp"
        android:visibility="gone">

        <Button
            android:id="@+id/btn_open_pdf"
            android:layout_width="0dp" android:layout_height="52dp" android:layout_weight="1"
            android:layout_marginEnd="8dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/open_pdf_button"
            android:textAllCaps="false" android:textColor="@color/text_primary" android:textSize="14sp"/>

        <Button
            android:id="@+id/btn_share"
            android:layout_width="0dp" android:layout_height="52dp" android:layout_weight="1"
            android:layout_marginStart="8dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/share_invoice_button"
            android:textAllCaps="false" android:textColor="@color/text_primary" android:textSize="14sp"/>

    </LinearLayout>

    <Button
        android:id="@+id/btn_open_folder"
        android:layout_width="match_parent"
        android:layout_height="52dp"
        android:background="@drawable/btn_pill_outline"
        android:text="@string/open_invoices_folder_button"
        android:textAllCaps="false"
        android:textColor="@color/accent_cyan"
        android:textSize="14sp"/>

</LinearLayout>
</ScrollView>
EOF_APP_SRC_MAIN_RES_LAYOUT_ACTIVITY_ADD_INVOICE_XML
echo "OK: app/src/main/res/layout/activity_add_invoice.xml"


# ============================================================
# 2) Точечные правки существующих файлов (безопасно перезапускать)
# ============================================================

echo ""
echo "--- Правки существующих файлов ---"

# --- 2.1 AndroidManifest.xml: регистрируем AddInvoiceActivity ---
python3 - "app/src/main/AndroidManifest.xml" << 'EOF_PY_MANIFEST'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "AddInvoiceActivity" in content:
    print("OK (уже применено): %s" % path)
else:
    anchor = '        <activity android:name=".AddEntryActivity" android:exported="false" />\n'
    if anchor not in content:
        print("!!! Не найден якорь AddEntryActivity в %s" % path)
        sys.exit(1)
    new_line = '        <activity android:name=".AddInvoiceActivity" android:exported="false" />\n'
    content = content.replace(anchor, anchor + new_line, 1)
    with io.open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("OK: %s -> добавлена AddInvoiceActivity" % path)
EOF_PY_MANIFEST

# --- 2.2 AppDatabase.kt: добавляем Invoice в базу данных ---
python3 - "app/src/main/java/com/example/fa_ksiegowy/AppDatabase.kt" << 'EOF_PY_DB'
import sys, io, re
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "InvoiceDao" in content:
    print("OK (уже применено): %s" % path)
    sys.exit(0)

if "import androidx.room.TypeConverters" not in content:
    content = content.replace(
        "import androidx.room.RoomDatabase",
        "import androidx.room.RoomDatabase\nimport androidx.room.TypeConverters",
        1
    )

old_decl = "@Database(entities = [Entry::class], version = 1, exportSchema = false)"
new_decl = "@Database(entities = [Entry::class, Invoice::class], version = 2, exportSchema = false)\n@TypeConverters(Converters::class)"
if old_decl not in content:
    print("!!! Не найдена аннотация @Database в %s" % path)
    sys.exit(1)
content = content.replace(old_decl, new_decl, 1)

m = re.search(r"(abstract fun entryDao\(\): EntryDao\s*\n)", content)
if not m:
    print("!!! Не найден abstract fun entryDao() в %s" % path)
    sys.exit(1)
content = content[:m.end()] + "    abstract fun invoiceDao(): InvoiceDao\n" + content[m.end():]

with io.open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("OK: %s -> добавлены Invoice::class, invoiceDao()" % path)
EOF_PY_DB

# --- 2.3 FileNaming.kt: добавляем invoiceFileName() ---
python3 - "app/src/main/java/com/example/fa_ksiegowy/FileNaming.kt" << 'EOF_PY_FN'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "invoiceFileName" in content:
    print("OK (уже применено): %s" % path)
    sys.exit(0)

anchor = '    fun timestamp(): String = stampFmt.format(Date())\n}'
if anchor not in content:
    print("!!! Не найден якорь timestamp() в %s" % path)
    sys.exit(1)

addition = '''    fun timestamp(): String = stampFmt.format(Date())

    private val invoiceDateFmt = SimpleDateFormat("yyyy_MM_dd", Locale.US)

    /**
     * \u0418\u043c\u044f \u0444\u0430\u0439\u043b\u0430 \u0441\u0447\u0451\u0442\u0430/\u0444\u0430\u043a\u0442\u0443\u0440\u044b: Faktura_[\u041d\u043e\u043c\u0435\u0440\u0414\u043e\u043a\u0443\u043c\u0435\u043d\u0442\u0430]_[\u0414\u0430\u0442\u0430].pdf
     * (\u043d\u0430\u043f\u0440\u0438\u043c\u0435\u0440, Faktura_1_2026_08_03.pdf). \u0414\u0430\u0442\u0430 \u2014 \u0434\u0430\u0442\u0430 \u0432\u044b\u0441\u0442\u0430\u0432\u043b\u0435\u043d\u0438\u044f \u0434\u043e\u043a\u0443\u043c\u0435\u043d\u0442\u0430.
     */
    fun invoiceFileName(invoiceNumber: Int, issueDateMillis: Long): String {
        val date = invoiceDateFmt.format(Date(issueDateMillis))
        return "Faktura_${invoiceNumber}_${date}.pdf"
    }
}'''

content = content.replace(anchor, addition, 1)
with io.open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("OK: %s -> добавлен invoiceFileName()" % path)
EOF_PY_FN

# --- 2.4 MineActivity.kt: кнопка перехода к счетам ---
python3 - "app/src/main/java/com/example/fa_ksiegowy/MineActivity.kt" << 'EOF_PY_MINE'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "btn_invoices" in content:
    print("OK (уже применено): %s" % path)
    sys.exit(0)

anchor = '''        findViewById<Button>(R.id.btn_history).setOnClickListener {
            startActivity(Intent(this, HistoryActivity::class.java))
        }
'''
if anchor not in content:
    print("!!! Не найден якорь btn_history в %s" % path)
    sys.exit(1)

addition = anchor + '''        findViewById<Button>(R.id.btn_invoices).setOnClickListener {
            startActivity(Intent(this, AddInvoiceActivity::class.java))
        }
'''
content = content.replace(anchor, addition, 1)
with io.open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("OK: %s -> добавлен обработчик btn_invoices" % path)
EOF_PY_MINE

# --- 2.5 activity_mine.xml: добавляем кнопку "Faktury" ---
python3 - "app/src/main/res/layout/activity_mine.xml" << 'EOF_PY_LAYOUT'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "btn_invoices" in content:
    print("OK (уже применено): %s" % path)
    sys.exit(0)

old_block = '''    <Button
        android:id="@+id/btn_history"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:layout_marginBottom="20dp"
        android:background="@drawable/btn_pill_outline"
        android:text="@string/transaction_history"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="16sp"/>
'''
if old_block not in content:
    print("!!! Не найден блок btn_history в %s" % path)
    sys.exit(1)

new_block = '''    <Button
        android:id="@+id/btn_history"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:layout_marginBottom="14dp"
        android:background="@drawable/btn_pill_outline"
        android:text="@string/transaction_history"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="16sp"/>

    <Button
        android:id="@+id/btn_invoices"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:layout_marginBottom="20dp"
        android:background="@drawable/btn_pill_outline"
        android:text="@string/nav_invoices"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="16sp"/>
'''
content = content.replace(old_block, new_block, 1)
with io.open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("OK: %s -> добавлена кнопка btn_invoices" % path)
EOF_PY_LAYOUT

# --- 2.6 themes.xml: стили полей ввода для формы счёта ---
python3 - "app/src/main/res/values/themes.xml" << 'EOF_PY_THEMES'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "InvoiceInput" in content:
    print("OK (уже применено): %s" % path)
    sys.exit(0)

if "</resources>" not in content:
    print("!!! Не найден </resources> в %s" % path)
    sys.exit(1)

addition = '''
    <style name="InvoiceInput">
        <item name="android:layout_width">match_parent</item>
        <item name="android:layout_height">56dp</item>
        <item name="android:layout_marginBottom">14dp</item>
        <item name="android:background">@drawable/input_field_bg</item>
        <item name="android:paddingStart">18dp</item>
        <item name="android:paddingEnd">18dp</item>
        <item name="android:textColor">@color/text_primary</item>
        <item name="android:textColorHint">@color/text_hint</item>
    </style>

    <style name="InvoiceInputHalfStart" parent="InvoiceInput">
        <item name="android:layout_width">0dp</item>
        <item name="android:layout_weight">1</item>
        <item name="android:layout_marginEnd">7dp</item>
    </style>

    <style name="InvoiceInputHalfEnd" parent="InvoiceInput">
        <item name="android:layout_width">0dp</item>
        <item name="android:layout_weight">1</item>
        <item name="android:layout_marginStart">7dp</item>
    </style>
</resources>'''

content = content.replace("</resources>", addition, 1)
with io.open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("OK: %s -> добавлены стили InvoiceInput*" % path)
EOF_PY_THEMES

# --- 2.7 file_paths.xml: путь для сохранения счетов (Android 8-9) ---
python3 - "app/src/main/res/xml/file_paths.xml" << 'EOF_PY_PATHS'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

if 'name="invoices"' in content:
    print("OK (уже применено): %s" % path)
    sys.exit(0)

if "</paths>" not in content:
    print("!!! Не найден </paths> в %s" % path)
    sys.exit(1)

addition = '''    <!-- Android 8\u20139 (API 26\u201328): rachunki/faktury zapisywane bezpo\u015brednio w publicznym
         Documents/FinArs/Invoices (na 29+ ten sam katalog obs\u0142uguje MediaStore). -->
    <external-path name="invoices" path="Documents/FinArs/Invoices/" />
</paths>'''

content = content.replace("</paths>", addition, 1)
with io.open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("OK: %s -> добавлен external-path invoices" % path)
EOF_PY_PATHS

echo "--- Правки применены ---"

# --- 2.8 strings.xml (EN/PL/RU): добавляем строки для формы счёта ---
echo "-- English: app/src/main/res/values/strings.xml --"
python3 - "app/src/main/res/values/strings.xml" << 'EOF_PY_STRINGS_EN'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "nav_invoices" in content:
    print("OK (уже применено): %s" % path)
    sys.exit(0)

if "</resources>" not in content:
    print("!!! Не найден </resources> в %s" % path)
    sys.exit(1)

addition = '''

    <!-- Invoices / Rachunki -->
    <string name="nav_invoices">Invoices</string>
    <string name="invoice_form_title">New invoice / receipt</string>
    <string name="invoice_seller_section">Seller (your details)</string>
    <string name="seller_name">Name / company name</string>
    <string name="seller_nip">NIP (leave empty if none)</string>
    <string name="seller_address_street">Street and number</string>
    <string name="seller_address_postal">Postal code</string>
    <string name="seller_address_city">City</string>
    <string name="invoice_buyer_section">Buyer</string>
    <string name="buyer_physical_person_switch">Private individual (no NIP)</string>
    <string name="buyer_name">First and last name</string>
    <string name="buyer_nip">Buyer NIP</string>
    <string name="buyer_address_street">Street and number</string>
    <string name="buyer_address_postal">Postal code</string>
    <string name="buyer_address_city">City</string>
    <string name="invoice_service_section">Item / service</string>
    <string name="service_name">Name of the service or item</string>
    <string name="service_amount">Gross amount (PLN)</string>
    <string name="payment_date_label">Payment date</string>
    <string name="service_date_label">Service / sale date</string>
    <string name="payment_method_label">Payment method</string>
    <string name="payment_method_cash">Cash</string>
    <string name="payment_method_transfer">Transfer</string>
    <string name="payment_method_blik">BLIK</string>
    <string name="payment_paid_cash">Paid in cash</string>
    <string name="payment_paid_transfer">Paid by bank transfer</string>
    <string name="payment_paid_blik">Paid by BLIK</string>
    <string name="cash_limit_title">Cash sales to individuals this year</string>
    <string name="cash_limit_label">%1$s / %2$s PLN</string>
    <string name="cash_limit_warning">You are approaching the annual cash-sales limit for private individuals without a fiscal cash register.</string>
    <string name="cash_limit_exceeded_warning">You have exceeded the 20,000 PLN annual cash-sales limit for private individuals — a fiscal cash register (kasa fiskalna) may now be required.</string>
    <string name="generate_invoice_button">Generate PDF</string>
    <string name="invoice_generated_toast">Invoice saved: %1$s</string>
    <string name="invoice_error_toast">Could not generate the invoice: %1$s</string>
    <string name="open_pdf_button">Open PDF</string>
    <string name="share_invoice_button">Share</string>
    <string name="open_invoices_folder_button">Open invoices folder</string>
    <string name="open_folder_error">Could not open the folder. Files are saved in %1$s</string>
    <string name="invoice_fill_required_fields">Please fill in the buyer, item and amount</string>
</resources>'''

content = content.replace("</resources>", addition, 1)
with io.open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("OK: %s -> добавлены строки счёта" % path)
EOF_PY_STRINGS_EN

echo "-- Polski: app/src/main/res/values-pl/strings.xml --"
python3 - "app/src/main/res/values-pl/strings.xml" << 'EOF_PY_STRINGS_PL'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "nav_invoices" in content:
    print("OK (уже применено): %s" % path)
    sys.exit(0)

if "</resources>" not in content:
    print("!!! Не найден </resources> в %s" % path)
    sys.exit(1)

addition = '''

    <!-- Faktury / Rachunki -->
    <string name="nav_invoices">Faktury</string>
    <string name="invoice_form_title">Nowa faktura / rachunek</string>
    <string name="invoice_seller_section">Sprzedawca (Twoje dane)</string>
    <string name="seller_name">Imię i nazwisko / nazwa firmy</string>
    <string name="seller_nip">NIP (zostaw puste, jeśli brak)</string>
    <string name="seller_address_street">Ulica i numer</string>
    <string name="seller_address_postal">Kod pocztowy</string>
    <string name="seller_address_city">Miasto</string>
    <string name="invoice_buyer_section">Nabywca</string>
    <string name="buyer_physical_person_switch">Osoba fizyczna (bez NIP)</string>
    <string name="buyer_name">Imię i nazwisko</string>
    <string name="buyer_nip">NIP nabywcy</string>
    <string name="buyer_address_street">Ulica i numer</string>
    <string name="buyer_address_postal">Kod pocztowy</string>
    <string name="buyer_address_city">Miasto</string>
    <string name="invoice_service_section">Usługa / towar</string>
    <string name="service_name">Nazwa usługi lub towaru</string>
    <string name="service_amount">Kwota brutto (PLN)</string>
    <string name="payment_date_label">Data zapłaty</string>
    <string name="service_date_label">Data wykonania usługi / sprzedaży</string>
    <string name="payment_method_label">Sposób płatności</string>
    <string name="payment_method_cash">Gotówka</string>
    <string name="payment_method_transfer">Przelew</string>
    <string name="payment_method_blik">BLIK</string>
    <string name="payment_paid_cash">Zapłacono gotówką</string>
    <string name="payment_paid_transfer">Zapłacono przelewem</string>
    <string name="payment_paid_blik">Zapłacono BLIK</string>
    <string name="cash_limit_title">Sprzedaż gotówkowa dla osób fizycznych w tym roku</string>
    <string name="cash_limit_label">%1$s / %2$s PLN</string>
    <string name="cash_limit_warning">Zbliżasz się do rocznego limitu sprzedaży gotówkowej dla osób fizycznych bez kasy fiskalnej.</string>
    <string name="cash_limit_exceeded_warning">Przekroczono roczny limit 20 000 PLN sprzedaży gotówkowej dla osób fizycznych — może być wymagana kasa fiskalna.</string>
    <string name="generate_invoice_button">Generuj PDF</string>
    <string name="invoice_generated_toast">Zapisano dokument: %1$s</string>
    <string name="invoice_error_toast">Nie udało się wygenerować dokumentu: %1$s</string>
    <string name="open_pdf_button">Otwórz PDF</string>
    <string name="share_invoice_button">Udostępnij</string>
    <string name="open_invoices_folder_button">Otwórz folder z fakturami</string>
    <string name="open_folder_error">Nie udało się otworzyć folderu. Pliki są zapisane w %1$s</string>
    <string name="invoice_fill_required_fields">Uzupełnij dane nabywcy, usługę i kwotę</string>
</resources>'''

content = content.replace("</resources>", addition, 1)
with io.open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("OK: %s -> добавлены строки счёта" % path)
EOF_PY_STRINGS_PL

echo "-- Русский: app/src/main/res/values-ru/strings.xml --"
python3 - "app/src/main/res/values-ru/strings.xml" << 'EOF_PY_STRINGS_RU'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "nav_invoices" in content:
    print("OK (уже применено): %s" % path)
    sys.exit(0)

if "</resources>" not in content:
    print("!!! Не найден </resources> в %s" % path)
    sys.exit(1)

addition = '''

    <!-- Счета / Фактуры -->
    <string name="nav_invoices">Счета</string>
    <string name="invoice_form_title">Новый счёт / рахунек</string>
    <string name="invoice_seller_section">Продавец (ваши данные)</string>
    <string name="seller_name">Имя и фамилия / название фирмы</string>
    <string name="seller_nip">NIP (оставьте пустым, если нет)</string>
    <string name="seller_address_street">Улица и номер</string>
    <string name="seller_address_postal">Почтовый индекс</string>
    <string name="seller_address_city">Город</string>
    <string name="invoice_buyer_section">Покупатель</string>
    <string name="buyer_physical_person_switch">Физическое лицо (без NIP)</string>
    <string name="buyer_name">Имя и фамилия</string>
    <string name="buyer_nip">NIP покупателя</string>
    <string name="buyer_address_street">Улица и номер</string>
    <string name="buyer_address_postal">Почтовый индекс</string>
    <string name="buyer_address_city">Город</string>
    <string name="invoice_service_section">Услуга / товар</string>
    <string name="service_name">Наименование услуги или товара</string>
    <string name="service_amount">Сумма брутто (PLN)</string>
    <string name="payment_date_label">Дата оплаты</string>
    <string name="service_date_label">Дата оказания услуги / продажи</string>
    <string name="payment_method_label">Способ оплаты</string>
    <string name="payment_method_cash">Наличные</string>
    <string name="payment_method_transfer">Перевод</string>
    <string name="payment_method_blik">BLIK</string>
    <string name="payment_paid_cash">Оплачено наличными</string>
    <string name="payment_paid_transfer">Оплачено переводом</string>
    <string name="payment_paid_blik">Оплачено через BLIK</string>
    <string name="cash_limit_title">Наличные продажи физлицам за год</string>
    <string name="cash_limit_label">%1$s / %2$s PLN</string>
    <string name="cash_limit_warning">Вы приближаетесь к годовому лимиту наличных расчётов с физлицами без кассового аппарата.</string>
    <string name="cash_limit_exceeded_warning">Превышен годовой лимит 20 000 PLN наличных расчётов с физлицами — может потребоваться кассовый аппарат.</string>
    <string name="generate_invoice_button">Сформировать PDF</string>
    <string name="invoice_generated_toast">Документ сохранён: %1$s</string>
    <string name="invoice_error_toast">Не удалось создать документ: %1$s</string>
    <string name="open_pdf_button">Открыть PDF</string>
    <string name="share_invoice_button">Отправить</string>
    <string name="open_invoices_folder_button">Открыть папку со счетами</string>
    <string name="open_folder_error">Не удалось открыть папку. Файлы сохранены в %1$s</string>
    <string name="invoice_fill_required_fields">Заполните данные покупателя, услугу и сумму</string>
</resources>'''

content = content.replace("</resources>", addition, 1)
with io.open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("OK: %s -> добавлены строки счёта" % path)
EOF_PY_STRINGS_RU


echo ""
echo "=== Готово. Дальше вручную: ==="
echo "1) Пересобери APK:  ./gradlew assembleDebug"
echo "2) Установи и проверь: на главном экране новая кнопка 'Faktury/Rachunki',"
echo "   форма создаёт PDF в Documents/FinArs/Invoices, лимит наличных 20000 zl считается верно."
echo "3) Если всё ок:"
echo "   git add -A"
echo "   git commit -m 'Add invoices/rachunki feature: seller/buyer form, PDF generation, cash limit tracking'"
echo "   git push"
echo ""
echo "Бэкап изменённых (не новых) файлов лежит в: $BACKUP_DIR — можно удалить после проверки."
