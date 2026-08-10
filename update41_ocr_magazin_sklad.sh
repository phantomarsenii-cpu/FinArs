#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=== Обновление 41: OCR чеков, склад (Magazin) со штрихкодами, многопозиционные фактуры ==="
echo "Что добавляется:"
echo " - Настройки -> Тип деятельности: Продажи / Услуги / Смешанная"
echo " - Склад (Magazin): список товаров, остатки, порог 'заканчивается', уведомления"
echo " - Сканирование штрихкода (ZXing): поиск товара в Open Food Facts, если не найден — ручной ввод с привязкой штрихкода"
echo " - Faktury: можно добавить несколько позиций со склада — сумма и списание остатков считаются автоматически"
echo " - Сканирование чека (ML Kit OCR): автозаполнение суммы, даты и продавца по фото"
echo " - Room обновлена до версии 4 с МИГРАЦИЕЙ (не destructive) — старые данные не теряются"
echo ""

if [ ! -f "settings.gradle" ] || [ ! -d "app/src/main/java/com/example/fa_ksiegowy" ]; then
    echo "!!! Запусти скрипт из корня проекта FA_ksiegowy-main (там, где settings.gradle)"
    exit 1
fi
if [ ! -f "app/src/main/java/com/example/fa_ksiegowy/AppDatabase.kt" ]; then
    echo "!!! Не найден AppDatabase.kt — запусти скрипт из корня проекта"
    exit 1
fi

BACKUP_DIR=".update41_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
for f in \
    "app/build.gradle" \
    "app/src/main/AndroidManifest.xml" \
    "app/src/main/java/com/example/fa_ksiegowy/AppDatabase.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/SettingsActivity.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/MineActivity.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/AddEntryActivity.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt" \
    "app/src/main/res/layout/activity_settings.xml" \
    "app/src/main/res/layout/activity_mine.xml" \
    "app/src/main/res/layout/activity_add_entry.xml" \
    "app/src/main/res/layout/activity_add_invoice.xml" \
    "app/src/main/res/values/strings.xml" \
    "app/src/main/res/values-ru/strings.xml" \
    "app/src/main/res/values-pl/strings.xml"
do
    if [ -f "$f" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$f")"
        cp "$f" "$BACKUP_DIR/$f"
    fi
done
echo "--- Бэкап изменяемых файлов сохранён в $BACKUP_DIR ---"
echo ""
echo "--- Пишу новые файлы ---"

JAVA_DIR="app/src/main/java/com/example/fa_ksiegowy"
LAYOUT_DIR="app/src/main/res/layout"

# ---------------------------------------------------------------------------
# BusinessKind.kt
# ---------------------------------------------------------------------------
cat > "$JAVA_DIR/BusinessKind.kt" << 'EOF_U41_BUSINESSKIND_KT'
package com.example.fa_ksiegowy

import android.content.SharedPreferences

/**
 * Тип деятельности пользователя, выбираемый в настройках. От него зависит,
 * появляется ли на главном экране кнопка "Склад" (Magazin) и связанная
 * логика списания товара при выставлении фактуры.
 */
enum class BusinessKind {
    SALES,
    SERVICES,
    MIXED;

    val showsMagazin: Boolean get() = this == SALES || this == MIXED
}

object BusinessKindHelper {
    private const val KEY = "business_kind"

    fun get(prefs: SharedPreferences): BusinessKind {
        val raw = prefs.getString(KEY, BusinessKind.SERVICES.name) ?: BusinessKind.SERVICES.name
        return try {
            BusinessKind.valueOf(raw)
        } catch (e: IllegalArgumentException) {
            BusinessKind.SERVICES
        }
    }

    fun set(prefs: SharedPreferences, kind: BusinessKind) {
        prefs.edit().putString(KEY, kind.name).apply()
    }
}
EOF_U41_BUSINESSKIND_KT
echo "OK: $JAVA_DIR/BusinessKind.kt"

# ---------------------------------------------------------------------------
# Product.kt
# ---------------------------------------------------------------------------
cat > "$JAVA_DIR/Product.kt" << 'EOF_U41_PRODUCT_KT'
package com.example.fa_ksiegowy

import androidx.room.Entity
import androidx.room.PrimaryKey

/** Товар на складе. barcode может быть null для товаров, добавленных вручную без сканирования. */
@Entity(tableName = "products")
data class Product(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val barcode: String?,
    val name: String,
    val quantity: Double,
    val unit: String = "szt.",
    val lowStockThreshold: Double = 5.0,
    val priceNet: Double = 0.0,
    val updatedAtMillis: Long = System.currentTimeMillis()
) {
    val isLowStock: Boolean get() = quantity <= lowStockThreshold
}
EOF_U41_PRODUCT_KT
echo "OK: $JAVA_DIR/Product.kt"

# ---------------------------------------------------------------------------
# ProductDao.kt
# ---------------------------------------------------------------------------
cat > "$JAVA_DIR/ProductDao.kt" << 'EOF_U41_PRODUCTDAO_KT'
package com.example.fa_ksiegowy

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update

@Dao
interface ProductDao {
    @Insert
    suspend fun insert(product: Product): Long

    @Update
    suspend fun update(product: Product)

    @Delete
    suspend fun delete(product: Product)

    @Query("SELECT * FROM products WHERE id = :id LIMIT 1")
    suspend fun getById(id: Long): Product?

    @Query("SELECT * FROM products WHERE barcode = :barcode LIMIT 1")
    suspend fun getByBarcode(barcode: String): Product?

    @Query("SELECT * FROM products ORDER BY name ASC")
    suspend fun getAll(): List<Product>

    @Query("SELECT * FROM products WHERE quantity <= lowStockThreshold")
    suspend fun getLowStock(): List<Product>

    /** Списание при продаже. Остаток не уходит ниже нуля. */
    @Query("UPDATE products SET quantity = MAX(0, quantity - :amount), updatedAtMillis = :now WHERE id = :id")
    suspend fun decrementQuantity(id: Long, amount: Double, now: Long = System.currentTimeMillis())
}
EOF_U41_PRODUCTDAO_KT
echo "OK: $JAVA_DIR/ProductDao.kt"

# ---------------------------------------------------------------------------
# InvoiceItem.kt
# ---------------------------------------------------------------------------
cat > "$JAVA_DIR/InvoiceItem.kt" << 'EOF_U41_INVOICEITEM_KT'
package com.example.fa_ksiegowy

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Одна позиция многопозиционной фактуры. productId == null означает, что
 * позиция была добавлена вручную, а не выбрана со склада (склад не затрагивается).
 */
@Entity(tableName = "invoice_items")
data class InvoiceItem(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val invoiceId: Long,
    val productId: Long?,
    val name: String,
    val quantity: Double,
    val unitPrice: Double
)
EOF_U41_INVOICEITEM_KT
echo "OK: $JAVA_DIR/InvoiceItem.kt"

# ---------------------------------------------------------------------------
# InvoiceItemDao.kt
# ---------------------------------------------------------------------------
cat > "$JAVA_DIR/InvoiceItemDao.kt" << 'EOF_U41_INVOICEITEMDAO_KT'
package com.example.fa_ksiegowy

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query

@Dao
interface InvoiceItemDao {
    @Insert
    suspend fun insertAll(items: List<InvoiceItem>)

    @Query("SELECT * FROM invoice_items WHERE invoiceId = :invoiceId")
    suspend fun getForInvoice(invoiceId: Long): List<InvoiceItem>
}
EOF_U41_INVOICEITEMDAO_KT
echo "OK: $JAVA_DIR/InvoiceItemDao.kt"

# ---------------------------------------------------------------------------
# ProductLookupService.kt (Open Food Facts — бесплатно, без ключа)
# ---------------------------------------------------------------------------
cat > "$JAVA_DIR/ProductLookupService.kt" << 'EOF_U41_PRODUCTLOOKUPSERVICE_KT'
package com.example.fa_ksiegowy

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Поиск названия товара по штрихкоду через открытую базу Open Food Facts.
 * Покрывает в основном продукты питания/бытовые товары — для остального
 * (или если интернета нет) возвращает null, и приложение переходит
 * к ручному вводу с уже привязанным штрихкодом.
 */
object ProductLookupService {
    suspend fun lookupName(barcode: String): String? = withContext(Dispatchers.IO) {
        try {
            val url = URL("https://world.openfoodfacts.org/api/v0/product/$barcode.json")
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 6000
            conn.readTimeout = 6000
            conn.requestMethod = "GET"
            conn.setRequestProperty("User-Agent", "FA_ksiegowy-Android-App")
            val code = conn.responseCode
            if (code != 200) {
                conn.disconnect()
                return@withContext null
            }
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            conn.disconnect()
            val json = JSONObject(body)
            if (json.optInt("status", 0) != 1) return@withContext null
            val product = json.optJSONObject("product") ?: return@withContext null
            val name = product.optString("product_name").ifBlank {
                product.optString("product_name_ru").ifBlank {
                    product.optString("product_name_pl")
                }
            }
            name.ifBlank { null }
        } catch (e: Exception) {
            null
        }
    }
}
EOF_U41_PRODUCTLOOKUPSERVICE_KT
echo "OK: $JAVA_DIR/ProductLookupService.kt"

# ---------------------------------------------------------------------------
# ReceiptOcrHelper.kt (ML Kit)
# ---------------------------------------------------------------------------
cat > "$JAVA_DIR/ReceiptOcrHelper.kt" << 'EOF_U41_RECEIPTOCRHELPER_KT'
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
 * Сначала пробуем латинский распознаватель (быстрее, покрывает польские чеки и цифры),
 * и если текста почти нет — пробуем кириллический (для русскоязычных чеков).
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
        val latinText = runRecognizer(TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS), image)
        if (latinText.length >= 15) return latinText
        return try {
            val cyrillicOptions = com.google.mlkit.vision.text.cyrillic.TextRecognizerOptions.Builder().build()
            val cyrillicText = runRecognizer(TextRecognition.getClient(cyrillicOptions), image)
            if (cyrillicText.length > latinText.length) cyrillicText else latinText
        } catch (e: Exception) {
            latinText
        }
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
EOF_U41_RECEIPTOCRHELPER_KT
echo "OK: $JAVA_DIR/ReceiptOcrHelper.kt"

# ---------------------------------------------------------------------------
# StockNotificationWorker.kt
# ---------------------------------------------------------------------------
cat > "$JAVA_DIR/StockNotificationWorker.kt" << 'EOF_U41_STOCKNOTIFICATIONWORKER_KT'
package com.example.fa_ksiegowy

import android.content.Context
import android.content.SharedPreferences
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

/** Ежедневная проверка остатков на складе — уведомление раз в день на товар, если остаток низкий. */
class StockNotificationWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        return try {
            val prefs = applicationContext.getSharedPreferences("settings", Context.MODE_PRIVATE)
            if (!BusinessKindHelper.get(prefs).showsMagazin) return Result.success()
            val dao = AppDatabase.getInstance(applicationContext).productDao()
            val today = SDF_DAY.format(Date())
            for (p in dao.getLowStock()) {
                notifyOnce(
                    prefs, "stock_low_${p.id}_$today",
                    applicationContext.getString(R.string.notif_low_stock_title),
                    applicationContext.getString(
                        R.string.notif_low_stock_text,
                        p.name,
                        String.format(Locale.getDefault(), "%.1f", p.quantity),
                        p.unit
                    )
                )
            }
            Result.success()
        } catch (e: Exception) {
            Result.retry()
        }
    }

    private fun notifyOnce(prefs: SharedPreferences, key: String, title: String, text: String) {
        if (prefs.getBoolean("notif_shown_$key", false)) return
        prefs.edit().putBoolean("notif_shown_$key", true).apply()
        LimitsNotificationWorker.showNotification(applicationContext, key.hashCode(), title, text)
    }

    companion object {
        private val SDF_DAY = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        private const val UNIQUE_WORK_NAME = "fa_stock_low_daily_check"

        fun schedule(context: Context) {
            LimitsNotificationWorker.createChannel(context)
            val request = PeriodicWorkRequestBuilder<StockNotificationWorker>(24, TimeUnit.HOURS).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request
            )
        }
    }
}
EOF_U41_STOCKNOTIFICATIONWORKER_KT
echo "OK: $JAVA_DIR/StockNotificationWorker.kt"

# ---------------------------------------------------------------------------
# ProductAdapter.kt
# ---------------------------------------------------------------------------
cat > "$JAVA_DIR/ProductAdapter.kt" << 'EOF_U41_PRODUCTADAPTER_KT'
package com.example.fa_ksiegowy

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.RecyclerView
import java.util.Locale

class ProductAdapter(
    private val onClick: (Product) -> Unit,
    private val onLongClick: (Product) -> Boolean
) : RecyclerView.Adapter<ProductAdapter.VH>() {
    private var items: List<Product> = emptyList()

    class VH(view: View) : RecyclerView.ViewHolder(view) {
        val tvName: TextView = view.findViewById(R.id.tv_product_name)
        val tvQty: TextView = view.findViewById(R.id.tv_product_qty)
        val tvBarcode: TextView = view.findViewById(R.id.tv_product_barcode)
    }

    fun submitList(newItems: List<Product>) {
        items = newItems
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val v = LayoutInflater.from(parent.context).inflate(R.layout.item_product, parent, false)
        return VH(v)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        val p = items[position]
        holder.tvName.text = p.name
        holder.tvQty.text = String.format(Locale.getDefault(), "%.1f %s", p.quantity, p.unit)
        holder.tvQty.setTextColor(
            ContextCompat.getColor(holder.itemView.context, if (p.isLowStock) R.color.expense_red else R.color.text_primary)
        )
        holder.tvBarcode.text = p.barcode ?: ""
        holder.itemView.setOnClickListener { onClick(p) }
        holder.itemView.setOnLongClickListener { onLongClick(p) }
    }

    override fun getItemCount(): Int = items.size
}
EOF_U41_PRODUCTADAPTER_KT
echo "OK: $JAVA_DIR/ProductAdapter.kt"

# ---------------------------------------------------------------------------
# MagazinActivity.kt
# ---------------------------------------------------------------------------
cat > "$JAVA_DIR/MagazinActivity.kt" << 'EOF_U41_MAGAZINACTIVITY_KT'
package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Склад: список товаров, добавление вручную или сканированием штрихкода, удаление. */
class MagazinActivity : BaseActivity() {
    private lateinit var adapter: ProductAdapter

    private val scanLauncher = registerForActivityResult(ScanContract()) { result ->
        val barcode = result.contents
        if (barcode != null) handleScannedBarcode(barcode)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_magazin)

        adapter = ProductAdapter(
            onClick = { p ->
                startActivity(Intent(this, AddEditProductActivity::class.java).putExtra("productId", p.id))
            },
            onLongClick = { p -> confirmDelete(p); true }
        )
        findViewById<RecyclerView>(R.id.rv_products).apply {
            layoutManager = LinearLayoutManager(this@MagazinActivity)
            adapter = this@MagazinActivity.adapter
        }

        findViewById<Button>(R.id.btn_add_product_manual).setOnClickListener {
            startActivity(Intent(this, AddEditProductActivity::class.java))
        }
        findViewById<Button>(R.id.btn_scan_barcode).setOnClickListener {
            scanLauncher.launch(
                ScanOptions()
                    .setDesiredBarcodeFormats(ScanOptions.ALL_CODE_TYPES)
                    .setPrompt(getString(R.string.scan_barcode_prompt))
                    .setBeepEnabled(true)
                    .setOrientationLocked(true)
            )
        }
    }

    override fun onResume() {
        super.onResume()
        loadProducts()
    }

    private fun loadProducts() {
        CoroutineScope(Dispatchers.IO).launch {
            val all = AppDatabase.getInstance(applicationContext).productDao().getAll()
            withContext(Dispatchers.Main) {
                adapter.submitList(all)
                val low = all.filter { it.isLowStock }
                val banner = findViewById<TextView>(R.id.tv_low_stock_banner)
                if (low.isNotEmpty()) {
                    banner.text = getString(R.string.low_stock_banner, low.size)
                    banner.visibility = View.VISIBLE
                } else {
                    banner.visibility = View.GONE
                }
            }
        }
    }

    /** Штрихкод отсканирован: если товар уже есть — открываем на редактирование (пополнение),
     *  иначе пробуем найти название в Open Food Facts, а если не нашли — открываем ручной ввод
     *  с уже подставленным штрихкодом. */
    private fun handleScannedBarcode(barcode: String) {
        CoroutineScope(Dispatchers.IO).launch {
            val existing = AppDatabase.getInstance(applicationContext).productDao().getByBarcode(barcode)
            if (existing != null) {
                withContext(Dispatchers.Main) {
                    startActivity(Intent(this@MagazinActivity, AddEditProductActivity::class.java).putExtra("productId", existing.id))
                }
                return@launch
            }
            withContext(Dispatchers.Main) {
                Toast.makeText(this@MagazinActivity, getString(R.string.looking_up_product), Toast.LENGTH_SHORT).show()
            }
            val name = ProductLookupService.lookupName(barcode)
            withContext(Dispatchers.Main) {
                val i = Intent(this@MagazinActivity, AddEditProductActivity::class.java)
                i.putExtra("barcode", barcode)
                if (name != null) i.putExtra("prefillName", name)
                startActivity(i)
            }
        }
    }

    private fun confirmDelete(p: Product) {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.delete_confirm_title))
            .setMessage(getString(R.string.delete_confirm_message))
            .setPositiveButton(getString(R.string.delete_confirm_yes)) { _, _ ->
                CoroutineScope(Dispatchers.IO).launch {
                    AppDatabase.getInstance(applicationContext).productDao().delete(p)
                    withContext(Dispatchers.Main) { loadProducts() }
                }
            }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
    }
}
EOF_U41_MAGAZINACTIVITY_KT
echo "OK: $JAVA_DIR/MagazinActivity.kt"

# ---------------------------------------------------------------------------
# AddEditProductActivity.kt
# ---------------------------------------------------------------------------
cat > "$JAVA_DIR/AddEditProductActivity.kt" << 'EOF_U41_ADDEDITPRODUCTACTIVITY_KT'
package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.Toast
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Добавление товара вручную ИЛИ редактирование существующего (открывается со склада или после сканирования). */
class AddEditProductActivity : BaseActivity() {
    private var editing: Product? = null

    private val scanLauncher = registerForActivityResult(ScanContract()) { result ->
        result.contents?.let { findViewById<EditText>(R.id.et_barcode).setText(it) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_add_edit_product)

        val productId = intent.getLongExtra("productId", -1L)
        intent.getStringExtra("barcode")?.let { findViewById<EditText>(R.id.et_barcode).setText(it) }
        intent.getStringExtra("prefillName")?.let { findViewById<EditText>(R.id.et_name).setText(it) }

        findViewById<Button>(R.id.btn_scan_barcode_form).setOnClickListener {
            scanLauncher.launch(ScanOptions().setBeepEnabled(true).setOrientationLocked(true))
        }
        findViewById<Button>(R.id.btn_save_product).setOnClickListener { save() }
        findViewById<Button>(R.id.btn_delete_product).setOnClickListener { confirmDelete() }

        if (productId != -1L) {
            findViewById<Button>(R.id.btn_delete_product).visibility = View.VISIBLE
            CoroutineScope(Dispatchers.IO).launch {
                val p = AppDatabase.getInstance(applicationContext).productDao().getById(productId)
                withContext(Dispatchers.Main) {
                    if (p == null) {
                        finish()
                        return@withContext
                    }
                    editing = p
                    findViewById<EditText>(R.id.et_name).setText(p.name)
                    findViewById<EditText>(R.id.et_barcode).setText(p.barcode ?: "")
                    findViewById<EditText>(R.id.et_quantity).setText(formatNum(p.quantity))
                    findViewById<EditText>(R.id.et_unit).setText(p.unit)
                    findViewById<EditText>(R.id.et_low_stock).setText(formatNum(p.lowStockThreshold))
                    findViewById<EditText>(R.id.et_price).setText(formatNum(p.priceNet))
                }
            }
        }
    }

    private fun confirmDelete() {
        val p = editing ?: return
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.delete_confirm_title))
            .setMessage(getString(R.string.delete_confirm_message))
            .setPositiveButton(getString(R.string.delete_confirm_yes)) { _, _ ->
                CoroutineScope(Dispatchers.IO).launch {
                    AppDatabase.getInstance(applicationContext).productDao().delete(p)
                    withContext(Dispatchers.Main) { finish() }
                }
            }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
    }

    private fun save() {
        val name = findViewById<EditText>(R.id.et_name).text.toString().trim()
        val barcode = findViewById<EditText>(R.id.et_barcode).text.toString().trim().ifBlank { null }
        val qty = findViewById<EditText>(R.id.et_quantity).text.toString().toDoubleOrNull()
        val unit = findViewById<EditText>(R.id.et_unit).text.toString().trim().ifBlank { "szt." }
        val low = findViewById<EditText>(R.id.et_low_stock).text.toString().toDoubleOrNull() ?: 5.0
        val price = findViewById<EditText>(R.id.et_price).text.toString().toDoubleOrNull() ?: 0.0

        if (name.isBlank() || qty == null) {
            Toast.makeText(this, getString(R.string.invoice_fill_required_fields), Toast.LENGTH_SHORT).show()
            return
        }

        val existing = editing
        CoroutineScope(Dispatchers.IO).launch {
            val dao = AppDatabase.getInstance(applicationContext).productDao()
            if (existing != null) {
                dao.update(
                    existing.copy(
                        name = name, barcode = barcode, quantity = qty, unit = unit,
                        lowStockThreshold = low, priceNet = price, updatedAtMillis = System.currentTimeMillis()
                    )
                )
            } else {
                dao.insert(Product(barcode = barcode, name = name, quantity = qty, unit = unit, lowStockThreshold = low, priceNet = price))
            }
            withContext(Dispatchers.Main) {
                Toast.makeText(this@AddEditProductActivity, getString(R.string.product_saved), Toast.LENGTH_SHORT).show()
                finish()
            }
        }
    }

    private fun formatNum(v: Double): String = if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()
}
EOF_U41_ADDEDITPRODUCTACTIVITY_KT
echo "OK: $JAVA_DIR/AddEditProductActivity.kt"

# ---------------------------------------------------------------------------
# SelectProductsActivity.kt (+ PickedProduct)
# ---------------------------------------------------------------------------
cat > "$JAVA_DIR/SelectProductsActivity.kt" << 'EOF_U41_SELECTPRODUCTSACTIVITY_KT'
package com.example.fa_ksiegowy

import android.content.Intent
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Позиция, выбранная со склада для фактуры. */
data class PickedProduct(val productId: Long, val name: String, val quantity: Double, val unitPrice: Double)

/** Выбор нескольких товаров со склада (с количеством) для многопозиционной фактуры. */
class SelectProductsActivity : BaseActivity() {
    private var products: List<Product> = emptyList()
    private val checkedQty = mutableMapOf<Long, Double>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_select_products)
        findViewById<Button>(R.id.btn_confirm_selection).setOnClickListener { confirmSelection() }
        loadProducts()
    }

    private fun loadProducts() {
        CoroutineScope(Dispatchers.IO).launch {
            val all = AppDatabase.getInstance(applicationContext).productDao().getAll()
            withContext(Dispatchers.Main) {
                products = all
                renderList()
            }
        }
    }

    private fun renderList() {
        val container = findViewById<LinearLayout>(R.id.ll_products_container)
        container.removeAllViews()
        if (products.isEmpty()) {
            val empty = TextView(this)
            empty.text = getString(R.string.magazin_empty)
            empty.setTextColor(resources.getColor(R.color.text_secondary, theme))
            container.addView(empty)
            return
        }
        val inflater = LayoutInflater.from(this)
        for (p in products) {
            val row = inflater.inflate(R.layout.item_product_select, container, false)
            val cb = row.findViewById<CheckBox>(R.id.cb_select)
            val tvName = row.findViewById<TextView>(R.id.tv_select_name)
            val etQty = row.findViewById<EditText>(R.id.et_select_qty)

            tvName.text = "${p.name} (${formatNum(p.quantity)} ${p.unit} ${getString(R.string.in_stock_suffix)})"
            etQty.setText("1")
            etQty.isEnabled = false

            cb.setOnCheckedChangeListener { _, isChecked ->
                etQty.isEnabled = isChecked
                if (isChecked) {
                    checkedQty[p.id] = etQty.text.toString().toDoubleOrNull() ?: 1.0
                } else {
                    checkedQty.remove(p.id)
                }
            }
            etQty.addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
                override fun afterTextChanged(s: Editable?) {
                    if (cb.isChecked) checkedQty[p.id] = s.toString().toDoubleOrNull() ?: 1.0
                }
            })
            container.addView(row)
        }
    }

    private fun confirmSelection() {
        val picked = products.filter { checkedQty.containsKey(it.id) }
            .map { PickedProduct(it.id, it.name, checkedQty[it.id] ?: 1.0, it.priceNet) }
        if (picked.isEmpty()) {
            Toast.makeText(this, getString(R.string.select_at_least_one_product), Toast.LENGTH_SHORT).show()
            return
        }
        val serialized = picked.joinToString("\n") { "${it.productId}|${it.name}|${it.quantity}|${it.unitPrice}" }
        val i = Intent()
        i.putExtra("picked_items", serialized)
        setResult(RESULT_OK, i)
        finish()
    }

    private fun formatNum(v: Double): String = if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()
}
EOF_U41_SELECTPRODUCTSACTIVITY_KT
echo "OK: $JAVA_DIR/SelectProductsActivity.kt"

# ---------------------------------------------------------------------------
# SettingsBusinessActivity.kt
# ---------------------------------------------------------------------------
cat > "$JAVA_DIR/SettingsBusinessActivity.kt" << 'EOF_U41_SETTINGSBUSINESSACTIVITY_KT'
package com.example.fa_ksiegowy

import android.os.Bundle
import android.widget.Button
import android.widget.Toast

/** Настройки -> Тип деятельности: определяет, показывается ли на главном экране "Склад". */
class SettingsBusinessActivity : BaseActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings_business)

        val prefs = getSharedPreferences("settings", MODE_PRIVATE)
        applyUi(BusinessKindHelper.get(prefs))

        findViewById<Button>(R.id.btn_business_sales).setOnClickListener { choose(prefs, BusinessKind.SALES) }
        findViewById<Button>(R.id.btn_business_services).setOnClickListener { choose(prefs, BusinessKind.SERVICES) }
        findViewById<Button>(R.id.btn_business_mixed).setOnClickListener { choose(prefs, BusinessKind.MIXED) }
    }

    private fun choose(prefs: android.content.SharedPreferences, kind: BusinessKind) {
        BusinessKindHelper.set(prefs, kind)
        applyUi(kind)
        Toast.makeText(this, getString(R.string.saved), Toast.LENGTH_SHORT).show()
    }

    private fun applyUi(kind: BusinessKind) {
        setState(findViewById(R.id.btn_business_sales), kind == BusinessKind.SALES)
        setState(findViewById(R.id.btn_business_services), kind == BusinessKind.SERVICES)
        setState(findViewById(R.id.btn_business_mixed), kind == BusinessKind.MIXED)
    }

    private fun setState(b: Button, selected: Boolean) {
        b.setBackgroundResource(if (selected) R.drawable.btn_pill_primary else R.drawable.btn_pill_outline)
    }
}
EOF_U41_SETTINGSBUSINESSACTIVITY_KT
echo "OK: $JAVA_DIR/SettingsBusinessActivity.kt"

echo ""
echo "--- Пишу новые layout-файлы ---"

cat > "$LAYOUT_DIR/item_product.xml" << 'EOF_U41_ITEM_PRODUCT_XML'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="horizontal"
    android:background="@drawable/card_bg"
    android:padding="12dp"
    android:layout_marginBottom="8dp"
    android:gravity="center_vertical">

    <LinearLayout
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:orientation="vertical">

        <TextView
            android:id="@+id/tv_product_name"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:textColor="@color/text_primary"
            android:textSize="15sp"
            android:textStyle="bold"/>

        <TextView
            android:id="@+id/tv_product_barcode"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:textColor="@color/text_secondary"
            android:textSize="11sp"/>

    </LinearLayout>

    <TextView
        android:id="@+id/tv_product_qty"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginStart="10dp"
        android:gravity="end"
        android:textSize="15sp"
        android:textStyle="bold"/>

</LinearLayout>
EOF_U41_ITEM_PRODUCT_XML
echo "OK: $LAYOUT_DIR/item_product.xml"

cat > "$LAYOUT_DIR/activity_magazin.xml" << 'EOF_U41_ACTIVITY_MAGAZIN_XML'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:orientation="vertical"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:padding="24dp">

    <TextView
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="@string/magazin_title"
        android:textSize="22sp"
        android:textStyle="bold"
        android:textColor="@color/accent_cyan"
        android:layout_marginBottom="14dp"/>

    <TextView
        android:id="@+id/tv_low_stock_banner"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:background="@drawable/card_bg"
        android:backgroundTint="#3A1414"
        android:padding="12dp"
        android:layout_marginBottom="12dp"
        android:textColor="#FF6B6B"
        android:textSize="13sp"
        android:textStyle="bold"
        android:visibility="gone"/>

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:weightSum="2"
        android:baselineAligned="false"
        android:layout_marginBottom="16dp">

        <Button
            android:id="@+id/btn_add_product_manual"
            android:layout_width="0dp"
            android:layout_height="52dp"
            android:layout_weight="1"
            android:layout_marginEnd="8dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/add_product_manually"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="13sp"/>

        <Button
            android:id="@+id/btn_scan_barcode"
            android:layout_width="0dp"
            android:layout_height="52dp"
            android:layout_weight="1"
            android:layout_marginStart="8dp"
            android:background="@drawable/btn_pill_primary"
            android:text="@string/scan_barcode"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="13sp"/>

    </LinearLayout>

    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/rv_products"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"/>

</LinearLayout>
EOF_U41_ACTIVITY_MAGAZIN_XML
echo "OK: $LAYOUT_DIR/activity_magazin.xml"

cat > "$LAYOUT_DIR/activity_add_edit_product.xml" << 'EOF_U41_ACTIVITY_ADD_EDIT_PRODUCT_XML'
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
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="@string/magazin_title"
        android:textColor="@color/accent_cyan"
        android:textSize="24sp"
        android:textStyle="bold"
        android:layout_marginBottom="20dp"/>

    <EditText android:id="@+id/et_name" android:layout_width="match_parent" android:layout_height="56dp"
        android:layout_marginBottom="14dp" android:background="@drawable/input_field_bg"
        android:paddingStart="18dp" android:paddingEnd="18dp" android:hint="@string/product_name"
        android:textColorHint="@color/text_hint" android:textColor="@color/text_primary" android:inputType="text"/>

    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="horizontal" android:layout_marginBottom="14dp" android:gravity="center_vertical">
        <EditText android:id="@+id/et_barcode" android:layout_width="0dp" android:layout_weight="1" android:layout_height="56dp"
            android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:hint="@string/product_barcode" android:textColorHint="@color/text_hint"
            android:textColor="@color/text_primary" android:inputType="number"/>
        <Button android:id="@+id/btn_scan_barcode_form" android:layout_width="56dp" android:layout_height="56dp"
            android:layout_marginStart="8dp" android:background="@drawable/btn_pill_outline"
            android:text="@string/scan_short" android:textAllCaps="false" android:textColor="@color/accent_cyan" android:textSize="11sp"/>
    </LinearLayout>

    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="horizontal" android:layout_marginBottom="14dp" android:weightSum="2" android:baselineAligned="false">
        <EditText android:id="@+id/et_quantity" android:layout_width="0dp" android:layout_weight="1" android:layout_height="56dp"
            android:layout_marginEnd="8dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:hint="@string/product_quantity" android:textColorHint="@color/text_hint" android:textColor="@color/text_primary" android:inputType="numberDecimal"/>
        <EditText android:id="@+id/et_unit" android:layout_width="0dp" android:layout_weight="1" android:layout_height="56dp"
            android:layout_marginStart="8dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:hint="@string/product_unit" android:textColorHint="@color/text_hint" android:textColor="@color/text_primary" android:inputType="text"/>
    </LinearLayout>

    <EditText android:id="@+id/et_low_stock" android:layout_width="match_parent" android:layout_height="56dp"
        android:layout_marginBottom="14dp" android:background="@drawable/input_field_bg"
        android:paddingStart="18dp" android:paddingEnd="18dp" android:hint="@string/product_low_stock"
        android:textColorHint="@color/text_hint" android:textColor="@color/text_primary" android:inputType="numberDecimal"/>

    <EditText android:id="@+id/et_price" android:layout_width="match_parent" android:layout_height="56dp"
        android:layout_marginBottom="28dp" android:background="@drawable/input_field_bg"
        android:paddingStart="18dp" android:paddingEnd="18dp" android:hint="@string/product_price"
        android:textColorHint="@color/text_hint" android:textColor="@color/text_primary" android:inputType="numberDecimal"/>

    <Button android:id="@+id/btn_delete_product" android:layout_width="match_parent" android:layout_height="52dp"
        android:layout_marginBottom="12dp" android:background="@drawable/btn_pill_danger"
        android:text="@string/delete_entry" android:textAllCaps="false" android:textColor="@color/text_primary" android:textSize="15sp"
        android:visibility="gone"/>

    <Button android:id="@+id/btn_save_product" android:layout_width="match_parent" android:layout_height="56dp"
        android:background="@drawable/btn_pill_primary" android:text="@string/save" android:textAllCaps="false"
        android:textColor="@color/text_primary" android:textSize="17sp" android:textStyle="bold"/>

</LinearLayout>
</ScrollView>
EOF_U41_ACTIVITY_ADD_EDIT_PRODUCT_XML
echo "OK: $LAYOUT_DIR/activity_add_edit_product.xml"

cat > "$LAYOUT_DIR/item_product_select.xml" << 'EOF_U41_ITEM_PRODUCT_SELECT_XML'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="horizontal"
    android:background="@drawable/card_bg"
    android:padding="10dp"
    android:layout_marginBottom="6dp"
    android:gravity="center_vertical">

    <CheckBox
        android:id="@+id/cb_select"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"/>

    <TextView
        android:id="@+id/tv_select_name"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:layout_marginStart="8dp"
        android:textColor="@color/text_primary"
        android:textSize="14sp"/>

    <EditText
        android:id="@+id/et_select_qty"
        android:layout_width="56dp"
        android:layout_height="wrap_content"
        android:background="@drawable/input_field_bg"
        android:textColor="@color/text_primary"
        android:gravity="center"
        android:inputType="numberDecimal"/>

</LinearLayout>
EOF_U41_ITEM_PRODUCT_SELECT_XML
echo "OK: $LAYOUT_DIR/item_product_select.xml"

cat > "$LAYOUT_DIR/activity_select_products.xml" << 'EOF_U41_ACTIVITY_SELECT_PRODUCTS_XML'
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
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="@string/select_products_title"
        android:textColor="@color/accent_cyan"
        android:textSize="20sp"
        android:textStyle="bold"
        android:layout_marginBottom="16dp"/>

    <LinearLayout
        android:id="@+id/ll_products_container"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:layout_marginBottom="16dp"/>

    <Button
        android:id="@+id/btn_confirm_selection"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:background="@drawable/btn_pill_primary"
        android:text="@string/save"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="17sp"
        android:textStyle="bold"/>

</LinearLayout>
</ScrollView>
EOF_U41_ACTIVITY_SELECT_PRODUCTS_XML
echo "OK: $LAYOUT_DIR/activity_select_products.xml"

cat > "$LAYOUT_DIR/activity_settings_business.xml" << 'EOF_U41_ACTIVITY_SETTINGS_BUSINESS_XML'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent" android:layout_height="match_parent"
    android:fillViewport="true">

<LinearLayout
    android:orientation="vertical" android:padding="24dp"
    android:layout_width="match_parent" android:layout_height="wrap_content">

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/business_kind_title" android:textSize="22sp" android:textStyle="bold"
        android:textColor="@color/accent_cyan" android:layout_marginBottom="8dp"/>

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/business_kind_description" android:textSize="13sp"
        android:textColor="@color/text_secondary" android:layout_marginBottom="24dp"/>

    <Button android:id="@+id/btn_business_sales" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/business_kind_sales" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
        android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_business_services" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/business_kind_services" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
        android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_business_mixed" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/business_kind_mixed" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"/>

</LinearLayout>
</ScrollView>
EOF_U41_ACTIVITY_SETTINGS_BUSINESS_XML
echo "OK: $LAYOUT_DIR/activity_settings_business.xml"

echo ""
echo "--- Обновляю существующие файлы ---"

# ---------------------------------------------------------------------------
# AppDatabase.kt — версия 4 с миграцией (данные НЕ теряются)
# ---------------------------------------------------------------------------
cat > "$JAVA_DIR/AppDatabase.kt" << 'EOF_U41_APPDATABASE_KT'
package com.example.fa_ksiegowy

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [Entry::class, Invoice::class, RecurringEntry::class, Product::class, InvoiceItem::class],
    version = 4,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun entryDao(): EntryDao

    abstract fun invoiceDao(): InvoiceDao

    abstract fun recurringEntryDao(): RecurringEntryDao

    abstract fun productDao(): ProductDao

    abstract fun invoiceItemDao(): InvoiceItemDao

    companion object {
        /** v3 -> v4: добавлены таблицы склада и позиций фактур. Обычная миграция
         *  (не destructive), чтобы у существующих пользователей не пропали данные. */
        private val MIGRATION_3_4 = object : Migration(3, 4) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    "CREATE TABLE IF NOT EXISTS `products` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `barcode` TEXT, `name` TEXT NOT NULL, `quantity` REAL NOT NULL, `unit` TEXT NOT NULL, `lowStockThreshold` REAL NOT NULL, `priceNet` REAL NOT NULL, `updatedAtMillis` INTEGER NOT NULL)"
                )
                database.execSQL(
                    "CREATE TABLE IF NOT EXISTS `invoice_items` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `invoiceId` INTEGER NOT NULL, `productId` INTEGER, `name` TEXT NOT NULL, `quantity` REAL NOT NULL, `unitPrice` REAL NOT NULL)"
                )
            }
        }

        @Volatile private var INSTANCE: AppDatabase? = null
        fun getInstance(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "fa_ksiegowy.db"
                ).addMigrations(MIGRATION_3_4).fallbackToDestructiveMigration().build().also { INSTANCE = it }
            }
        }
    }
}
EOF_U41_APPDATABASE_KT
echo "OK: $JAVA_DIR/AppDatabase.kt (version 3 -> 4, миграция без потери данных)"

# ---------------------------------------------------------------------------
# SettingsActivity.kt — добавлена кнопка "Тип деятельности"
# ---------------------------------------------------------------------------
cat > "$JAVA_DIR/SettingsActivity.kt" << 'EOF_U41_SETTINGSACTIVITY_KT'
package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Button

/** Главное меню настроек — теперь просто категории, сами экраны вынесены
 *  в отдельные Activity, чтобы список не занимал весь экран и было место
 *  под будущие разделы. */
class SettingsActivity : BaseActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)

        findViewById<Button>(R.id.btn_menu_business).setOnClickListener {
            startActivity(Intent(this, SettingsBusinessActivity::class.java))
        }
        findViewById<Button>(R.id.btn_menu_tax).setOnClickListener {
            startActivity(Intent(this, SettingsTaxActivity::class.java))
        }
        findViewById<Button>(R.id.btn_menu_pit36).setOnClickListener {
            if (BillingManager.isPro(this)) {
                startActivity(Intent(this, Pit36Activity::class.java))
            } else {
                AlertDialog.Builder(this)
                    .setTitle(getString(R.string.pro_feature_locked_title))
                    .setMessage(getString(R.string.pit36_pro_locked_message))
                    .setPositiveButton(getString(R.string.settings_menu_pro)) { _, _ ->
                        startActivity(Intent(this, SettingsProActivity::class.java))
                    }
                    .setNegativeButton(getString(R.string.dialog_close), null)
                    .show()
            }
        }
        findViewById<Button>(R.id.btn_menu_language).setOnClickListener {
            startActivity(Intent(this, SettingsLanguageActivity::class.java))
        }
        findViewById<Button>(R.id.btn_menu_backup).setOnClickListener {
            if (BillingManager.isPro(this)) {
                startActivity(Intent(this, SettingsBackupActivity::class.java))
            } else {
                AlertDialog.Builder(this)
                    .setTitle(getString(R.string.pro_feature_locked_title))
                    .setMessage(getString(R.string.backup_pro_locked_message))
                    .setPositiveButton(getString(R.string.settings_menu_pro)) { _, _ ->
                        startActivity(Intent(this, SettingsProActivity::class.java))
                    }
                    .setNegativeButton(getString(R.string.dialog_close), null)
                    .show()
            }
        }
        findViewById<Button>(R.id.btn_menu_pro).setOnClickListener {
            startActivity(Intent(this, SettingsProActivity::class.java))
        }
        findViewById<Button>(R.id.btn_menu_terms).setOnClickListener {
            val i = Intent(this, TermsActivity::class.java)
            i.putExtra(TermsActivity.EXTRA_READ_ONLY, true)
            startActivity(i)
        }
        findViewById<Button>(R.id.btn_menu_about).setOnClickListener {
            AlertDialog.Builder(this)
                .setTitle(getString(R.string.about_app))
                .setMessage(getString(R.string.about_description))
                .setPositiveButton(getString(R.string.dialog_write)) { _, _ ->
                    val intent = Intent(Intent.ACTION_SENDTO).apply {
                        data = Uri.parse("mailto:" + getString(R.string.about_email))
                    }
                    startActivity(intent)
                }
                .setNegativeButton(getString(R.string.dialog_close), null)
                .show()
        }
    }
}
EOF_U41_SETTINGSACTIVITY_KT
echo "OK: $JAVA_DIR/SettingsActivity.kt"

# ---------------------------------------------------------------------------
# activity_settings.xml — новая кнопка сверху
# ---------------------------------------------------------------------------
cat > "$LAYOUT_DIR/activity_settings.xml" << 'EOF_U41_ACTIVITY_SETTINGS_XML'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent" android:layout_height="match_parent"
    android:fillViewport="true">

<LinearLayout
    android:orientation="vertical" android:padding="24dp"
    android:layout_width="match_parent" android:layout_height="wrap_content">

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/settings" android:textSize="22sp" android:textStyle="bold"
        android:textColor="@color/accent_cyan" android:layout_marginBottom="24dp"/>

    <Button android:id="@+id/btn_menu_business" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/settings_menu_business" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
        android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_menu_tax" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/settings_menu_tax" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
        android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_menu_pit36" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/settings_menu_pit36" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
        android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_menu_language" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/settings_menu_language" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
        android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_menu_backup" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/settings_menu_backup" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
        android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_menu_pro" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/settings_menu_pro" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_primary"
        android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_menu_terms" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/settings_menu_terms" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
        android:layout_marginBottom="14dp"/>

    <View android:layout_width="match_parent" android:layout_height="1dp"
        android:background="#2A2E60" android:layout_marginTop="10dp" android:layout_marginBottom="24dp"/>

    <Button android:id="@+id/btn_menu_about" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/about_app" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"/>

</LinearLayout>
</ScrollView>
EOF_U41_ACTIVITY_SETTINGS_XML
echo "OK: $LAYOUT_DIR/activity_settings.xml"

# ---------------------------------------------------------------------------
# MineActivity.kt — кнопка "Склад" (видна только если BusinessKind.showsMagazin) + воркер остатков
# ---------------------------------------------------------------------------
cat > "$JAVA_DIR/MineActivity.kt" << 'EOF_U41_MINEACTIVITY_KT'
package com.example.fa_ksiegowy

import android.Manifest
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.google.android.gms.ads.AdView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale

class MineActivity : BaseActivity() {
    private lateinit var db: AppDatabase
    private var bannerAdView: AdView? = null

    private val notificationPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { /* результат не критичен для UI */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_mine)
        db = AppDatabase.getInstance(this)

        // Единая кнопка добавления: выбор дохода/расхода происходит уже внутри
        // AddEntryActivity (переключатель с подсветкой выбранного варианта).
        // По умолчанию открываем на "доход", это чаще нужное действие.
        findViewById<Button>(R.id.btn_add_entry).setOnClickListener {
            startActivity(Intent(this, AddEntryActivity::class.java).putExtra("isIncome", true))
        }
        findViewById<Button>(R.id.btn_settings).setOnClickListener {
            startActivity(Intent(this, SettingsActivity::class.java))
        }
        findViewById<Button>(R.id.btn_reports).setOnClickListener {
            startActivity(Intent(this, ReportActivity::class.java))
        }
        findViewById<Button>(R.id.btn_history).setOnClickListener {
            startActivity(Intent(this, HistoryActivity::class.java))
        }
        findViewById<Button>(R.id.btn_invoices).setOnClickListener {
            if (BillingManager.isPro(this)) {
                startActivity(Intent(this, AddInvoiceActivity::class.java))
            } else {
                androidx.appcompat.app.AlertDialog.Builder(this)
                    .setTitle(getString(R.string.pro_feature_locked_title))
                    .setMessage(getString(R.string.invoice_pro_locked_message))
                    .setPositiveButton(getString(R.string.pro_feature_locked_go_settings)) { _, _ ->
                        startActivity(Intent(this, SettingsActivity::class.java))
                    }
                    .setNegativeButton(getString(R.string.dialog_close), null)
                    .show()
            }
        }
        findViewById<Button>(R.id.btn_magazin).setOnClickListener {
            startActivity(Intent(this, MagazinActivity::class.java))
        }


        bannerAdView = AdsManager.setupAndLoadBanner(
            this,
            findViewById<FrameLayout>(R.id.ad_container),
            findViewById(R.id.tv_ad_debug)
        )
        setupHiddenDevCodeGesture()
        requestNotificationPermissionIfNeeded()
        LimitsNotificationWorker.schedule(this)
        InvoiceReminderWorker.schedule(this)
        RecurringEntryWorker.schedule(this)
        StockNotificationWorker.schedule(this)
    }

    /** На Android 13+ уведомления требуют явного разрешения — запрашиваем один раз при первом запуске экрана. */
    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
            if (!granted) {
                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
    }

    /**
     * Скрытый вход для разработчика: удержание пальца на логотипе 10 секунд открывает
     * диалог ввода кода. Никакой видимой кнопки/подсказки в UI нет — это сделано умышленно,
     * чтобы обычный пользователь не наткнулся на неё случайно.
     */
    private fun setupHiddenDevCodeGesture() {
        val handler = Handler(Looper.getMainLooper())
        val holdDurationMs = 10_000L
        var triggered = false

        val showCodeDialog = Runnable {
            if (triggered) return@Runnable
            triggered = true
            val input = EditText(this)
            input.hint = getString(R.string.enter_code_hint)
            AlertDialog.Builder(this)
                .setTitle(getString(R.string.enter_code_title))
                .setView(input)
                .setPositiveButton(getString(R.string.enter_code_apply)) { _, _ ->
                    val ok = BillingManager.tryUnlockWithDevCode(this, input.text.toString())
                    Toast.makeText(
                        this,
                        getString(if (ok) R.string.enter_code_success else R.string.enter_code_wrong),
                        Toast.LENGTH_SHORT
                    ).show()
                }
                .setNegativeButton(getString(R.string.dialog_close), null)
                .show()
        }

        findViewById<ImageView>(R.id.iv_logo).setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    triggered = false
                    handler.postDelayed(showCodeDialog, holdDurationMs)
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(showCodeDialog)
                    true
                }
                else -> false
            }
        }
    }

    override fun onDestroy() {
        bannerAdView?.destroy()
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        loadData()
        loadLimits()
        applyBusinessKindUi()
        if (BillingManager.isPro(this)) {
            bannerAdView?.let { AdsManager.hideBanner(findViewById(R.id.ad_container), it) }
        }
    }

    /** Кнопка "Склад" видна только если в настройках выбран тип деятельности Продажи/Смешанная. */
    private fun applyBusinessKindUi() {
        val prefs = getSharedPreferences("settings", MODE_PRIVATE)
        val showsMagazin = BusinessKindHelper.get(prefs).showsMagazin
        findViewById<Button>(R.id.btn_magazin).visibility = if (showsMagazin) View.VISIBLE else View.GONE
    }

    private fun loadData() {
        CoroutineScope(Dispatchers.IO).launch {
            // Баланс/статистика/налог — только за текущий календарный год,
            // так как лимит 30 000 zł годовой (см. TaxHelper).
            val year = TaxHelper.currentYear()
            val (yearStart, yearEndExclusive) = TaxHelper.yearRange(year)
            val yearEntries = db.entryDao().getBetween(yearStart, yearEndExclusive - 1)

            val income = yearEntries.filter { it.isIncome }.sumOf { it.amount }
            val expense = yearEntries.filter { !it.isIncome }.sumOf { it.amount }
            val profit = income - expense

            val prefs = getSharedPreferences("settings", MODE_PRIVATE)
            val otherIncome = TaxHelper.getOtherIncome(prefs, year)
            val activityType = ActivityTypeHelper.get(prefs)
            val ryczaltRate = ActivityTypeHelper.getRyczaltRate(prefs)
            val taxResult = when (activityType) {
                ActivityType.NIEZAREJESTROWANA, ActivityType.JDG_SKALA -> TaxHelper.calc(profit, otherIncome)
                ActivityType.JDG_LINIOWY -> TaxHelper.calcLiniowy(profit)
                ActivityType.JDG_RYCZALT -> TaxHelper.calcRyczalt(income, ryczaltRate)
            }
            val taxLabelRes = when (activityType) {
                ActivityType.JDG_LINIOWY -> R.string.tax_label_liniowy
                ActivityType.JDG_RYCZALT -> R.string.tax_label_ryczalt
                else -> TaxHelper.taxLabelResId(profit)
            }

            withContext(Dispatchers.Main) {
                findViewById<TextView>(R.id.tv_balance).text = formatMoney(profit)
                findViewById<TextView>(R.id.tv_stat_income).text = formatMoney(income)
                findViewById<TextView>(R.id.tv_stat_expense).text = formatMoney(expense)
                findViewById<TextView>(R.id.tv_stat_profit).text = formatMoney(profit)
                // Динамическая подпись налога: "0% — необлагаемый минимум" / "12%" /
                // "Прогрессивная шкала 12%/32%" для skali, либо своя подпись для
                // liniowy/ryczałt — вместо одной фиксированной формулировки.
                findViewById<TextView>(R.id.tv_stat_tax_label).text = getString(taxLabelRes)
                findViewById<TextView>(R.id.tv_stat_tax).text = formatMoney(taxResult.tax)
                // Чистая прибыль = прибыль минус налог по выбранной форме налогообложения.
                findViewById<TextView>(R.id.tv_stat_net_profit).text = formatMoney(profit - taxResult.tax)
            }
        }
    }

    /** Обновляет три гейджа лимитов и красный баннер превышения лимита niezarejestrowanej działalności. */
    private fun loadLimits() {
        CoroutineScope(Dispatchers.IO).launch {
            val limits = LimitsHelper.compute(this@MineActivity)
            withContext(Dispatchers.Main) {
                findViewById<TextView>(R.id.tv_limit_monthly_label).text =
                    getString(
                        R.string.limit_monthly_label,
                        formatMoney(limits.monthly.current), formatMoney(limits.monthly.limit)
                    )
                findViewById<ProgressBar>(R.id.pb_limit_monthly).progress = limits.monthly.percent.coerceAtMost(100)

                findViewById<TextView>(R.id.tv_limit_bracket_label).text =
                    getString(
                        R.string.limit_bracket_label,
                        formatMoney(limits.bracket.current), formatMoney(limits.bracket.limit)
                    )
                findViewById<ProgressBar>(R.id.pb_limit_bracket).progress = limits.bracket.percent.coerceAtMost(100)

                findViewById<TextView>(R.id.tv_limit_vat_label).text =
                    getString(
                        R.string.limit_vat_label,
                        formatMoney(limits.vat.current), formatMoney(limits.vat.limit)
                    )
                findViewById<ProgressBar>(R.id.pb_limit_vat).progress = limits.vat.percent.coerceAtMost(100)

                val warning = findViewById<TextView>(R.id.tv_limit_warning)
                if (limits.activityType == ActivityType.NIEZAREJESTROWANA && limits.monthly.exceeded) {
                    warning.text = getString(R.string.limit_exceeded_warning)
                    warning.visibility = View.VISIBLE
                } else {
                    warning.visibility = View.GONE
                }
            }
        }
    }

    private fun formatMoney(v: Double): String = String.format(Locale.getDefault(), "%.2f", v)
}
EOF_U41_MINEACTIVITY_KT
echo "OK: $JAVA_DIR/MineActivity.kt"

# ---------------------------------------------------------------------------
# activity_mine.xml — кнопка "Склад" (изначально скрыта)
# ---------------------------------------------------------------------------
python3 - << 'PYEOF_U41_ACTIVITY_MINE_XML'
import re
path = "app/src/main/res/layout/activity_mine.xml"
text = open(path, encoding="utf-8").read()

anchor = '''    <Button
        android:id="@+id/btn_invoices"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:layout_marginBottom="20dp"
        android:background="@drawable/btn_pill_outline"
        android:text="@string/nav_invoices"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="16sp"/>'''

addition = '''    <Button
        android:id="@+id/btn_invoices"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:layout_marginBottom="14dp"
        android:background="@drawable/btn_pill_outline"
        android:text="@string/nav_invoices"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="16sp"/>

    <Button
        android:id="@+id/btn_magazin"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:layout_marginBottom="20dp"
        android:background="@drawable/btn_pill_outline"
        android:text="@string/nav_magazin"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="16sp"
        android:visibility="gone"/>'''

if anchor not in text:
    raise SystemExit("ANCHOR NOT FOUND in activity_mine.xml")
text = text.replace(anchor, addition, 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF_U41_ACTIVITY_MINE_XML
echo "OK: $LAYOUT_DIR/activity_mine.xml (добавлена кнопка btn_magazin)"

# ---------------------------------------------------------------------------
# AddEntryActivity.kt — кнопка "Сканировать чек" (ML Kit OCR)
# ---------------------------------------------------------------------------
cat > "$JAVA_DIR/AddEntryActivity.kt" << 'EOF_U41_ADDENTRYACTIVITY_KT'
package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.app.DatePickerDialog
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Экран добавления ИЛИ редактирования операции.
 * Если в intent передан "entryId" (id существующей записи) — режим редактирования:
 * поля предзаполняются, появляется кнопка удаления, а сохранение обновляет запись
 * вместо создания новой. Без "entryId" работает как раньше — создание новой записи.
 */
class AddEntryActivity : BaseActivity() {
    private var selectedImagePath: String? = null
    private var editingEntry: Entry? = null
    private var currentIsIncome: Boolean = true
    // Дата транзакции (Data sprzedaży / Data transakcji) — по умолчанию сегодня,
    // но пользователь может выбрать любую дату через DatePickerDialog. Это важно,
    // так как лимиты działalność nierejestrowana считаются строго по месяцам/кварталам,
    // и запись должна попадать в правильный период, а не всегда в "сейчас".
    private var selectedDateMillis: Long = System.currentTimeMillis()
    // Повтор доступен только при создании новой записи (не при редактировании
    // существующей) — иначе неясно, что должно произойти с уже созданными
    // на основе шаблона транзакциями.
    private var wantsRecurring: Boolean = false

    // Фото для распознавания чека (ML Kit OCR) — пишется в полном разрешении через
    // системную камеру (FileProvider), затем прогоняется через ReceiptOcrHelper.
    private var ocrPhotoFile: File? = null

    private val takeOcrPhoto = registerForActivityResult(ActivityResultContracts.TakePicture()) { success ->
        if (success) runOcr()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_add_entry)

        val pickImage = registerForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
            if (uri == null) return@registerForActivityResult
            try {
                val input = contentResolver.openInputStream(uri)
                if (input == null) {
                    Toast.makeText(this, "Не удалось открыть файл", Toast.LENGTH_SHORT).show()
                    return@registerForActivityResult
                }
                // Временное имя: окончательное стандартизированное имя
                // (YYYY-MM-DD_TYPE_AMOUNT_ID.jpg) присваивается при сохранении записи,
                // когда известны дата операции, сумма, тип и id (см. renameReceiptToStandardName).
                val out = File(getExternalFilesDir(null), "receipt_tmp_${System.currentTimeMillis()}.jpg")
                FileOutputStream(out).use { fos -> input.copyTo(fos) }
                input.close()
                selectedImagePath = out.absolutePath
                findViewById<Button>(R.id.btn_attach).text = getString(R.string.attach_receipt) + " ✓"
                Toast.makeText(this, "Чек добавлен", Toast.LENGTH_SHORT).show()
            } catch (e: Exception) {
                Toast.makeText(this, "Ошибка при добавлении чека: ${e.message}", Toast.LENGTH_LONG).show()
            }
        }

        val entryId = intent.getLongExtra("entryId", -1L)
        currentIsIncome = intent.getBooleanExtra("isIncome", true)

        setupTypeToggle()
        findViewById<Button>(R.id.btn_attach).setOnClickListener { pickImage.launch("image/*") }
        findViewById<Button>(R.id.btn_scan_receipt).setOnClickListener { launchReceiptScan() }
        findViewById<Button>(R.id.btn_delete).setOnClickListener { confirmDelete() }
        findViewById<Button>(R.id.btn_date).setOnClickListener { showDatePicker() }
        findViewById<android.widget.Switch>(R.id.sw_recurring).setOnCheckedChangeListener { _, checked ->
            wantsRecurring = checked
        }

        updateTypeToggleUi()
        updateTitle()
        updateDateButtonText()

        if (entryId != -1L) {
            findViewById<Button>(R.id.btn_delete).visibility = View.VISIBLE
            findViewById<View>(R.id.row_recurring).visibility = View.GONE
            CoroutineScope(Dispatchers.IO).launch {
                val entry = AppDatabase.getInstance(applicationContext).entryDao().getById(entryId)
                withContext(Dispatchers.Main) {
                    if (entry == null) {
                        Toast.makeText(this@AddEntryActivity, "Запись не найдена", Toast.LENGTH_SHORT).show()
                        finish()
                        return@withContext
                    }
                    editingEntry = entry
                    currentIsIncome = entry.isIncome
                    findViewById<EditText>(R.id.et_amount).setText(formatAmount(entry.amount))
                    findViewById<EditText>(R.id.et_comment).setText(entry.comment ?: "")
                    selectedImagePath = entry.receiptPath
                    selectedDateMillis = entry.dateMillis
                    if (entry.receiptPath != null) {
                        findViewById<Button>(R.id.btn_attach).text = getString(R.string.attach_receipt) + " ✓"
                    }
                    updateTypeToggleUi()
                    updateTitle()
                    updateDateButtonText()
                }
            }
        }

        findViewById<Button>(R.id.btn_save).setOnClickListener {
            val amt = findViewById<EditText>(R.id.et_amount).text.toString().toDoubleOrNull()
            if (amt == null || amt <= 0.0) {
                Toast.makeText(this, "Введите корректную сумму", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            val comment = findViewById<EditText>(R.id.et_comment).text.toString()
            findViewById<Button>(R.id.btn_save).isEnabled = false

            val existing = editingEntry
            CoroutineScope(Dispatchers.IO).launch {
                val dao = AppDatabase.getInstance(applicationContext).entryDao()
                val finalReceiptPath = renameReceiptToStandardName(
                    selectedImagePath, selectedDateMillis, currentIsIncome, amt, existing?.id
                )
                if (existing != null) {
                    dao.update(
                        existing.copy(
                            amount = amt,
                            isIncome = currentIsIncome,
                            comment = comment,
                            dateMillis = selectedDateMillis,
                            receiptPath = finalReceiptPath
                        )
                    )
                } else {
                    val newId = dao.insert(
                        Entry(
                            amount = amt,
                            isIncome = currentIsIncome,
                            comment = comment,
                            dateMillis = selectedDateMillis,
                            receiptPath = finalReceiptPath
                        )
                    )
                    // Имя файла чека включает id записи — при создании id известен только
                    // после insert, поэтому для новых записей переименовываем повторно.
                    val renamedAgain = renameReceiptToStandardName(
                        finalReceiptPath, selectedDateMillis, currentIsIncome, amt, newId
                    )
                    if (renamedAgain != finalReceiptPath) {
                        dao.update(
                            Entry(
                                id = newId, amount = amt, isIncome = currentIsIncome,
                                comment = comment, dateMillis = selectedDateMillis, receiptPath = renamedAgain
                            )
                        )
                    }
                    if (wantsRecurring) {
                        val cal = java.util.Calendar.getInstance().apply { timeInMillis = selectedDateMillis }
                        val dayOfMonth = cal.get(java.util.Calendar.DAY_OF_MONTH).coerceIn(1, 28)
                        cal.add(java.util.Calendar.MONTH, 1)
                        cal.set(java.util.Calendar.DAY_OF_MONTH, dayOfMonth)
                        AppDatabase.getInstance(applicationContext).recurringEntryDao().insert(
                            RecurringEntry(
                                amount = amt,
                                isIncome = currentIsIncome,
                                comment = comment,
                                dayOfMonth = dayOfMonth,
                                nextRunMillis = cal.timeInMillis
                            )
                        )
                    }
                }
                withContext(Dispatchers.Main) {
                    Toast.makeText(
                        this@AddEntryActivity,
                        getString(if (existing != null) R.string.entry_updated else R.string.saved),
                        Toast.LENGTH_SHORT
                    ).show()
                    finish()
                }
            }
        }
    }

    /** Запускает системную камеру для фото чека и сохраняет полноразмерный файл через FileProvider. */
    private fun launchReceiptScan() {
        val file = File(getExternalFilesDir(null), "ocr_tmp_${System.currentTimeMillis()}.jpg")
        ocrPhotoFile = file
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        takeOcrPhoto.launch(uri)
    }

    /** Прогоняет сделанное фото через ML Kit и подставляет распознанные сумму/дату/продавца. */
    private fun runOcr() {
        val file = ocrPhotoFile ?: return
        Toast.makeText(this, getString(R.string.receipt_scan_processing), Toast.LENGTH_SHORT).show()
        CoroutineScope(Dispatchers.IO).launch {
            val bmp = try {
                BitmapFactory.decodeFile(file.absolutePath)
            } catch (e: Exception) {
                null
            }
            if (bmp == null) {
                withContext(Dispatchers.Main) {
                    Toast.makeText(this@AddEntryActivity, getString(R.string.receipt_scan_no_text), Toast.LENGTH_SHORT).show()
                }
                return@launch
            }
            val result = try {
                ReceiptOcrHelper.recognize(bmp)
            } catch (e: Exception) {
                null
            }
            withContext(Dispatchers.Main) {
                if (result == null) {
                    Toast.makeText(this@AddEntryActivity, getString(R.string.receipt_scan_no_text), Toast.LENGTH_LONG).show()
                    return@withContext
                }
                if (result.amount != null) {
                    findViewById<EditText>(R.id.et_amount).setText(formatAmount(result.amount))
                }
                if (result.dateMillis != null) {
                    selectedDateMillis = result.dateMillis
                    updateDateButtonText()
                }
                if (!result.sellerName.isNullOrBlank()) {
                    val existingComment = findViewById<EditText>(R.id.et_comment).text.toString()
                    if (existingComment.isBlank()) {
                        findViewById<EditText>(R.id.et_comment).setText(result.sellerName)
                    }
                }
                selectedImagePath = file.absolutePath
                findViewById<Button>(R.id.btn_attach).text = getString(R.string.attach_receipt) + " ✓"
                if (result.amount == null && result.dateMillis == null) {
                    Toast.makeText(this@AddEntryActivity, getString(R.string.receipt_scan_no_text), Toast.LENGTH_LONG).show()
                } else {
                    Toast.makeText(this@AddEntryActivity, getString(R.string.receipt_scan_done), Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    private fun setupTypeToggle() {
        findViewById<Button>(R.id.btn_type_income).setOnClickListener {
            currentIsIncome = true
            updateTypeToggleUi()
            updateTitle()
        }
        findViewById<Button>(R.id.btn_type_expense).setOnClickListener {
            currentIsIncome = false
            updateTypeToggleUi()
            updateTitle()
        }
    }

    private fun updateTypeToggleUi() {
        val income = findViewById<Button>(R.id.btn_type_income)
        val expense = findViewById<Button>(R.id.btn_type_expense)
        income.setBackgroundResource(if (currentIsIncome) R.drawable.btn_pill_primary else R.drawable.btn_pill_outline)
        expense.setBackgroundResource(if (!currentIsIncome) R.drawable.btn_pill_primary else R.drawable.btn_pill_outline)
    }

    private fun updateTitle() {
        val isEditing = editingEntry != null
        val titleRes = when {
            isEditing && currentIsIncome -> R.string.edit_income_title
            isEditing && !currentIsIncome -> R.string.edit_expense_title
            currentIsIncome -> R.string.add_income
            else -> R.string.add_expense
        }
        findViewById<TextView>(R.id.tv_add_title).text = getString(titleRes)
    }

    private fun confirmDelete() {
        val entry = editingEntry ?: return
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.delete_confirm_title))
            .setMessage(getString(R.string.delete_confirm_message))
            .setPositiveButton(getString(R.string.delete_confirm_yes)) { _, _ ->
                CoroutineScope(Dispatchers.IO).launch {
                    AppDatabase.getInstance(applicationContext).entryDao().delete(entry)
                    withContext(Dispatchers.Main) {
                        Toast.makeText(this@AddEntryActivity, getString(R.string.entry_deleted), Toast.LENGTH_SHORT).show()
                        finish()
                    }
                }
            }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
    }

    /** Без лишних нулей для целых сумм (100, а не 100.0), но с сохранением копеек, если они есть. */
    private fun formatAmount(v: Double): String =
        if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()

    /** Открывает системный DatePickerDialog, предзаполненный текущей выбранной датой. */
    private fun showDatePicker() {
        val cal = Calendar.getInstance().apply { timeInMillis = selectedDateMillis }
        DatePickerDialog(
            this,
            { _, year, month, dayOfMonth ->
                val picked = Calendar.getInstance().apply {
                    set(year, month, dayOfMonth, 12, 0, 0)
                    set(Calendar.MILLISECOND, 0)
                }
                selectedDateMillis = picked.timeInMillis
                updateDateButtonText()
            },
            cal.get(Calendar.YEAR),
            cal.get(Calendar.MONTH),
            cal.get(Calendar.DAY_OF_MONTH)
        ).show()
    }

    /**
     * Переименовывает файл чека (если он есть) в стандартизированный формат
     * `YYYY-MM-DD_TYPE_AMOUNT_ID.jpg` (см. FileNaming) для удобной сортировки
     * и архивации перед подачей в налоговую. Если id ещё не известен
     * (новая запись до insert), используется 0 — сразу после insert
     * файл переименовывается ещё раз с настоящим id.
     */
    private fun renameReceiptToStandardName(
        path: String?, dateMillis: Long, isIncome: Boolean, amount: Double, entryId: Long?
    ): String? {
        if (path == null) return null
        val current = File(path)
        if (!current.exists()) return path
        val ext = current.extension.ifBlank { "jpg" }
        val newName = FileNaming.receiptFileName(dateMillis, isIncome, amount, entryId ?: 0L, ext)
        val newFile = File(current.parentFile, newName)
        if (newFile.absolutePath == current.absolutePath) return path
        return try {
            if (current.renameTo(newFile)) newFile.absolutePath else path
        } catch (e: Exception) {
            path
        }
    }

    /** Обновляет текст кнопки даты в формате dd.MM.yyyy (польский/общеевропейский формат). */
    private fun updateDateButtonText() {
        val sdf = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())
        val formatted = sdf.format(selectedDateMillis)
        findViewById<Button>(R.id.btn_date).text =
            getString(R.string.entry_date_label) + ": " + formatted
    }
}
EOF_U41_ADDENTRYACTIVITY_KT
echo "OK: $JAVA_DIR/AddEntryActivity.kt"

# ---------------------------------------------------------------------------
# activity_add_entry.xml — кнопка "Сканировать чек"
# ---------------------------------------------------------------------------
python3 - << 'PYEOF_U41_ACTIVITY_ADD_ENTRY_XML'
import re
path = "app/src/main/res/layout/activity_add_entry.xml"
text = open(path, encoding="utf-8").read()

anchor = '''    <Button
        android:id="@+id/btn_attach"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:layout_marginBottom="28dp"
        android:background="@drawable/input_field_bg"
        android:text="@string/attach_receipt"
        android:textAllCaps="false"
        android:textColor="@color/accent_cyan"
        android:textSize="15sp"
        android:gravity="start|center_vertical"
        android:paddingStart="18dp"
        android:paddingEnd="18dp"/>'''

addition = '''    <Button
        android:id="@+id/btn_attach"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:layout_marginBottom="14dp"
        android:background="@drawable/input_field_bg"
        android:text="@string/attach_receipt"
        android:textAllCaps="false"
        android:textColor="@color/accent_cyan"
        android:textSize="15sp"
        android:gravity="start|center_vertical"
        android:paddingStart="18dp"
        android:paddingEnd="18dp"/>

    <Button
        android:id="@+id/btn_scan_receipt"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:layout_marginBottom="28dp"
        android:background="@drawable/input_field_bg"
        android:text="@string/scan_receipt_button"
        android:textAllCaps="false"
        android:textColor="@color/accent_cyan"
        android:textSize="15sp"
        android:gravity="start|center_vertical"
        android:paddingStart="18dp"
        android:paddingEnd="18dp"/>'''

if anchor not in text:
    raise SystemExit("ANCHOR NOT FOUND in activity_add_entry.xml")
text = text.replace(anchor, addition, 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF_U41_ACTIVITY_ADD_ENTRY_XML
echo "OK: $LAYOUT_DIR/activity_add_entry.xml (добавлена кнопка btn_scan_receipt)"

# ---------------------------------------------------------------------------
# activity_add_invoice.xml — кнопка "Товары со склада"
# ---------------------------------------------------------------------------
python3 - << 'PYEOF_U41_ACTIVITY_ADD_INVOICE_XML'
import re
path = "app/src/main/res/layout/activity_add_invoice.xml"
text = open(path, encoding="utf-8").read()

anchor = '''        <EditText android:id="@+id/et_service_name" style="@style/InvoiceInput" android:hint="@string/service_name" android:inputType="text"/>
        <EditText android:id="@+id/et_amount" style="@style/InvoiceInput" android:hint="@string/service_amount" android:inputType="numberDecimal"/>'''

addition = '''        <EditText android:id="@+id/et_service_name" style="@style/InvoiceInput" android:hint="@string/service_name" android:inputType="text"/>
        <EditText android:id="@+id/et_amount" style="@style/InvoiceInput" android:hint="@string/service_amount" android:inputType="numberDecimal"/>

        <Button
            android:id="@+id/btn_add_warehouse_items"
            android:layout_width="match_parent"
            android:layout_height="48dp"
            android:layout_marginTop="4dp"
            android:layout_marginBottom="10dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/add_from_warehouse"
            android:textAllCaps="false"
            android:textColor="@color/accent_cyan"
            android:textSize="13sp"/>'''

if anchor not in text:
    raise SystemExit("ANCHOR NOT FOUND in activity_add_invoice.xml")
text = text.replace(anchor, addition, 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF_U41_ACTIVITY_ADD_INVOICE_XML
echo "OK: $LAYOUT_DIR/activity_add_invoice.xml (добавлена кнопка btn_add_warehouse_items)"

# ---------------------------------------------------------------------------
# AddInvoiceActivity.kt — многопозиционные накладные + автосписание со склада
# ---------------------------------------------------------------------------
cat > "$JAVA_DIR/AddInvoiceActivity.kt" << 'EOF_U41_ADDINVOICEACTIVITY_KT'
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
import androidx.activity.result.contract.ActivityResultContracts
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
 *
 * Jeśli użytkownik wybierze pozycje ze magazynu (btn_add_warehouse_items),
 * ich suma zastępuje pole kwoty, a same pozycje zapisujemy osobno w tabeli
 * invoice_items i odejmujemy ze stanu magazynowego — PDF nadal generuje się
 * jako jedna usługa/pozycja (serviceName/amount), żeby nie ruszać ryzykownej
 * logiki rysowania PDF w InvoicePdfGenerator.
 */
class AddInvoiceActivity : BaseActivity() {

    private var isPhysicalPerson: Boolean = true
    private var paymentMethod: PaymentMethod = PaymentMethod.CASH
    private var serviceDateMillis: Long = System.currentTimeMillis()
    private var paymentDateMillis: Long = System.currentTimeMillis()
    private var invoiceStatus: InvoiceStatus = InvoiceStatus.PAID
    private var dueDateMillis: Long = System.currentTimeMillis() + 14L * 24 * 60 * 60 * 1000
    private var lastSavedUri: Uri? = null
    private var warehouseItems: List<PickedProduct> = emptyList()

    private val selectProductsLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (result.resultCode == RESULT_OK) {
            val data = result.data?.getStringExtra("picked_items")
            if (!data.isNullOrBlank()) applyPickedItems(data)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_add_invoice)

        setupPaymentMethodToggle()
        findViewById<Button>(R.id.btn_service_date).setOnClickListener { showDatePicker(isServiceDate = true) }
        findViewById<Button>(R.id.btn_payment_date).setOnClickListener { showDatePicker(isServiceDate = false) }
        updateDateButtons()

        findViewById<Switch>(R.id.sw_invoice_paid).setOnCheckedChangeListener { _, checked ->
            invoiceStatus = if (checked) InvoiceStatus.PAID else InvoiceStatus.PENDING
            findViewById<Button>(R.id.btn_due_date).visibility = if (checked) View.GONE else View.VISIBLE
        }
        findViewById<Button>(R.id.btn_due_date).setOnClickListener { showDueDatePicker() }
        updateDueDateButton()

        findViewById<Switch>(R.id.sw_physical_person).setOnCheckedChangeListener { _, checked ->
            isPhysicalPerson = checked
            findViewById<EditText>(R.id.et_buyer_nip).visibility = if (checked) View.GONE else View.VISIBLE
        }

        findViewById<Button>(R.id.btn_add_warehouse_items).setOnClickListener {
            selectProductsLauncher.launch(Intent(this, SelectProductsActivity::class.java))
        }

        findViewById<Button>(R.id.btn_generate).setOnClickListener { generateInvoice() }
        findViewById<Button>(R.id.btn_open_pdf).setOnClickListener { openLastPdf() }
        findViewById<Button>(R.id.btn_share).setOnClickListener { shareLastPdf() }
        findViewById<Button>(R.id.btn_open_folder).setOnClickListener { openInvoicesFolder() }
        findViewById<Button>(R.id.btn_invoice_history).setOnClickListener {
            startActivity(Intent(this, InvoiceHistoryActivity::class.java))
        }

        loadSellerData()
        refreshCashLimit()
    }

    /** Позиции со склада выбраны: подставляем сводное название и сумму в форму. Списание
     *  остатков происходит только после успешного сохранения фактуры (см. generateInvoice). */
    private fun applyPickedItems(serialized: String) {
        warehouseItems = serialized.lines().filter { it.isNotBlank() }.mapNotNull { line ->
            val parts = line.split("|")
            if (parts.size == 4) {
                try {
                    PickedProduct(parts[0].toLong(), parts[1], parts[2].toDouble(), parts[3].toDouble())
                } catch (e: Exception) {
                    null
                }
            } else null
        }
        if (warehouseItems.isEmpty()) return
        val summary = warehouseItems.joinToString(", ") { "${it.name} x${formatQty(it.quantity)}" }
        val total = warehouseItems.sumOf { it.quantity * it.unitPrice }
        findViewById<EditText>(R.id.et_service_name).setText(summary)
        findViewById<EditText>(R.id.et_amount).setText(formatMoney(total))
    }

    private fun formatQty(v: Double): String = if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()

    private fun loadSellerData() {
        CoroutineScope(Dispatchers.IO).launch {
            val seller = InvoiceSellerDataStore.load(applicationContext)
            withContext(Dispatchers.Main) {
                findViewById<EditText>(R.id.et_seller_name).setText(seller.name)
                findViewById<EditText>(R.id.et_seller_nip).setText(seller.nip)
                findViewById<EditText>(R.id.et_seller_street).setText(seller.street)
                findViewById<EditText>(R.id.et_seller_postal).setText(seller.postalCode)
                findViewById<EditText>(R.id.et_seller_city).setText(seller.city)
                findViewById<EditText>(R.id.et_seller_bank_account).setText(seller.bankAccount)
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
        setPaymentButtonState(cash, paymentMethod == PaymentMethod.CASH)
        setPaymentButtonState(transfer, paymentMethod == PaymentMethod.TRANSFER)
        setPaymentButtonState(blik, paymentMethod == PaymentMethod.BLIK)
    }

    /** Явно выделяем выбранный способ оплаты: яркий фон + жирный белый текст против
     *  приглушённого фона и серого текста у невыбранных — чтобы было сразу видно,
     *  какой способ активен. */
    private fun setPaymentButtonState(button: Button, selected: Boolean) {
        button.setBackgroundResource(if (selected) R.drawable.btn_pill_payment_selected else R.drawable.btn_pill_payment_unselected)
        button.setTextColor(resources.getColor(if (selected) R.color.text_primary else R.color.text_secondary, theme))
        button.alpha = if (selected) 1.0f else 0.75f
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

    private fun showDueDatePicker() {
        val cal = Calendar.getInstance().apply { timeInMillis = dueDateMillis }
        DatePickerDialog(
            this,
            { _, year, month, dayOfMonth ->
                val picked = Calendar.getInstance().apply {
                    set(year, month, dayOfMonth, 12, 0, 0)
                    set(Calendar.MILLISECOND, 0)
                }
                dueDateMillis = picked.timeInMillis
                updateDueDateButton()
            },
            cal.get(Calendar.YEAR), cal.get(Calendar.MONTH), cal.get(Calendar.DAY_OF_MONTH)
        ).show()
    }

    private fun updateDueDateButton() {
        val sdf = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())
        findViewById<Button>(R.id.btn_due_date).text =
            getString(R.string.invoice_due_date_label) + ": " + sdf.format(dueDateMillis)
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
        val sellerBankAccount = findViewById<EditText>(R.id.et_seller_bank_account).text.toString().trim()

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
        val seller = InvoiceSellerData(sellerName, sellerNip, sellerStreet, sellerPostal, sellerCity, sellerBankAccount)
        val issueDateMillis = System.currentTimeMillis()
        val itemsForThisInvoice = warehouseItems

        CoroutineScope(Dispatchers.IO).launch {
            try {
                InvoiceSellerDataStore.save(applicationContext, seller)
                val dao = AppDatabase.getInstance(applicationContext).invoiceDao()
                val invoiceNumber = (dao.getMaxInvoiceNumber() ?: 0) + 1
                val fileName = FileNaming.invoiceFileName(invoiceNumber, issueDateMillis)

                val saved = InvoiceFileStorage.savePdf(applicationContext, fileName) { out ->
                    InvoicePdfGenerator.generate(
                        context = this@AddInvoiceActivity,
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
                        invoiceStatus = invoiceStatus,
                        dueDateMillis = if (invoiceStatus == InvoiceStatus.PENDING) dueDateMillis else null,
                        out = out
                    )
                }

                val invoiceId = dao.insert(
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
                        pdfFileName = fileName,
                        status = invoiceStatus,
                        dueDateMillis = if (invoiceStatus == InvoiceStatus.PENDING) dueDateMillis else null
                    )
                )

                // Многопозиционная разбивка + автосписание со склада (только если
                // пользователь выбирал позиции через "Товары со склада").
                if (itemsForThisInvoice.isNotEmpty()) {
                    val items = itemsForThisInvoice.map {
                        InvoiceItem(invoiceId = invoiceId, productId = it.productId, name = it.name, quantity = it.quantity, unitPrice = it.unitPrice)
                    }
                    AppDatabase.getInstance(applicationContext).invoiceItemDao().insertAll(items)
                    val productDao = AppDatabase.getInstance(applicationContext).productDao()
                    for (item in itemsForThisInvoice) {
                        productDao.decrementQuantity(item.productId, item.quantity)
                    }
                }

                withContext(Dispatchers.Main) {
                    lastSavedUri = saved.uri
                    warehouseItems = emptyList()
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
EOF_U41_ADDINVOICEACTIVITY_KT
echo "OK: $JAVA_DIR/AddInvoiceActivity.kt"

echo ""
echo "--- Обновляю app/build.gradle (ML Kit + ZXing) ---"
python3 - << 'PYEOF_U41_BUILD_GRADLE'
path = "app/build.gradle"
text = open(path, encoding="utf-8").read()
anchor = '    implementation "com.tom-roush:pdfbox-android:2.0.27.0"\n}'
if anchor not in text:
    raise SystemExit("ANCHOR NOT FOUND in app/build.gradle")
addition = (
    '    implementation "com.tom-roush:pdfbox-android:2.0.27.0"\n'
    '\n'
    '    // Update 41: OCR чеков (ML Kit, работает на устройстве, без интернета)\n'
    '    implementation "com.google.mlkit:text-recognition:16.0.0"\n'
    '    implementation "com.google.mlkit:text-recognition-cyrillic:16.0.0"\n'
    '\n'
    '    // Update 41: сканирование штрихкодов для склада (ZXing, без OpenCV)\n'
    '    implementation "com.journeyapps:zxing-android-embedded:4.3.0"\n'
    '}'
)
text = text.replace(anchor, addition, 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF_U41_BUILD_GRADLE
echo "OK: app/build.gradle"

echo ""
echo "--- Обновляю AndroidManifest.xml (CAMERA + новые Activity) ---"
python3 - << 'PYEOF_U41_MANIFEST'
path = "app/src/main/AndroidManifest.xml"
text = open(path, encoding="utf-8").read()

perm_anchor = '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />'
if perm_anchor not in text:
    raise SystemExit("PERMISSION ANCHOR NOT FOUND in AndroidManifest.xml")
perm_addition = (
    perm_anchor + '\n'
    '    <uses-permission android:name="android.permission.CAMERA" />\n'
    '    <uses-feature android:name="android.hardware.camera" android:required="false" />'
)
text = text.replace(perm_anchor, perm_addition, 1)

activity_anchor = '        <activity android:name=".MineActivity" android:exported="true">'
if activity_anchor not in text:
    raise SystemExit("ACTIVITY ANCHOR NOT FOUND in AndroidManifest.xml")
activity_addition = (
    '        <activity android:name=".SettingsBusinessActivity" android:exported="false" />\n'
    '        <activity android:name=".MagazinActivity" android:exported="false" />\n'
    '        <activity android:name=".AddEditProductActivity" android:exported="false" />\n'
    '        <activity android:name=".SelectProductsActivity" android:exported="false" />\n'
    + activity_anchor
)
text = text.replace(activity_anchor, activity_addition, 1)

open(path, "w", encoding="utf-8").write(text)
PYEOF_U41_MANIFEST
echo "OK: app/src/main/AndroidManifest.xml"

echo ""
echo "--- Добавляю строки в values/strings.xml, values-ru/strings.xml, values-pl/strings.xml ---"

python3 - << 'PYEOF_U41_STRINGS_BASE'
path = "app/src/main/res/values/strings.xml"
text = open(path, encoding="utf-8").read()
addition = '''
    <!-- Update 41: business kind, magazin, barcode, receipt OCR -->
    <string name="settings_menu_business">Business type</string>
    <string name="business_kind_title">Business type</string>
    <string name="business_kind_description">Choose what best matches your activity. Selecting Sales or Mixed adds a Warehouse (Magazyn) button on the main screen for tracking stock.</string>
    <string name="business_kind_sales">Sales</string>
    <string name="business_kind_services">Services</string>
    <string name="business_kind_mixed">Mixed (sales and services)</string>
    <string name="nav_magazin">Warehouse</string>
    <string name="magazin_title">Warehouse</string>
    <string name="magazin_empty">No products yet. Add one manually or scan a barcode.</string>
    <string name="add_product_manually">Add manually</string>
    <string name="scan_barcode">Scan barcode</string>
    <string name="scan_short">Scan</string>
    <string name="scan_barcode_prompt">Point the camera at the barcode</string>
    <string name="looking_up_product">Looking up product…</string>
    <string name="product_name">Product name</string>
    <string name="product_barcode">Barcode (optional)</string>
    <string name="product_quantity">Quantity in stock</string>
    <string name="product_unit">Unit (e.g. pcs, kg)</string>
    <string name="product_low_stock">Low stock threshold</string>
    <string name="product_price">Unit price</string>
    <string name="product_saved">Product saved</string>
    <string name="low_stock_banner">%1$d product(s) running low</string>
    <string name="notif_low_stock_title">Stock running low</string>
    <string name="notif_low_stock_text">%1$s: only %2$s %3$s left</string>
    <string name="add_from_warehouse">Add items from warehouse</string>
    <string name="select_products_title">Select products</string>
    <string name="in_stock_suffix">in stock</string>
    <string name="select_at_least_one_product">Select at least one product</string>
    <string name="scan_receipt_button">Scan receipt (auto-fill)</string>
    <string name="receipt_scan_processing">Recognizing receipt…</string>
    <string name="receipt_scan_done">Receipt recognized, please check the fields</string>
    <string name="receipt_scan_no_text">Could not read the receipt, please enter manually</string>
</resources>'''
if not text.rstrip().endswith("</resources>"):
    raise SystemExit("Unexpected end of values/strings.xml")
text = text.rstrip()[:-len("</resources>")] + addition + "\n"
open(path, "w", encoding="utf-8").write(text)
PYEOF_U41_STRINGS_BASE
echo "OK: app/src/main/res/values/strings.xml"

python3 - << 'PYEOF_U41_STRINGS_RU'
path = "app/src/main/res/values-ru/strings.xml"
text = open(path, encoding="utf-8").read()
addition = '''
    <!-- Update 41: тип деятельности, склад, штрихкоды, OCR чеков -->
    <string name="settings_menu_business">Тип деятельности</string>
    <string name="business_kind_title">Тип деятельности</string>
    <string name="business_kind_description">Выберите, что больше подходит вашему бизнесу. При выборе \\"Продажи\\" или \\"Смешанная\\" на главном экране появится кнопка \\"Склад\\" для учёта товаров.</string>
    <string name="business_kind_sales">Продажи</string>
    <string name="business_kind_services">Услуги</string>
    <string name="business_kind_mixed">Смешанная (продажи и услуги)</string>
    <string name="nav_magazin">Склад</string>
    <string name="magazin_title">Склад</string>
    <string name="magazin_empty">Пока нет товаров. Добавьте вручную или отсканируйте штрихкод.</string>
    <string name="add_product_manually">Добавить вручную</string>
    <string name="scan_barcode">Сканировать штрихкод</string>
    <string name="scan_short">Скан</string>
    <string name="scan_barcode_prompt">Наведите камеру на штрихкод</string>
    <string name="looking_up_product">Ищу товар в базе…</string>
    <string name="product_name">Название товара</string>
    <string name="product_barcode">Штрихкод (необязательно)</string>
    <string name="product_quantity">Количество на складе</string>
    <string name="product_unit">Единица (шт., кг и т.п.)</string>
    <string name="product_low_stock">Порог \\"заканчивается\\"</string>
    <string name="product_price">Цена за единицу</string>
    <string name="product_saved">Товар сохранён</string>
    <string name="low_stock_banner">Заканчивается: %1$d товар(ов)</string>
    <string name="notif_low_stock_title">Товар заканчивается</string>
    <string name="notif_low_stock_text">%1$s: осталось %2$s %3$s</string>
    <string name="add_from_warehouse">Добавить товары со склада</string>
    <string name="select_products_title">Выбор товаров</string>
    <string name="in_stock_suffix">в наличии</string>
    <string name="select_at_least_one_product">Выберите хотя бы один товар</string>
    <string name="scan_receipt_button">Сканировать чек (автозаполнение)</string>
    <string name="receipt_scan_processing">Распознаю чек…</string>
    <string name="receipt_scan_done">Чек распознан, проверьте поля</string>
    <string name="receipt_scan_no_text">Не удалось распознать чек, заполните вручную</string>
</resources>'''
if not text.rstrip().endswith("</resources>"):
    raise SystemExit("Unexpected end of values-ru/strings.xml")
text = text.rstrip()[:-len("</resources>")] + addition + "\n"
open(path, "w", encoding="utf-8").write(text)
PYEOF_U41_STRINGS_RU
echo "OK: app/src/main/res/values-ru/strings.xml"

python3 - << 'PYEOF_U41_STRINGS_PL'
path = "app/src/main/res/values-pl/strings.xml"
text = open(path, encoding="utf-8").read()
addition = '''
    <!-- Update 41: rodzaj działalności, magazyn, kody kreskowe, OCR paragonów -->
    <string name="settings_menu_business">Rodzaj działalności</string>
    <string name="business_kind_title">Rodzaj działalności</string>
    <string name="business_kind_description">Wybierz to, co najlepiej pasuje do Twojej działalności. Przy wyborze \\"Sprzedaż\\" lub \\"Mieszana\\" na ekranie głównym pojawi się przycisk \\"Magazyn\\".</string>
    <string name="business_kind_sales">Sprzedaż</string>
    <string name="business_kind_services">Usługi</string>
    <string name="business_kind_mixed">Mieszana (sprzedaż i usługi)</string>
    <string name="nav_magazin">Magazyn</string>
    <string name="magazin_title">Magazyn</string>
    <string name="magazin_empty">Brak produktów. Dodaj ręcznie lub zeskanuj kod kreskowy.</string>
    <string name="add_product_manually">Dodaj ręcznie</string>
    <string name="scan_barcode">Skanuj kod kreskowy</string>
    <string name="scan_short">Skanuj</string>
    <string name="scan_barcode_prompt">Skieruj aparat na kod kreskowy</string>
    <string name="looking_up_product">Szukam produktu w bazie…</string>
    <string name="product_name">Nazwa produktu</string>
    <string name="product_barcode">Kod kreskowy (opcjonalnie)</string>
    <string name="product_quantity">Ilość w magazynie</string>
    <string name="product_unit">Jednostka (szt., kg itp.)</string>
    <string name="product_low_stock">Próg \\"kończy się\\"</string>
    <string name="product_price">Cena jednostkowa</string>
    <string name="product_saved">Produkt zapisany</string>
    <string name="low_stock_banner">Kończy się: %1$d produkt(ów)</string>
    <string name="notif_low_stock_title">Produkt się kończy</string>
    <string name="notif_low_stock_text">%1$s: zostało %2$s %3$s</string>
    <string name="add_from_warehouse">Dodaj towary z magazynu</string>
    <string name="select_products_title">Wybór produktów</string>
    <string name="in_stock_suffix">w magazynie</string>
    <string name="select_at_least_one_product">Wybierz co najmniej jeden produkt</string>
    <string name="scan_receipt_button">Skanuj paragon (autouzupełnianie)</string>
    <string name="receipt_scan_processing">Rozpoznaję paragon…</string>
    <string name="receipt_scan_done">Paragon rozpoznany, sprawdź pola</string>
    <string name="receipt_scan_no_text">Nie udało się odczytać paragonu, wpisz ręcznie</string>
</resources>'''
if not text.rstrip().endswith("</resources>"):
    raise SystemExit("Unexpected end of values-pl/strings.xml")
text = text.rstrip()[:-len("</resources>")] + addition + "\n"
open(path, "w", encoding="utf-8").write(text)
PYEOF_U41_STRINGS_PL
echo "OK: app/src/main/res/values-pl/strings.xml"

echo ""
echo "=== Готово. Дальше вручную: ==="
echo "1) git add -A && git commit -m 'Update 41: OCR receipts, warehouse with barcode scan, multi-item invoices' && git push"
echo "2) Дождись сборки в GitHub Actions"
echo "3) Проверь по очереди:"
echo "   - Настройки -> Тип деятельности -> выбери 'Продажи' или 'Смешанная'"
echo "   - На главном экране должна появиться кнопка 'Склад'"
echo "   - Склад -> Сканировать штрихкод (первый запуск спросит разрешение камеры)"
echo "   - Склад -> Добавить вручную — сохрани тестовый товар"
echo "   - Fakturа -> Добавить товары со склада -> выбери товар и количество -> Сгенерировать"
echo "   - Добавить расход -> Сканировать чек — сфотографируй любой чек, проверь автозаполнение"
echo ""
echo "ВАЖНО: база данных обновлена до версии 4 ЧЕРЕЗ МИГРАЦИЮ — старые доходы/расходы/фактуры не удаляются."
echo "Бэкап изменённых файлов лежит в: $BACKUP_DIR — можно удалить после проверки."
