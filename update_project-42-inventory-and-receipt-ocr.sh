#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=== Обновление 42: инвентаризация склада + починка сканера чеков ==="
echo "Что меняется:"
echo " - Magazin: новая кнопка \"Zrób inwentaryzację\" -> экран, где можно проверить"
echo "   фактическое количество каждого товара; остатки обновляются, расхождения"
echo "   сохраняются в историю (таблица inventory_records, миграция БД v4 -> v5)"
echo " - Skanuj paragon: точнее определяется итоговая сумма чека (приоритет"
echo "   \"do zapłaty\"/\"suma\" над числами из середины чека) и теперь распознаются"
echo "   отдельные позиции покупки (товар + цена) — они автоматически подставляются"
echo "   в комментарий списком, а не как раньше — одна нечитаемая строка продавца"
echo ""

if [ ! -f "settings.gradle" ] || [ ! -d "app/src/main/java/com/example/fa_ksiegowy" ]; then
    echo "!!! Запусти скрипт из корня проекта FA_ksiegowy-main (там, где settings.gradle)"
    exit 1
fi

if [ ! -f "app/src/main/java/com/example/fa_ksiegowy/MagazinActivity.kt" ]; then
    echo "!!! Не найден MagazinActivity.kt — запусти скрипт из корня проекта"
    exit 1
fi

BACKUP_DIR=".update42_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
for f in \
    "app/src/main/java/com/example/fa_ksiegowy/AppDatabase.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/InventoryRecord.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/InventoryRecordDao.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/InventoryActivity.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/MagazinActivity.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/ReceiptOcrHelper.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/AddEntryActivity.kt" \
    "app/src/main/res/layout/activity_magazin.xml" \
    "app/src/main/res/layout/activity_inventory.xml" \
    "app/src/main/res/layout/item_inventory.xml" \
    "app/src/main/res/values/strings.xml" \
    "app/src/main/res/values-ru/strings.xml" \
    "app/src/main/res/values-pl/strings.xml" \
    "app/src/main/AndroidManifest.xml"
do
    if [ -f "$f" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$f")"
        cp "$f" "$BACKUP_DIR/$f"
    fi
done
echo "--- Бэкап изменяемых файлов сохранён в $BACKUP_DIR ---"

echo ""
echo "--- Записываю новые и обновлённые файлы ---"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/AppDatabase.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/AppDatabase.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_APPDATABASE_KT'
package com.example.fa_ksiegowy

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [Entry::class, Invoice::class, RecurringEntry::class, Product::class, InvoiceItem::class, InventoryRecord::class],
    version = 5,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun entryDao(): EntryDao

    abstract fun invoiceDao(): InvoiceDao

    abstract fun recurringEntryDao(): RecurringEntryDao

    abstract fun productDao(): ProductDao

    abstract fun invoiceItemDao(): InvoiceItemDao

    abstract fun inventoryRecordDao(): InventoryRecordDao

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

        /** v4 -> v5: добавлена таблица истории инвентаризации склада. Обычная
         *  миграция (не destructive), чтобы у существующих пользователей не
         *  пропали товары и остальные данные. */
        private val MIGRATION_4_5 = object : Migration(4, 5) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    "CREATE TABLE IF NOT EXISTS `inventory_records` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `productId` INTEGER NOT NULL, `productName` TEXT NOT NULL, `unit` TEXT NOT NULL, `quantityBefore` REAL NOT NULL, `quantityCounted` REAL NOT NULL, `dateMillis` INTEGER NOT NULL)"
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
                ).addMigrations(MIGRATION_3_4, MIGRATION_4_5).fallbackToDestructiveMigration().build().also { INSTANCE = it }
            }
        }
    }
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_APPDATABASE_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/AppDatabase.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/InventoryRecord.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/InventoryRecord.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVENTORYRECORD_KT'
package com.example.fa_ksiegowy

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Запись о результате инвентаризации одного товара: сколько было по учёту и
 * сколько насчитал пользователь при физической проверке склада. Хранится даже
 * если разница равна нулю (подтверждение, что товар проверялся) — так по
 * dateMillis можно увидеть, когда в последний раз делалась инвентаризация.
 */
@Entity(tableName = "inventory_records")
data class InventoryRecord(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val productId: Long,
    val productName: String,
    val unit: String,
    val quantityBefore: Double,
    val quantityCounted: Double,
    val dateMillis: Long = System.currentTimeMillis()
) {
    val diff: Double get() = quantityCounted - quantityBefore
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVENTORYRECORD_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/InventoryRecord.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/InventoryRecordDao.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/InventoryRecordDao.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVENTORYRECORDDAO_KT'
package com.example.fa_ksiegowy

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query

@Dao
interface InventoryRecordDao {
    @Insert
    suspend fun insert(record: InventoryRecord): Long

    @Query("SELECT * FROM inventory_records ORDER BY dateMillis DESC")
    suspend fun getAll(): List<InventoryRecord>

    @Query("SELECT * FROM inventory_records WHERE productId = :productId ORDER BY dateMillis DESC")
    suspend fun getForProduct(productId: Long): List<InventoryRecord>
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVENTORYRECORDDAO_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/InventoryRecordDao.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/InventoryActivity.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/InventoryActivity.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVENTORYACTIVITY_KT'
package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Инвентаризация склада: пользователь может в любой момент открыть этот экран,
 * пройтись по товарам и вписать фактически посчитанное количество. При
 * сохранении остаток на складе обновляется до введённого значения, а по каждой
 * позиции с расхождением создаётся запись в истории инвентаризации
 * (InventoryRecord) — так видно, что и когда корректировалось.
 */
class InventoryActivity : BaseActivity() {
    private var products: List<Product> = emptyList()
    // productId -> введённое пользователем фактическое количество. Заполняется
    // текущим остатком при отрисовке строки, дальше обновляется по мере ввода.
    private val counted = mutableMapOf<Long, Double>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_inventory)
        findViewById<Button>(R.id.btn_save_inventory).setOnClickListener { saveInventory() }
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
        val container = findViewById<LinearLayout>(R.id.ll_inventory_container)
        container.removeAllViews()
        counted.clear()
        if (products.isEmpty()) {
            val empty = TextView(this)
            empty.text = getString(R.string.magazin_empty)
            empty.setTextColor(resources.getColor(R.color.text_secondary, theme))
            container.addView(empty)
            findViewById<Button>(R.id.btn_save_inventory).isEnabled = false
            return
        }
        val inflater = LayoutInflater.from(this)
        for (p in products) {
            val row = inflater.inflate(R.layout.item_inventory, container, false)
            row.findViewById<TextView>(R.id.tv_inv_name).text = p.name
            row.findViewById<TextView>(R.id.tv_inv_current).text =
                getString(R.string.inventory_current_stock, formatQty(p.quantity), p.unit)
            val etCounted = row.findViewById<EditText>(R.id.et_inv_counted)
            etCounted.setText(formatQty(p.quantity))
            counted[p.id] = p.quantity
            etCounted.addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
                override fun afterTextChanged(s: Editable?) {
                    counted[p.id] = s.toString().toDoubleOrNull() ?: p.quantity
                }
            })
            container.addView(row)
        }
    }

    /** Применяет посчитанные количества: обновляет остатки и пишет историю расхождений. */
    private fun saveInventory() {
        findViewById<Button>(R.id.btn_save_inventory).isEnabled = false
        val snapshot = products.map { it to (counted[it.id] ?: it.quantity) }
        CoroutineScope(Dispatchers.IO).launch {
            val db = AppDatabase.getInstance(applicationContext)
            val changed = mutableListOf<InventoryRecord>()
            val now = System.currentTimeMillis()
            for ((product, newQty) in snapshot) {
                if (newQty == product.quantity) continue
                db.productDao().update(product.copy(quantity = newQty, updatedAtMillis = now))
                val record = InventoryRecord(
                    productId = product.id,
                    productName = product.name,
                    unit = product.unit,
                    quantityBefore = product.quantity,
                    quantityCounted = newQty,
                    dateMillis = now
                )
                db.inventoryRecordDao().insert(record)
                changed.add(record)
            }
            withContext(Dispatchers.Main) {
                findViewById<Button>(R.id.btn_save_inventory).isEnabled = true
                showSummary(changed)
            }
        }
    }

    private fun showSummary(changed: List<InventoryRecord>) {
        if (changed.isEmpty()) {
            Toast.makeText(this, getString(R.string.inventory_no_changes), Toast.LENGTH_SHORT).show()
            finish()
            return
        }
        val message = changed.joinToString("\n") { r ->
            val sign = if (r.diff > 0) "+" else ""
            getString(
                R.string.inventory_diff_line,
                r.productName,
                formatQty(r.quantityBefore),
                formatQty(r.quantityCounted),
                "$sign${formatQty(r.diff)}"
            )
        }
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.inventory_saved_title))
            .setMessage(message)
            .setPositiveButton(android.R.string.ok) { _, _ -> finish() }
            .setCancelable(false)
            .show()
    }

    /** Без лишних ".0" для целых количеств (5 szt., а не 5,0 szt.). */
    private fun formatQty(v: Double): String = if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVENTORYACTIVITY_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/InventoryActivity.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/MagazinActivity.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/MagazinActivity.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_MAGAZINACTIVITY_KT'
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
        findViewById<Button>(R.id.btn_inventory).setOnClickListener {
            startActivity(Intent(this, InventoryActivity::class.java))
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
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_MAGAZINACTIVITY_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/MagazinActivity.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/ReceiptOcrHelper.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/ReceiptOcrHelper.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_RECEIPTOCRHELPER_KT'
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
        "FISKALNY", "FISKALNA", "NUMER", "ID:", "REGON",
        "ЧЕК", "КАССА", "КАССИР", "НОМЕР", "ИНН", "ТЕЛ"
    )
    private val DATE_LIKE: Pattern = Pattern.compile("\\d{1,4}[./-]\\d{1,2}[./-]\\d{1,4}")
    private val MOSTLY_DIGITS: Pattern = Pattern.compile("^[\\s0-9:\\-./#]+$")

    /** Ищет наиболее похожую на название продавца строку чека: пропускает номера
     *  документа/NIP/телефона/даты и строки, где цифр больше, чем букв. */
    private fun extractSeller(text: String): String? {
        for (rawLine in text.lines()) {
            val line = rawLine.trim()
            if (line.length !in 3..40) continue
            val upper = line.uppercase(Locale.ROOT)
            if (SELLER_SKIP_KEYWORDS.any { upper.contains(it) }) continue
            if (STRONG_TOTAL_KEYWORDS.any { upper.contains(it) } || WEAK_TOTAL_KEYWORDS.any { upper.contains(it) }) continue
            if (MOSTLY_DIGITS.matcher(line).matches()) continue
            if (DATE_LIKE.matcher(line).find()) continue
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
        "PODPIS", "ADRES", "UL.", "MIASTO", "%",
        "НАЛИЧНЫМИ", "БЕЗНАЛИЧНЫМИ", "КАРТОЙ", "СДАЧА", "ПРОДАВЕЦ", "СПАСИБО", "НАЛОГ"
    )

    // Строка вида "название товара ... цена" — цена (формат 0,00) в конце строки,
    // опционально с валютой (zł/PLN) и/или буквой ставки НДС сразу после. Так
    // распознаются позиции типичного польского фискального чека, например
    // "Chleb pszenny            4,50 B" или "Mleko 2% 1L x2       6,98".
    private val itemLinePattern: Pattern =
        Pattern.compile("^(.{2,45}?)\\s+(\\d{1,4}[.,]\\d{2})\\s*(?:zl|zł|PLN|pln)?\\s*[A-Za-z]?\\*?$", Pattern.CASE_INSENSITIVE)
    private val LEADING_QTY: Pattern = Pattern.compile("^\\d+[.,]?\\d*\\s*(x|X|szt\\.?|×)\\s*")

    /**
     * Построчно вытаскивает позиции покупки (название + цена) — то, что раньше
     * приходилось переписывать в комментарий вручную. Работает по эвристике
     * "текст, затем число вида 0,00 в конце строки"; строки-итоги/налоги/реквизиты
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
            val m = itemLinePattern.matcher(line)
            if (!m.matches()) continue
            val price = normalizeNumber(m.group(2)) ?: continue
            var name = m.group(1).trim().trimEnd('*', '-', ':', '.', ' ')
            name = name.replace(LEADING_QTY, "").trim()
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
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_RECEIPTOCRHELPER_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/ReceiptOcrHelper.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/AddEntryActivity.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/AddEntryActivity.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_ADDENTRYACTIVITY_KT'
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
                // Комментарий заполняем позициями покупки с чека (название + цена
                // каждого товара/услуги), а не просто именем продавца — это то, ради
                // чего вообще нужно сканирование, чтобы не вводить список вручную.
                // Не трогаем поле, если пользователь уже что-то в него вписал.
                if (result.items.isNotEmpty() || !result.sellerName.isNullOrBlank()) {
                    val commentField = findViewById<EditText>(R.id.et_comment)
                    if (commentField.text.toString().isBlank()) {
                        commentField.setText(buildReceiptComment(result))
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
        // Явное выделение выбранного варианта — тот же приём, что и для способа оплаты
        // на экране фактуры: яркий фон + белый текст против приглушённого фона и
        // серого текста у невыбранного варианта.
        income.setBackgroundResource(if (currentIsIncome) R.drawable.btn_pill_payment_selected else R.drawable.btn_pill_payment_unselected)
        expense.setBackgroundResource(if (!currentIsIncome) R.drawable.btn_pill_payment_selected else R.drawable.btn_pill_payment_unselected)
        income.setTextColor(resources.getColor(if (currentIsIncome) R.color.text_primary else R.color.text_secondary, theme))
        expense.setTextColor(resources.getColor(if (!currentIsIncome) R.color.text_primary else R.color.text_secondary, theme))
        income.alpha = if (currentIsIncome) 1.0f else 0.75f
        expense.alpha = if (!currentIsIncome) 1.0f else 0.75f
        // Прикладывать/сканировать чек имеет смысл только для расходов (чек подтверждает трату) —
        // для приходов эти кнопки только путают.
        findViewById<Button>(R.id.btn_attach).visibility = if (currentIsIncome) View.GONE else View.VISIBLE
        findViewById<Button>(R.id.btn_scan_receipt).visibility = if (currentIsIncome) View.GONE else View.VISIBLE
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

    /**
     * Собирает текст комментария из результата распознавания чека: название
     * продавца (если распозналось) и построчный список купленных позиций с
     * ценами — вместо того, чтобы заставлять пользователя переписывать чек
     * руками. Если позиции распознать не удалось, остаётся хотя бы продавец.
     */
    private fun buildReceiptComment(result: ReceiptOcrResult): String {
        val builder = StringBuilder()
        if (!result.sellerName.isNullOrBlank()) {
            builder.append(result.sellerName.trim())
        }
        if (result.items.isNotEmpty()) {
            if (builder.isNotEmpty()) builder.append("\n")
            for (item in result.items) {
                builder.append("• ").append(item.name)
                if (item.price != null) {
                    builder.append(" — ").append(formatAmount(item.price)).append(" zł")
                }
                builder.append("\n")
            }
        }
        return builder.toString().trim()
    }

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
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_ADDENTRYACTIVITY_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/AddEntryActivity.kt"

mkdir -p "$(dirname "app/src/main/res/layout/activity_magazin.xml")"
cat > app/src/main/res/layout/activity_magazin.xml << 'EOF_APP_SRC_MAIN_RES_LAYOUT_ACTIVITY_MAGAZIN_XML'
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

    <Button
        android:id="@+id/btn_inventory"
        android:layout_width="match_parent"
        android:layout_height="48dp"
        android:layout_marginBottom="16dp"
        android:background="@drawable/btn_pill_outline"
        android:text="@string/start_inventory"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="13sp"/>

    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/rv_products"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"/>

</LinearLayout>
EOF_APP_SRC_MAIN_RES_LAYOUT_ACTIVITY_MAGAZIN_XML
echo "OK: app/src/main/res/layout/activity_magazin.xml"

mkdir -p "$(dirname "app/src/main/res/layout/activity_inventory.xml")"
cat > app/src/main/res/layout/activity_inventory.xml << 'EOF_APP_SRC_MAIN_RES_LAYOUT_ACTIVITY_INVENTORY_XML'
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
        android:text="@string/inventory_title"
        android:textColor="@color/accent_cyan"
        android:textSize="22sp"
        android:textStyle="bold"
        android:layout_marginBottom="6dp"/>

    <TextView
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="@string/inventory_hint"
        android:textColor="@color/text_secondary"
        android:textSize="13sp"
        android:layout_marginBottom="16dp"/>

    <LinearLayout
        android:id="@+id/ll_inventory_container"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:layout_marginBottom="16dp"/>

    <Button
        android:id="@+id/btn_save_inventory"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:background="@drawable/btn_pill_primary"
        android:text="@string/inventory_save"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="17sp"
        android:textStyle="bold"/>

</LinearLayout>
</ScrollView>
EOF_APP_SRC_MAIN_RES_LAYOUT_ACTIVITY_INVENTORY_XML
echo "OK: app/src/main/res/layout/activity_inventory.xml"

mkdir -p "$(dirname "app/src/main/res/layout/item_inventory.xml")"
cat > app/src/main/res/layout/item_inventory.xml << 'EOF_APP_SRC_MAIN_RES_LAYOUT_ITEM_INVENTORY_XML'
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
            android:id="@+id/tv_inv_name"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:textColor="@color/text_primary"
            android:textSize="15sp"
            android:textStyle="bold"/>

        <TextView
            android:id="@+id/tv_inv_current"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:textColor="@color/text_secondary"
            android:textSize="12sp"
            android:layout_marginTop="2dp"/>

    </LinearLayout>

    <EditText
        android:id="@+id/et_inv_counted"
        android:layout_width="76dp"
        android:layout_height="wrap_content"
        android:layout_marginStart="10dp"
        android:background="@drawable/input_field_bg"
        android:textColor="@color/text_primary"
        android:gravity="center"
        android:padding="8dp"
        android:inputType="numberDecimal"/>

</LinearLayout>
EOF_APP_SRC_MAIN_RES_LAYOUT_ITEM_INVENTORY_XML
echo "OK: app/src/main/res/layout/item_inventory.xml"

mkdir -p "$(dirname "app/src/main/res/values/strings.xml")"
cat > app/src/main/res/values/strings.xml << 'EOF_APP_SRC_MAIN_RES_VALUES_STRINGS_XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">FinArs</string>
    <string name="app_subtitle">FinArs</string>
    <string name="add_income">Add income</string>
    <string name="add_expense">Add expense</string>
    <string name="add_entry">Add +</string>
    <string name="balance">Balance</string>
    <string name="enter_amount">Amount</string>
    <string name="enter_comment">Comment</string>
    <string name="entry_date_label">Transaction date</string>
    <string name="attach_receipt">Attach receipt</string>
    <string name="save">Save</string>
    <string name="settings">Settings</string>
    <string name="tax_percent">Tax percent</string>
    <string name="other_income_label">Other income (%1$d)</string>
    <string name="tax_scale_title">Tax is calculated automatically</string>
    <string name="tax_scale_description" formatted="false">0% up to 30,000 zł/year · 12% on the part between 30,000 and 120,000 zł · 32% on the part above 120,000 zł. The rate applies only to the amount above each threshold, not to the whole sum.</string>
    <string name="other_income_title">Other income</string>
    <string name="other_income_hint">Your total taxable income this year from other sources (job, other business, etc.). Used together with income from this app to check the 30,000 zł annual tax-free limit.</string>
    <string name="saved">Saved</string>
    <string name="auto_tax_button">Calculate automatically</string>
    <string name="auto_tax_result" formatted="false">Suggested rate: %1$.1f% (based on Polish PIT scale: 12% up to 120,000 zł/year, 32% above). You can edit it before saving.</string>
    <string name="export_report">Export report</string>
    <string name="generate_report">Generate report</string>
    <string name="select_period">Select period</string>
    <string name="month">Month</string>
    <string name="year">Year</string>
    <string name="custom_range">Custom range</string>
    <string name="from">From</string>
    <string name="to">To</string>
    <string name="no_entries">No entries</string>
    <string name="search_no_results">Nothing found</string>
    <string name="history_search_hint">Search by comment or amount</string>
    <string name="invoice_search_hint">Search by number, client or amount</string>
    <string name="filter_date_range">Date range</string>
    <string name="filter_clear">Clear filters</string>

    <string name="statistics">Statistics</string>
    <string name="stat_income">Income</string>
    <string name="stat_expense">Expense</string>
    <string name="stat_profit">Profit (gross)</string>
    <string name="stat_tax_format" formatted="false">Tax (%1$.1f%)</string>

    <string name="report_col_date">Date</string>
    <string name="report_col_income">Income</string>
    <string name="report_col_expense">Expense</string>
    <string name="report_col_tax_percent" formatted="false">Tax %</string>
    <string name="report_col_tax_amount">Tax amount</string>
    <string name="report_col_comment">Comment</string>
    <string name="report_sheet_name">Report</string>
    <string name="report_title_month">Report — Month</string>
    <string name="report_title_year">Report — Year</string>
    <string name="report_title_custom">Report — Custom period</string>
    <string name="custom_range_invalid">The end date must be after the start date</string>
    <string name="report_total_income">Total income</string>
    <string name="report_total_expense">Total expense</string>
    <string name="report_total_profit">Total profit</string>
    <string name="report_total_tax">Total tax</string>
    <string name="report_total_net_profit">Net profit (after tax)</string>
    <string name="report_generating">Generating report…</string>
    <string name="report_ready">Report ready</string>
    <string name="report_share_title">Share report</string>
    <string name="report_error">Failed to generate report: %1$s</string>
    <string name="about_app">About the app</string>
    <string name="about_description">FinArs is a comprehensive app for managing the finances of unregistered business activity and sole proprietorships (JDG). Track income and expenses, monitor limits, automatically calculate taxes, issue invoices, and generate ready-made reports and tax returns — all in one place, with the full history of operations always at hand.\n\n\uD83D\uDCCA Finances and taxes\n\uD83D\uDCB0 Income and expense tracking with attached receipts\n\uD83D\uDCC8 Automatic profit and tax calculation (12%/32% scale, 19% flat, lump-sum)\n\uD83D\uDD01 Recurring transactions (rent, subscriptions) created automatically every month\n\uD83D\uDEA6 Limit tracking: unregistered activity, 120,000 zł tax bracket, VAT exemption (200,000 zł)\n\uD83D\uDD14 Notifications when limits are approaching or exceeded\n\n\uD83E\uDDFE Invoices and receipts (Pro)\n\uD83D\uDCDD Issue invoices/receipts to individuals and companies with PDF generation\n\u2705 Statuses: Paid / Pending / Overdue, plus due-date reminders\n\uD83D\uDCB5 Tracking of the annual 20,000 zł cash-sales limit for private individuals\n\uD83D\uDD0D Invoice history with search and filters\n\n\uD83D\uDCC4 Reports and tax returns\n\uD83D\uDCCA Income/expense chart for the last 6 months\n\uD83D\uDCE5 Export monthly report (free), yearly and custom-period reports (Pro) to Excel with receipts\n\uD83E\uDDEE Generate PIT-36 / PIT-36L / PIT-28 tax returns — helper PDF and official form filling (Pro)\n\n\uD83D\uDD12 Security and convenience\n\uD83D\uDD10 App lock with PIN code and fingerprint / face unlock\n\uD83D\uDCBE Backup and restore your data (Pro)\n\uD83C\uDF19 Modern dark interface\n\uD83C\uDF0D Available in Polish, Russian and English\n\uD83D\uDD12 All data is stored locally on your device\n\nContact: p.arsenii@interia.pl</string>
    <string name="about_email">p.arsenii@interia.pl</string>
    <string name="dialog_close">Close</string>
    <string name="dialog_write">Write</string>
    <string name="pro_status_locked">Pro is locked. Unlock to get yearly/custom Excel reports, backup \&amp; restore, and remove ads.</string>
    <string name="pro_status_active">Pro unlocked. Thank you for your support!</string>
    <string name="pro_unlock_button">Unlock Pro</string>
    <string name="pro_unlock_button_price">Unlock Pro — %1$s</string>
    <string name="pro_loading">Loading price…</string>
    <string name="pro_feature_locked_title">Pro feature</string>
    <string name="pro_feature_locked_message">Yearly and custom reports are a Pro feature. Unlock Pro in Settings to use them.</string>
    <string name="pro_feature_locked_go_settings">Go to Settings</string>
    <string name="invoice_pro_locked_message">Issuing invoices is a Pro feature. Unlock Pro in Settings to use it.</string>
    <string name="backup_pro_locked_message">Backup and restore is a Pro feature. Unlock Pro to keep your data safe with a backup file.</string>
    <string name="pro_purchase_error">Could not start the purchase. Check your connection and try again.</string>
    <string name="pro_info_title">Pro version</string>
    <string name="pro_info_message">Pro unlocks:\n\n\u2022 Issuing invoices and receipts (PDF)\n\u2022 Yearly Excel report\n\u2022 Custom-period Excel report\n\u2022 PIT-36 / PIT-36L / PIT-28 tax return generation\n\u2022 Backup &amp; restore\n\u2022 No ads\n\nThis is a one-time purchase — pay once, keep it forever.</string>
    <string name="pro_info_continue">Continue to purchase</string>
    <string name="enter_code_button">Have a code?</string>
    <string name="enter_code_title">Enter code</string>
    <string name="enter_code_hint">Code</string>
    <string name="enter_code_apply">Apply</string>
    <string name="enter_code_wrong">Invalid code</string>
    <string name="enter_code_success">Pro unlocked</string>
    <string name="transaction_history">Transaction history</string>
    <string name="stat_net_profit">Net profit (after tax)</string>
    <string name="type_income">Income</string>
    <string name="type_expense">Expense</string>
    <string name="edit_income_title">Edit income</string>
    <string name="edit_expense_title">Edit expense</string>
    <string name="delete_entry">Delete</string>
    <string name="delete_confirm_title">Delete entry?</string>
    <string name="delete_confirm_message">This entry will be permanently deleted. This cannot be undone.</string>
    <string name="delete_confirm_yes">Delete</string>
    <string name="entry_updated">Updated</string>
    <string name="entry_deleted">Deleted</string>
    <string name="clear_all_button">Clear all data</string>
    <string name="clear_all_confirm_title">Are you sure?</string>
    <string name="clear_all_confirm_message">All income and expense entries will be permanently deleted. This cannot be undone.</string>
    <string name="clear_all_confirm_yes">Delete all</string>
    <string name="clear_all_done">All data has been deleted</string>

    <string name="settings_menu_tax">Tax and limits</string>
    <string name="settings_menu_language">Language</string>
    <string name="settings_menu_backup">Backup (Pro)</string>
    <string name="settings_menu_pro">Pro version</string>

    <string name="backup_hint">Save a backup of your income/expense entries — including amounts, dates, comments and attached receipt photos — as a file. In the save dialog you can choose phone storage or Google Drive (if the Drive app is installed). Keep this file safe: it\'s the only way to restore your data if you lose the phone or reinstall the app.</string>
    <string name="backup_in_progress">Working…</string>
    <string name="backup_create">Create backup</string>
    <string name="backup_restore">Restore from backup</string>
    <string name="backup_success">Backup saved (%1$d entries)</string>
    <string name="backup_error">Error: %1$s</string>
    <string name="backup_restore_confirm_title">Restore from backup?</string>
    <string name="backup_restore_confirm_message">Entries from the backup file will be added to what you already have on this device (existing entries are not deleted or overwritten). If you want a clean restore, use \"Clear all data\" first, then restore.</string>
    <string name="backup_invalid_file">This does not look like a valid FinArs backup file</string>
    <string name="backup_restored">Restored %1$d entries</string>
    <string name="backup_never">Last backup: never</string>
    <string name="backup_last_time">Last backup: %1$s</string>

    <string name="settings_menu_security">Security (PIN / fingerprint)</string>
    <string name="settings_menu_pit36">Generate PIT (Pro)</string>
    <string name="pit36_pro_locked_message">PIT-36 generation is a Pro feature. Unlock Pro in Settings to use it.</string>

    <string name="lock_title">FinArs is locked</string>
    <string name="lock_subtitle">Enter your PIN to continue</string>
    <string name="lock_pin_hint">PIN</string>
    <string name="lock_wrong_pin">Wrong PIN, try again</string>
    <string name="lock_unlock_button">Unlock</string>
    <string name="lock_biometric_button">Use fingerprint / face</string>
    <string name="lock_biometric_prompt_title">Unlock FinArs</string>
    <string name="lock_biometric_prompt_subtitle">Confirm your fingerprint or face</string>
    <string name="lock_use_pin">Use PIN</string>
    <string name="lock_biometric_unavailable">No fingerprint/face is set up on this device. Add one in your phone\'s settings first.</string>

    <string name="security_hint">Protect the app with a PIN code. When enabled, FinArs will ask for the PIN every time you open it after leaving the app. You can also enable fingerprint/face unlock as a quick shortcut for the same PIN.</string>
    <string name="security_pin_switch">Require PIN to open the app</string>
    <string name="security_change_pin">Change PIN</string>
    <string name="security_biometric_switch">Unlock with fingerprint / face</string>
    <string name="security_set_pin_title">Set a PIN</string>
    <string name="security_set_pin_message">Choose a 4–6 digit PIN</string>
    <string name="security_continue">Continue</string>
    <string name="security_pin_length_error">PIN must be 4–6 digits</string>
    <string name="security_confirm_pin_title">Confirm your PIN</string>
    <string name="security_pin_saved">PIN saved</string>
    <string name="security_pin_mismatch">PINs don\'t match, try again</string>
    <string name="security_disable_pin_title">Enter current PIN</string>
    <string name="security_enter_current_pin">Enter your current PIN to continue</string>
    <string name="security_pin_disabled">PIN protection disabled</string>

    <string name="pit_data_title">Personal data for your tax return</string>
    <string name="pit_data_hint">Used only to fill in your PIT helper report (PIT-36 / PIT-36L / PIT-28 — depending on your activity type). Everything stays on your device.</string>
    <string name="pit_first_name">First name</string>
    <string name="pit_last_name">Last name</string>
    <string name="pit_pesel">PESEL (optional)</string>
    <string name="pit_street">Street</string>
    <string name="pit_house_number">House number</string>
    <string name="pit_apartment_number">Apartment number (optional)</string>
    <string name="pit_voivodeship">Voivodeship</string>
    <string name="pit_county">County (powiat)</string>
    <string name="pit_commune">Commune (gmina)</string>
    <string name="pit_postal_code">Postal code</string>
    <string name="pit_city">City</string>
    <string name="pit_tax_office">Tax office (urząd skarbowy)</string>
    <string name="pit_reliefs_title">Reliefs and deductions (optional)</string>
    <string name="pit_children_count">Number of children (ulga na dzieci)</string>
    <string name="pit_internet_relief">Internet relief — amount spent</string>
    <string name="pit_ikze">IKZE contributions</string>
    <string name="pit_donations">Donations (darowizny)</string>
    <string name="pit_joint_spouse">File jointly with spouse</string>
    <string name="pit_spouse_data_title">Spouse personal data</string>
    <string name="pit_spouse_id_hint">Spouse NIP/PESEL</string>
    <string name="pit_spouse_first_name_hint">Spouse first name</string>
    <string name="pit_spouse_last_name_hint">Spouse last name</string>
    <string name="pit_spouse_birth_date_hint">Date of birth (DD.MM.YYYY)</string>
    <string name="pit_spouse_income_hint">Spouse income (optional)</string>
    <string name="pit_data_required_error">Please fill in first name, last name and tax office first</string>

    <string name="pit36_hint">Pick a full calendar year, check your personal data, then generate a helper PDF with the numbers and guidance for filling in your official form on podatki.gov.pl (Twój e-PIT) or on paper.</string>
    <string name="pit_row_przychod">Przychód (income)</string>
    <string name="pit_row_koszty">Koszty (expenses)</string>
    <string name="pit_row_dochod">Dochód (profit)</string>
    <string name="pit_row_tax">Estimated tax</string>
    <string name="pit_data_status_missing">Personal data not filled in yet — required before generating the report.</string>
    <string name="pit_data_status_ready">Personal data ready: %1$s</string>
    <string name="pit_edit_data_button">Edit personal data</string>
    <string name="pit36_generate_button">Generate helper PDF</string>
    <string name="pit36_disclaimer">This report is informational only and is not an official form, e-Deklaracja or tax advice. Always double-check the numbers before submitting your declaration.</string>
    <string name="pit36_calculating">Still calculating, please wait…</string>
    <string name="pit36_generated">PDF report generated</string>
    <string name="pit36_generate_official_button">Fill official form (2025 template)</string>
    <string name="pit36_official_hint">Fills the real %1$s(32)/2025 government PDF: your ID, address and business income/expenses row. You still need to add other income sources and any deductions yourself before submitting — see the disclaimer below.</string>
    <string name="pit36_official_unsupported">The official fillable form is only available for PIT-36 (skala). Your current form is %1$s — use "Generate helper PDF" instead.</string>
    <string name="pit36_official_generated">Official PIT-36 form filled. Please review sections E–K and add other income/deductions before submitting.</string>

    <!-- Activity type / registration rules -->
    <string name="activity_type_title">Activity type</string>
    <string name="activity_type_hint">Choose how you operate — this decides which limit applies and which annual form you should file.</string>
    <string name="activity_type_niezarejestrowana">Unregistered activity (bez rejestracji JDG)</string>
    <string name="activity_type_niezarejestrowana_desc" formatted="false">Income must stay under 75% of the minimum wage per month. If exceeded, you must register a JDG within 7 days. Filed via PIT-36, tax scale.</string>
    <string name="activity_type_jdg_skala" formatted="false">Registered JDG — tax scale 12% / 32% (PIT-36)</string>
    <string name="activity_type_jdg_liniowy" formatted="false">Registered JDG — flat tax 19% (PIT-36L)</string>
    <string name="activity_type_jdg_ryczalt">Registered JDG — lump-sum tax (PIT-28)</string>
    <string name="ryczalt_rate_label" formatted="false">Lump-sum tax rate for your activity (%, depends on PKD)</string>
    <string name="ryczalt_rate_hint">e.g. 3, 5.5, 8.5, 12, 17</string>
    <string name="min_wage_label">Minimum monthly wage (zł) — used to calculate the unregistered-activity limit</string>
    <string name="monthly_limit_preview" formatted="false">Monthly limit (75%): %1$,.2f zł</string>

    <!-- Main screen limit gauges -->
    <string name="limits_title">Limits</string>
    <string name="limit_monthly_label">Unregistered activity, this month: %1$s / %2$s zł</string>
    <string name="limit_bracket_label">First tax bracket (120,000 zł/year): %1$s / %2$s zł</string>
    <string name="limit_vat_label">VAT exemption (200,000 zł/year): %1$s / %2$s zł</string>
    <string name="limit_exceeded_warning">You have exceeded the unregistered-activity limit! You must register a JDG within 7 days.</string>

    <!-- Dynamic tax label -->
    <string name="tax_label_zero" formatted="false">Tax (0% — tax-free amount)</string>
    <string name="tax_label_12" formatted="false">Tax (12%)</string>
    <string name="tax_label_32" formatted="false">Tax (32% bracket)</string>
    <string name="tax_label_progressive" formatted="false">Tax (progressive scale 12% / 32%)</string>
    <string name="tax_label_liniowy" formatted="false">Tax (flat 19%)</string>
    <string name="tax_label_ryczalt">Tax (lump-sum, of revenue)</string>
    <string name="pit_form_applicable">Applicable declaration: %1$s</string>

    <!-- History table -->
    <string name="history_col_receipt">Receipt</string>
    <string name="history_col_amount">Amount</string>

    <!-- Report columns -->
    <string name="report_col_receipt">Receipt</string>
    <string name="report_receipt_yes">Yes</string>

    <!-- Notifications -->
    <string name="notif_channel_name">Limits and deadlines</string>
    <string name="notif_channel_description">Alerts about activity limits and tax deadlines</string>
    <string name="notif_limit_exceeded_title">Unregistered activity limit exceeded</string>
    <string name="notif_limit_exceeded_text" formatted="false">Your income this month exceeds 75% of the minimum wage. You must register a JDG within 7 days.</string>
    <string name="notif_limit_95_title" formatted="false">95% of the monthly limit reached</string>
    <string name="notif_limit_95_text">You are very close to the unregistered-activity limit for this month.</string>
    <string name="notif_limit_80_title" formatted="false">80% of the monthly limit reached</string>
    <string name="notif_limit_80_text" formatted="false">You have used 80% of the unregistered-activity limit for this month.</string>
    <string name="notif_bracket_title">Approaching the 120,000 zł threshold</string>
    <string name="notif_bracket_text" formatted="false">Your yearly profit is close to 120,000 zł — income above this is taxed at 32% instead of 12%.</string>
    <string name="notif_vat_title">Approaching the VAT exemption limit</string>
    <string name="notif_vat_text">Your yearly revenue is close to 200,000 zł — the VAT exemption threshold.</string>
    <string name="notif_advance_title">Advance tax payment reminder</string>
    <string name="notif_advance_text">Advance tax payments are due by the 20th of the month.</string>
    <string name="notif_pit_deadline_title">Annual tax return reminder</string>
    <string name="notif_pit_deadline_text">Annual tax returns are due between 15 February and 30 April.</string>
    <string name="terms_title">Terms of Service</string>
    <string name="terms_full_text">Terms of Service and Legal Disclaimer\n\nBy tapping “Accept”, you confirm that you have read, understood and fully agree to these terms. If you do not agree, you may not use the FinArs app.\n\n1. No accounting or legal services\nFinArs is a tool only (an automated calculator and record organizer). Neither the app nor its developers are an accredited accounting firm, tax advisor, or law office. All calculations and auto-generated declarations (PIT-36, PIT-36L, PIT-28) are for informational purposes only.\n\n2. Your responsibility\nYou are solely responsible for the accuracy of entered data and for verifying calculations and PDF forms before filing them with tax authorities, and for meeting filing deadlines.\n\n3. Limitation of liability\nThe app is provided “as is”, without warranties. The developer is not liable for fines, tax adjustments, algorithm errors, or data loss on your device.\n\n4. Legal changes\nPolish tax law changes regularly; verify results against podatki.gov.pl or a licensed accountant.\n\n5. Data privacy\nAll data and generated PDFs are stored locally on your device only.\n\n6. Governing law\nThe laws of the Republic of Poland apply.\n\n7. Withdrawal\nThese terms are accepted once, on first launch. If you stop agreeing, you must stop using the app and uninstall it.</string>
    <string name="terms_checkbox_label">I have read and accept the Terms of Service</string>
    <string name="terms_accept_button">Accept and continue</string>
    <string name="terms_status_accepted">Status: Terms accepted (%1$s)</string>
    <string name="terms_status_unknown">Status: Terms accepted</string>
    <string name="settings_menu_terms">Terms of Service</string>


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

    <!-- Invoice history -->
    <string name="invoice_history_title">Invoice history</string>
    <string name="no_invoices">No invoices yet</string>


    <!-- Invoice PDF labels -->
    <string name="invoice_pdf_faktura">INVOICE</string>
    <string name="invoice_pdf_rachunek">RECEIPT</string>
    <string name="invoice_pdf_issue_date">Issue date</string>
    <string name="invoice_pdf_sale_date">Sale date</string>
    <string name="invoice_pdf_seller">Seller</string>
    <string name="invoice_pdf_buyer">Buyer</string>
    <string name="invoice_pdf_nip">Tax ID (NIP)</string>
    <string name="invoice_pdf_bank_account">Bank account</string>
    <string name="invoice_pdf_buyer_private">Private individual (no Tax ID).</string>
    <string name="invoice_pdf_table_lp">No.</string>
    <string name="invoice_pdf_table_name">Item / service</string>
    <string name="invoice_pdf_table_unit">Unit</string>
    <string name="invoice_pdf_table_qty">Qty</string>
    <string name="invoice_pdf_table_price">Price</string>
    <string name="invoice_pdf_table_total">Total</string>
    <string name="invoice_pdf_unit_piece">pc</string>
    <string name="invoice_pdf_sum_label">Total</string>
    <string name="invoice_pdf_paid_stamp">PAID</string>
    <string name="invoice_pdf_payment_date">Payment date</string>
    <string name="invoice_pdf_footer">Document generated in the FinArs app. This is not official accounting or tax advice — if in doubt, consult a tax advisor.</string>
    <string name="seller_bank_account">Bank account (optional)</string>
    <string name="delete_invoice_confirm_title">Delete invoice?</string>
    <string name="delete_invoice_confirm_message">The invoice record and its PDF file will be permanently deleted. This cannot be undone.</string>
    <string name="invoice_deleted">Invoice deleted</string>

    <string name="invoice_status_paid">Paid</string>
    <string name="invoice_status_pending">Pending</string>
    <string name="invoice_status_overdue">Overdue</string>
    <string name="invoice_paid_switch_label">Paid</string>
    <string name="invoice_due_date_label">Due date</string>
    <string name="notif_invoice_overdue_title">Overdue invoice</string>
    <string name="notif_invoice_overdue_text">Invoice №%2$d for %1$s is overdue.</string>
    <string name="notif_invoice_due_soon_title">Payment due soon</string>
    <string name="notif_invoice_due_soon_text">Invoice №%2$d for %1$s is due within 3 days.</string>
    <string name="recurring_switch_label">Repeat monthly</string>
    <string name="chart_title">Income and expenses, last 6 months</string>
    <string name="invoice_status_filter_all">All</string>

    <string name="invoice_pdf_pending_stamp">AWAITING PAYMENT</string>

    <!-- Update 41: business kind, magazin, barcode, receipt OCR -->
    <string name="settings_menu_business">Sales type (goods/services)</string>
    <string name="business_kind_title">Sales type (goods/services)</string>
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

    <!-- Update 41 fix 6 -->
    <string name="invoice_mark_paid_confirm_title">Mark as paid?</string>
    <string name="invoice_mark_paid_confirm_message">This sets the invoice status to paid today and updates the saved PDF file to reflect the new status.</string>
    <string name="invoice_marked_paid_toast">Invoice marked as paid</string>
    <string name="invoice_marked_paid_pdf_warning">Status updated, but the PDF file could not be regenerated</string>

    <!-- Update 42: warehouse inventory count + better receipt scanning -->
    <string name="start_inventory">Take inventory</string>
    <string name="inventory_title">Warehouse inventory</string>
    <string name="inventory_hint">Check the actual quantity of each product. Only changed items will be updated.</string>
    <string name="inventory_current_stock">In system: %1$s %2$s</string>
    <string name="inventory_save">Save inventory</string>
    <string name="inventory_no_changes">No differences found, nothing changed</string>
    <string name="inventory_saved_title">Inventory saved</string>
    <string name="inventory_diff_line">%1$s: %2$s → %3$s (%4$s)</string>
</resources>
EOF_APP_SRC_MAIN_RES_VALUES_STRINGS_XML
echo "OK: app/src/main/res/values/strings.xml"

mkdir -p "$(dirname "app/src/main/res/values-ru/strings.xml")"
cat > app/src/main/res/values-ru/strings.xml << 'EOF_APP_SRC_MAIN_RES_VALUES_RU_STRINGS_XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">FinArs</string>
    <string name="app_subtitle">FinArs</string>
    <string name="add_income">Добавить доход</string>
    <string name="add_expense">Добавить расход</string>
    <string name="add_entry">Добавить +</string>
    <string name="balance">Баланс</string>
    <string name="enter_amount">Сумма</string>
    <string name="enter_comment">Комментарий</string>
    <string name="entry_date_label">Дата операции</string>
    <string name="attach_receipt">Прикрепить чек</string>
    <string name="save">Сохранить</string>
    <string name="settings">Настройки</string>
    <string name="tax_percent">Процент налога</string>
    <string name="other_income_label">Прочие доходы (%1$d)</string>
    <string name="tax_scale_title">Налог считается автоматически</string>
    <string name="tax_scale_description" formatted="false">0% до 30 000 zł/год · 12% с суммы от 30 000 до 120 000 zł · 32% с суммы свыше 120 000 zł. Ставка применяется только к части сверх каждого порога, а не ко всей сумме.</string>
    <string name="other_income_title">Прочие доходы</string>
    <string name="other_income_hint">Ваш общий налогооблагаемый доход за этот год из других источников (работа, другая деятельность и т.д.). Учитывается вместе с доходом из этого приложения при проверке годового необлагаемого лимита в 30 000 zł.</string>
    <string name="saved">Сохранено</string>
    <string name="auto_tax_button">Рассчитать автоматически</string>
    <string name="auto_tax_result" formatted="false">Предложенная ставка: %1$.1f% (по шкале PIT: 12% до 120 000 zł/год, 32% свыше). Перед сохранением можно поправить вручную.</string>
    <string name="export_report">Экспорт отчёта</string>
    <string name="generate_report">Сгенерировать отчёт</string>
    <string name="select_period">Выберите период</string>
    <string name="month">Месяц</string>
    <string name="year">Год</string>
    <string name="custom_range">Произвольный период</string>
    <string name="from">От</string>
    <string name="to">До</string>
    <string name="no_entries">Нет записей</string>
    <string name="search_no_results">Ничего не найдено</string>
    <string name="history_search_hint">Поиск по комментарию или сумме</string>
    <string name="invoice_search_hint">Поиск по номеру, клиенту или сумме</string>
    <string name="filter_date_range">Диапазон дат</string>
    <string name="filter_clear">Сбросить фильтры</string>

    <string name="statistics">Статистика</string>
    <string name="stat_income">Доход</string>
    <string name="stat_expense">Расход</string>
    <string name="stat_profit">Прибыль (до налога)</string>
    <string name="stat_tax_format" formatted="false">Налог (%1$.1f%)</string>

    <string name="report_col_date">Дата</string>
    <string name="report_col_income">Доход</string>
    <string name="report_col_expense">Расход</string>
    <string name="report_col_tax_percent" formatted="false">Налог %</string>
    <string name="report_col_tax_amount">Сумма налога</string>
    <string name="report_col_comment">Комментарий</string>
    <string name="report_sheet_name">Отчёт</string>
    <string name="report_title_month">Отчёт — Месяц</string>
    <string name="report_title_year">Отчёт — Год</string>
    <string name="report_title_custom">Отчёт — Произвольный период</string>
    <string name="custom_range_invalid">Дата окончания должна быть позже даты начала</string>
    <string name="report_total_income">Итого доход</string>
    <string name="report_total_expense">Итого расход</string>
    <string name="report_total_profit">Итого прибыль</string>
    <string name="report_total_tax">Итого налог</string>
    <string name="report_total_net_profit">Чистая прибыль (после налога)</string>
    <string name="report_generating">Формирую отчёт…</string>
    <string name="report_ready">Отчёт готов</string>
    <string name="report_share_title">Поделиться отчётом</string>
    <string name="report_error">Ошибка формирования отчёта: %1$s</string>
    <string name="about_app">О приложении</string>
    <string name="about_description">FinArs — комплексное приложение для управления финансами нерегистрируемой деятельности и ИП (JDG). Ведите учёт доходов и расходов, контролируйте лимиты, автоматически считайте налоги, выставляйте счета и формируйте готовые отчёты и налоговые декларации — всё в одном месте, с полной историей операций под рукой.\n\n\uD83D\uDCCA Финансы и налоги\n\uD83D\uDCB0 Учёт доходов и расходов с прикреплением чеков\n\uD83D\uDCC8 Автоматический расчёт прибыли и налога (шкала 12%/32%, плоский 19%, ryczałt)\n\uD83D\uDD01 Регулярные транзакции (аренда, подписки) создаются автоматически каждый месяц\n\uD83D\uDEA6 Контроль лимитов: незарегистрированная деятельность, порог 120 000 zł, освобождение от VAT (200 000 zł)\n\uD83D\uDD14 Уведомления о приближении и превышении лимитов\n\n\uD83E\uDDFE Счета и фактуры (Pro)\n\uD83D\uDCDD Выставление счетов/фактур физлицам и компаниям с генерацией PDF\n\u2705 Статусы: Оплачена / Ожидает оплаты / Просрочена, плюс напоминания о сроке оплаты\n\uD83D\uDCB5 Контроль годового лимита наличных (20 000 zł) для продаж физлицам\n\uD83D\uDD0D История счетов с поиском и фильтрами\n\n\uD83D\uDCC4 Отчёты и декларации\n\uD83D\uDCCA График доходов и расходов за последние 6 месяцев\n\uD83D\uDCE5 Экспорт отчёта за месяц (бесплатно), год и произвольный период (Pro) в Excel вместе с чеками\n\uD83E\uDDEE Формирование деклараций PIT-36 / PIT-36L / PIT-28 — вспомогательный PDF и заполнение официального бланка (Pro)\n\n\uD83D\uDD12 Безопасность и удобство\n\uD83D\uDD10 Блокировка приложения PIN-кодом и отпечатком пальца / лицом\n\uD83D\uDCBE Резервное копирование и восстановление данных (Pro)\n\uD83C\uDF19 Современный тёмный интерфейс\n\uD83C\uDF0D Доступно на польском, русском и английском языках\n\uD83D\uDD12 Все данные хранятся локально на устройстве\n\nСвязь: p.arsenii@interia.pl</string>
    <string name="about_email">p.arsenii@interia.pl</string>
    <string name="dialog_close">Закрыть</string>
    <string name="dialog_write">Написать</string>
    <string name="pro_status_locked">Pro не активирован. Разблокируйте, чтобы получить годовые и произвольные отчёты в Excel, резервное копирование и восстановление, а также убрать рекламу.</string>
    <string name="pro_status_active">Pro активирован. Спасибо за поддержку!</string>
    <string name="pro_unlock_button">Разблокировать Pro</string>
    <string name="pro_unlock_button_price">Разблокировать Pro — %1$s</string>
    <string name="pro_loading">Загрузка цены…</string>
    <string name="pro_feature_locked_title">Функция Pro</string>
    <string name="pro_feature_locked_message">Годовые и произвольные отчёты доступны только в Pro-версии. Разблокируйте Pro в настройках.</string>
    <string name="pro_feature_locked_go_settings">Перейти в настройки</string>
    <string name="invoice_pro_locked_message">Выставление фактур доступно только в Pro-версии. Разблокируйте Pro в настройках.</string>
    <string name="backup_pro_locked_message">Резервное копирование и восстановление — Pro-функция. Разблокируйте Pro, чтобы сохранить данные в файл на случай потери.</string>
    <string name="pro_purchase_error">Не удалось открыть окно оплаты. Проверьте соединение и попробуйте снова.</string>
    <string name="pro_info_title">Pro-версия</string>
    <string name="pro_info_message">Pro открывает:\n\n\u2022 Выставление счетов и фактур (PDF)\n\u2022 Годовой отчёт в Excel\n\u2022 Отчёт за произвольный период\n\u2022 Формирование деклараций PIT-36 / PIT-36L / PIT-28\n\u2022 Резервное копирование и восстановление\n\u2022 Без рекламы\n\nЭто разовая покупка — платите один раз, доступ остаётся навсегда.</string>
    <string name="pro_info_continue">Перейти к покупке</string>
    <string name="enter_code_button">Есть код?</string>
    <string name="enter_code_title">Введите код</string>
    <string name="enter_code_hint">Код</string>
    <string name="enter_code_apply">Применить</string>
    <string name="enter_code_wrong">Неверный код</string>
    <string name="enter_code_success">Pro активирован</string>
    <string name="transaction_history">История операций</string>
    <string name="stat_net_profit">Чистая прибыль (после налога)</string>
    <string name="type_income">Доход</string>
    <string name="type_expense">Расход</string>
    <string name="edit_income_title">Редактировать доход</string>
    <string name="edit_expense_title">Редактировать расход</string>
    <string name="delete_entry">Удалить</string>
    <string name="delete_confirm_title">Удалить запись?</string>
    <string name="delete_confirm_message">Запись будет удалена без возможности восстановления.</string>
    <string name="delete_confirm_yes">Удалить</string>
    <string name="entry_updated">Обновлено</string>
    <string name="entry_deleted">Удалено</string>
    <string name="clear_all_button">Очистить все данные</string>
    <string name="clear_all_confirm_title">Вы уверены?</string>
    <string name="clear_all_confirm_message">Все доходы и расходы будут безвозвратно удалены. Это действие нельзя отменить.</string>
    <string name="clear_all_confirm_yes">Удалить всё</string>
    <string name="clear_all_done">Все данные удалены</string>

    <string name="settings_menu_tax">Налог и лимиты</string>
    <string name="settings_menu_language">Язык</string>
    <string name="settings_menu_backup">Резервная копия (Pro)</string>
    <string name="settings_menu_pro">Pro версия</string>

    <string name="backup_hint">Сохраните резервную копию доходов/расходов — суммы, даты, комментарии и прикреплённые фото чеков — в виде файла. В окне сохранения можно выбрать память телефона или Google Диск (если установлено приложение Диска). Храните этот файл в надёжном месте — только по нему можно восстановить данные при потере телефона или переустановке приложения.</string>
    <string name="backup_in_progress">Выполняется…</string>
    <string name="backup_create">Создать резервную копию</string>
    <string name="backup_restore">Восстановить из копии</string>
    <string name="backup_success">Копия сохранена (%1$d записей)</string>
    <string name="backup_error">Ошибка: %1$s</string>
    <string name="backup_restore_confirm_title">Восстановить из копии?</string>
    <string name="backup_restore_confirm_message">Записи из файла копии будут добавлены к тем, что уже есть на этом устройстве (существующие записи не удаляются и не перезаписываются). Если нужно "чистое" восстановление — сначала используйте "Очистить все данные", затем восстановление.</string>
    <string name="backup_invalid_file">Это не похоже на файл резервной копии FinArs</string>
    <string name="backup_restored">Восстановлено записей: %1$d</string>
    <string name="backup_never">Последняя копия: никогда</string>
    <string name="backup_last_time">Последняя копия: %1$s</string>

    <string name="settings_menu_security">Безопасность (PIN / отпечаток)</string>
    <string name="settings_menu_pit36">Сформировать PIT (Pro)</string>
    <string name="pit36_pro_locked_message">Генерация PIT-36 — функция Pro. Разблокируйте Pro в настройках, чтобы ей пользоваться.</string>

    <string name="lock_title">FinArs заблокирован</string>
    <string name="lock_subtitle">Введите PIN, чтобы продолжить</string>
    <string name="lock_pin_hint">PIN</string>
    <string name="lock_wrong_pin">Неверный PIN, попробуйте ещё раз</string>
    <string name="lock_unlock_button">Разблокировать</string>
    <string name="lock_biometric_button">Войти по отпечатку / лицу</string>
    <string name="lock_biometric_prompt_title">Разблокировка FinArs</string>
    <string name="lock_biometric_prompt_subtitle">Подтвердите отпечатком пальца или лицом</string>
    <string name="lock_use_pin">Ввести PIN</string>
    <string name="lock_biometric_unavailable">На этом устройстве не настроен отпечаток/лицо. Сначала добавьте его в настройках телефона.</string>

    <string name="security_hint">Защитите приложение PIN-кодом. Когда функция включена, FinArs будет спрашивать PIN каждый раз, когда вы возвращаетесь в приложение после его сворачивания. Также можно включить вход по отпечатку/лицу — это быстрый способ ввести тот же PIN.</string>
    <string name="security_pin_switch">Запрашивать PIN при открытии приложения</string>
    <string name="security_change_pin">Изменить PIN</string>
    <string name="security_biometric_switch">Вход по отпечатку / лицу</string>
    <string name="security_set_pin_title">Установите PIN</string>
    <string name="security_set_pin_message">Выберите PIN из 4–6 цифр</string>
    <string name="security_continue">Продолжить</string>
    <string name="security_pin_length_error">PIN должен состоять из 4–6 цифр</string>
    <string name="security_confirm_pin_title">Подтвердите PIN</string>
    <string name="security_pin_saved">PIN сохранён</string>
    <string name="security_pin_mismatch">PIN-коды не совпадают, попробуйте ещё раз</string>
    <string name="security_disable_pin_title">Введите текущий PIN</string>
    <string name="security_enter_current_pin">Введите текущий PIN, чтобы продолжить</string>
    <string name="security_pin_disabled">Защита PIN-ом отключена</string>

    <string name="pit_data_title">Личные данные для налоговой декларации</string>
    <string name="pit_data_hint">Используются только для заполнения вспомогательного отчёта PIT (PIT-36 / PIT-36L / PIT-28 — в зависимости от вида деятельности). Всё остаётся на вашем устройстве.</string>
    <string name="pit_first_name">Имя</string>
    <string name="pit_last_name">Фамилия</string>
    <string name="pit_pesel">PESEL (необязательно)</string>
    <string name="pit_street">Улица</string>
    <string name="pit_house_number">Номер дома</string>
    <string name="pit_apartment_number">Номер квартиры (необязательно)</string>
    <string name="pit_voivodeship">Воеводство</string>
    <string name="pit_county">Повят</string>
    <string name="pit_commune">Гмина</string>
    <string name="pit_postal_code">Почтовый индекс</string>
    <string name="pit_city">Город</string>
    <string name="pit_tax_office">Налоговая инспекция (urząd skarbowy)</string>
    <string name="pit_reliefs_title">Льготы и вычеты (необязательно)</string>
    <string name="pit_children_count">Количество детей (ulga na dzieci)</string>
    <string name="pit_internet_relief">Льгота на интернет — сумма расходов</string>
    <string name="pit_ikze">Взносы на IKZE</string>
    <string name="pit_donations">Пожертвования (darowizny)</string>
    <string name="pit_joint_spouse">Совместная подача с супругом</string>
    <string name="pit_spouse_data_title">Личные данные супруга(и)</string>
    <string name="pit_spouse_id_hint">NIP/PESEL супруга(и)</string>
    <string name="pit_spouse_first_name_hint">Имя супруга(и)</string>
    <string name="pit_spouse_last_name_hint">Фамилия супруга(и)</string>
    <string name="pit_spouse_birth_date_hint">Дата рождения (ДД.ММ.ГГГГ)</string>
    <string name="pit_spouse_income_hint">Доход супруга(и) (опционально)</string>
    <string name="pit_data_required_error">Сначала укажите имя, фамилию и налоговую инспекцию</string>

    <string name="pit36_hint">Выберите полный календарный год, проверьте личные данные, затем сформируйте вспомогательный PDF с цифрами и подсказками для заполнения вашей декларации на podatki.gov.pl (Twój e-PIT) или на бумаге.</string>
    <string name="pit_row_przychod">Przychód (доход)</string>
    <string name="pit_row_koszty">Koszty (расходы)</string>
    <string name="pit_row_dochod">Dochód (прибыль)</string>
    <string name="pit_row_tax">Расчётный налог</string>
    <string name="pit_data_status_missing">Личные данные ещё не заполнены — это нужно сделать перед формированием отчёта.</string>
    <string name="pit_data_status_ready">Личные данные готовы: %1$s</string>
    <string name="pit_edit_data_button">Изменить личные данные</string>
    <string name="pit36_generate_button">Сформировать вспомогательный PDF</string>
    <string name="pit36_disclaimer">Этот отчёт носит исключительно информационный характер и не является официальным бланком, e-Deklaracją или налоговой консультацией. Всегда перепроверяйте цифры перед подачей декларации.</string>
    <string name="pit36_calculating">Идёт расчёт, подождите…</string>
    <string name="pit36_generated">PDF-отчёт сформирован</string>
    <string name="pit36_generate_official_button">Заполнить официальный бланк (шаблон 2025)</string>
    <string name="pit36_official_hint">Заполняет настоящий государственный PDF %1$s(32)/2025: ваши данные, адрес и строку доходов/расходов бизнеса. Остальные источники дохода и вычеты нужно дозаполнить самостоятельно — см. предупреждение ниже.</string>
    <string name="pit36_official_unsupported">Официальный заполненный бланк доступен только для PIT-36 (skala). Ваша текущая форма — %1$s, используйте кнопку «Сформировать вспомогательный PDF».</string>
    <string name="pit36_official_generated">Официальный бланк PIT-36 заполнен. Проверьте разделы E–K и добавьте другие доходы/вычеты перед подачей.</string>

    <!-- Тип деятельности / правила регистрации -->
    <string name="activity_type_title">Форма деятельности</string>
    <string name="activity_type_hint">Выберите, как вы работаете — от этого зависит применяемый лимит и то, какую декларацию подавать.</string>
    <string name="activity_type_niezarejestrowana">Незарегистрированная деятельность (без JDG)</string>
    <string name="activity_type_niezarejestrowana_desc" formatted="false">Доход не должен превышать 75% минимальной зарплаты в месяц. При превышении нужно зарегистрировать JDG в течение 7 дней. Подаётся через PIT-36 по обычной шкале.</string>
    <string name="activity_type_jdg_skala" formatted="false">Зарегистрированное ИП (JDG) — шкала 12% / 32% (PIT-36)</string>
    <string name="activity_type_jdg_liniowy" formatted="false">Зарегистрированное ИП (JDG) — плоский налог 19% (PIT-36L)</string>
    <string name="activity_type_jdg_ryczalt">Зарегистрированное ИП (JDG) — ryczałt (PIT-28)</string>
    <string name="ryczalt_rate_label" formatted="false">Ставка ryczałtu для вашей деятельности (%, зависит от PKD)</string>
    <string name="ryczalt_rate_hint">например 3, 5.5, 8.5, 12, 17</string>
    <string name="min_wage_label">Минимальная месячная зарплата (zł) — для расчёта лимита незарегистрированной деятельности</string>
    <string name="monthly_limit_preview" formatted="false">Месячный лимит (75%): %1$.2f zł</string>

    <!-- Гейджи лимитов на главном экране -->
    <string name="limits_title">Лимиты</string>
    <string name="limit_monthly_label">Незарегистрированная деятельность, этот месяц: %1$s / %2$s zł</string>
    <string name="limit_bracket_label">Первый налоговый порог (120 000 zł/год): %1$s / %2$s zł</string>
    <string name="limit_vat_label">Освобождение от VAT (200 000 zł/год): %1$s / %2$s zł</string>
    <string name="limit_exceeded_warning">Превышен лимит незарегистрированной деятельности! Вы обязаны зарегистрировать JDG в течение 7 дней.</string>

    <!-- Динамическая подпись налога -->
    <string name="tax_label_zero" formatted="false">Налог (0% — необлагаемый минимум)</string>
    <string name="tax_label_12" formatted="false">Налог (12%)</string>
    <string name="tax_label_32" formatted="false">Налог (ставка 32%)</string>
    <string name="tax_label_progressive" formatted="false">Налог (прогрессивная шкала 12% / 32%)</string>
    <string name="tax_label_liniowy" formatted="false">Налог (плоский 19%)</string>
    <string name="tax_label_ryczalt">Налог (ryczałt, от дохода)</string>
    <string name="pit_form_applicable">Применимая декларация: %1$s</string>

    <!-- Таблица истории -->
    <string name="history_col_receipt">Чек</string>
    <string name="history_col_amount">Сумма</string>

    <!-- Колонки отчёта -->
    <string name="report_col_receipt">Чек</string>
    <string name="report_receipt_yes">Есть</string>

    <!-- Уведомления -->
    <string name="notif_channel_name">Лимиты и сроки</string>
    <string name="notif_channel_description">Оповещения о лимитах деятельности и налоговых сроках</string>
    <string name="notif_limit_exceeded_title">Превышен лимит незарегистрированной деятельности</string>
    <string name="notif_limit_exceeded_text" formatted="false">Доход в этом месяце превышает 75% минимальной зарплаты. Зарегистрируйте JDG в течение 7 дней.</string>
    <string name="notif_limit_95_title" formatted="false">Достигнуто 95% месячного лимита</string>
    <string name="notif_limit_95_text">Вы очень близки к лимиту незарегистрированной деятельности за этот месяц.</string>
    <string name="notif_limit_80_title" formatted="false">Достигнуто 80% месячного лимита</string>
    <string name="notif_limit_80_text" formatted="false">Использовано 80% лимита незарегистрированной деятельности за этот месяц.</string>
    <string name="notif_bracket_title">Приближение к порогу 120 000 zł</string>
    <string name="notif_bracket_text" formatted="false">Годовая прибыль приближается к 120 000 zł — доход сверх этой суммы облагается по 32% вместо 12%.</string>
    <string name="notif_vat_title">Приближение к лимиту освобождения от VAT</string>
    <string name="notif_vat_text">Годовой доход приближается к 200 000 zł — порогу освобождения от VAT.</string>
    <string name="notif_advance_title">Напоминание об авансовом платеже</string>
    <string name="notif_advance_text">Авансовые платежи по налогу нужно вносить до 20 числа каждого месяца.</string>
    <string name="notif_pit_deadline_title">Напоминание о подаче годовой декларации</string>
    <string name="notif_pit_deadline_text">Годовые декларации подаются с 15 февраля по 30 апреля.</string>
    <string name="terms_title">Пользовательское соглашение</string>
    <string name="terms_full_text">Пользовательское соглашение и Отказ от ответственности (Terms of Service &amp; Legal Disclaimer)\n\nНажимая кнопку «Принять», вы подтверждаете, что прочитали, поняли и полностью согласны со всеми условиями данного соглашения. Если вы не согласны с условиями, вы не имеете права использовать приложение FinArs.\n\n1. Отказ от оказания бухгалтерских и юридических услуг\n— Приложение FinArs является исключительно инструментальным сервисом (автоматизированным калькулятором и органайзером учета данных).\n— Приложение, его разработчики и правообладатели НЕ являются аккредитованной бухгалтерской компанией, налоговыми консультантами (Doradca podatkowy) или юридическим бюро.\n— Все расчеты, автоматические генерации деклараций (включая формы PIT-36, PIT-36L, PIT-28), шкалы лимитов и уведомления носят исключительно информационный и справочный характер.\n\n2. Ответственность за точность и подачу данных\nПользователь несет полную и единоличную ответственность за достоверность вводимых данных, проверку итоговых расчетов и PDF-форм перед подачей в налоговые органы, а также за соблюдение сроков подачи деклараций и регистрации деятельности.\n\n3. Ограничение ответственности разработчика\nПриложение предоставляется «как есть», без каких-либо гарантий. Разработчик не несет ответственности за штрафы, доначисления, ошибки алгоритмов и потерю данных на устройстве пользователя.\n\n4. Изменения в законодательстве\nЗаконодательство Республики Польша регулярно меняется. Рекомендуется сверять результаты с podatki.gov.pl или лицензированными бухгалтерами.\n\n5. Конфиденциальность и хранение данных\nВсе данные и PDF-файлы хранятся локально на устройстве пользователя. Разработчик не собирает и не передает финансовые документы на внешние серверы.\n\n6. Применимое право\nК настоящему Соглашению применяется законодательство Республики Польша.\n\n7. Отзыв согласия\nСоглашение принимается однократно при первом запуске. Если пользователь больше не согласен с условиями — он обязан прекратить использование приложения и удалить его.</string>
    <string name="terms_checkbox_label">Я прочитал(а) и принимаю условия соглашения</string>
    <string name="terms_accept_button">Принять и продолжить</string>
    <string name="terms_status_accepted">Статус: Соглашение принято (%1$s)</string>
    <string name="terms_status_unknown">Статус: Соглашение принято</string>
    <string name="settings_menu_terms">Пользовательское соглашение</string>


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

    <!-- История счетов -->
    <string name="invoice_history_title">История счетов</string>
    <string name="no_invoices">Вы ещё не выставили ни одного счёта</string>


    <!-- Метки PDF счёта -->
    <string name="invoice_pdf_faktura">СЧЁТ-ФАКТУРА</string>
    <string name="invoice_pdf_rachunek">СЧЁТ</string>
    <string name="invoice_pdf_issue_date">Дата выставления</string>
    <string name="invoice_pdf_sale_date">Дата продажи</string>
    <string name="invoice_pdf_seller">Продавец</string>
    <string name="invoice_pdf_buyer">Покупатель</string>
    <string name="invoice_pdf_nip">NIP</string>
    <string name="invoice_pdf_bank_account">Счёт</string>
    <string name="invoice_pdf_buyer_private">Физическое лицо без предпринимательской деятельности (без NIP).</string>
    <string name="invoice_pdf_table_lp">№</string>
    <string name="invoice_pdf_table_name">Наименование товара/услуги</string>
    <string name="invoice_pdf_table_unit">Ед.</string>
    <string name="invoice_pdf_table_qty">Кол-во</string>
    <string name="invoice_pdf_table_price">Цена</string>
    <string name="invoice_pdf_table_total">Сумма</string>
    <string name="invoice_pdf_unit_piece">шт</string>
    <string name="invoice_pdf_sum_label">Итого</string>
    <string name="invoice_pdf_paid_stamp">ОПЛАЧЕНО</string>
    <string name="invoice_pdf_payment_date">Дата оплаты</string>
    <string name="invoice_pdf_footer">Документ создан в приложении FinArs. Не является официальной бухгалтерской или налоговой консультацией — в случае сомнений обратитесь к налоговому консультанту.</string>
    <string name="seller_bank_account">Номер счёта (необязательно)</string>
    <string name="delete_invoice_confirm_title">Удалить счёт?</string>
    <string name="delete_invoice_confirm_message">Запись и PDF-файл счёта будут безвозвратно удалены. Это действие нельзя отменить.</string>
    <string name="invoice_deleted">Счёт удалён</string>

    <string name="invoice_status_paid">Оплачена</string>
    <string name="invoice_status_pending">Ожидает оплаты</string>
    <string name="invoice_status_overdue">Просрочена</string>
    <string name="invoice_paid_switch_label">Оплачена</string>
    <string name="invoice_due_date_label">Срок оплаты</string>
    <string name="notif_invoice_overdue_title">Просроченная фактура</string>
    <string name="notif_invoice_overdue_text">Фактура №%2$d для %1$s просрочена.</string>
    <string name="notif_invoice_due_soon_title">Скоро срок оплаты</string>
    <string name="notif_invoice_due_soon_text">Срок оплаты фактуры №%2$d для %1$s истекает в течение 3 дней.</string>
    <string name="recurring_switch_label">Повторять ежемесячно</string>
    <string name="chart_title">Доходы и расходы за последние 6 месяцев</string>
    <string name="invoice_status_filter_all">Все</string>

    <string name="invoice_pdf_pending_stamp">ОЖИДАЕТ ОПЛАТЫ</string>

    <!-- Update 41: тип деятельности, склад, штрихкоды, OCR чеков -->
    <string name="settings_menu_business">Тип продаж (товары/услуги)</string>
    <string name="business_kind_title">Тип продаж (товары/услуги)</string>
    <string name="business_kind_description">Выберите, что больше подходит вашему бизнесу. При выборе \"Продажи\" или \"Смешанная\" на главном экране появится кнопка \"Склад\" для учёта товаров.</string>
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
    <string name="product_low_stock">Порог \"заканчивается\"</string>
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

    <!-- Update 41 fix 6 -->
    <string name="invoice_mark_paid_confirm_title">Отметить как оплаченную?</string>
    <string name="invoice_mark_paid_confirm_message">Статус фактуры изменится на «оплачена» сегодняшним числом, а сохранённый PDF-файл будет обновлён с новым статусом.</string>
    <string name="invoice_marked_paid_toast">Фактура отмечена как оплаченная</string>
    <string name="invoice_marked_paid_pdf_warning">Статус обновлён, но не удалось перезаписать PDF-файл</string>

    <!-- Update 42: инвентаризация склада + улучшенное сканирование чеков -->
    <string name="start_inventory">Провести инвентаризацию</string>
    <string name="inventory_title">Инвентаризация склада</string>
    <string name="inventory_hint">Проверьте фактическое количество каждого товара. Обновятся только изменённые позиции.</string>
    <string name="inventory_current_stock">По учёту: %1$s %2$s</string>
    <string name="inventory_save">Сохранить инвентаризацию</string>
    <string name="inventory_no_changes">Расхождений не найдено, ничего не изменилось</string>
    <string name="inventory_saved_title">Инвентаризация сохранена</string>
    <string name="inventory_diff_line">%1$s: %2$s → %3$s (%4$s)</string>
</resources>
EOF_APP_SRC_MAIN_RES_VALUES_RU_STRINGS_XML
echo "OK: app/src/main/res/values-ru/strings.xml"

mkdir -p "$(dirname "app/src/main/res/values-pl/strings.xml")"
cat > app/src/main/res/values-pl/strings.xml << 'EOF_APP_SRC_MAIN_RES_VALUES_PL_STRINGS_XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">FinArs</string>
    <string name="app_subtitle">FinArs</string>
    <string name="add_income">Dodaj przychód</string>
    <string name="add_expense">Dodaj wydatek</string>
    <string name="add_entry">Dodaj +</string>
    <string name="balance">Bilans</string>
    <string name="enter_amount">Kwota</string>
    <string name="enter_comment">Komentarz</string>
    <string name="entry_date_label">Data transakcji</string>
    <string name="attach_receipt">Dołącz paragon</string>
    <string name="save">Zapisz</string>
    <string name="settings">Ustawienia</string>
    <string name="tax_percent">Procent podatku</string>
    <string name="other_income_label">Inne przychody (%1$d)</string>
    <string name="tax_scale_title">Podatek liczony jest automatycznie</string>
    <string name="tax_scale_description" formatted="false">0% do 30 000 zł/rok · 12% od kwoty od 30 000 do 120 000 zł · 32% od kwoty powyżej 120 000 zł. Stawka dotyczy tylko części ponad każdy próg, a nie całej kwoty.</string>
    <string name="other_income_title">Inne przychody</string>
    <string name="other_income_hint">Twój łączny dochód podlegający opodatkowaniu w tym roku z innych źródeł (etat, inna działalność itd.). Uwzględniany razem z dochodem z tej aplikacji przy sprawdzaniu rocznego limitu wolnego od podatku 30 000 zł.</string>
    <string name="saved">Zapisano</string>
    <string name="auto_tax_button">Oblicz automatycznie</string>
    <string name="auto_tax_result" formatted="false">Sugerowana stawka: %1$.1f% (wg skali PIT: 12% do 120 000 zł/rok, 32% powyżej). Przed zapisaniem można poprawić ręcznie.</string>
    <string name="export_report">Eksportuj raport</string>
    <string name="generate_report">Generuj raport</string>
    <string name="select_period">Wybierz okres</string>
    <string name="month">Miesiąc</string>
    <string name="year">Rok</string>
    <string name="custom_range">Zakres niestandardowy</string>
    <string name="from">Od</string>
    <string name="to">Do</string>
    <string name="no_entries">Brak wpisów</string>
    <string name="search_no_results">Nic nie znaleziono</string>
    <string name="history_search_hint">Szukaj po komentarzu lub kwocie</string>
    <string name="invoice_search_hint">Szukaj po numerze, kliencie lub kwocie</string>
    <string name="filter_date_range">Zakres dat</string>
    <string name="filter_clear">Wyczyść filtry</string>

    <string name="statistics">Statystyka</string>
    <string name="stat_income">Przychód</string>
    <string name="stat_expense">Wydatek</string>
    <string name="stat_profit">Zysk (brutto)</string>
    <string name="stat_tax_format" formatted="false">Podatek (%1$.1f%)</string>

    <string name="report_col_date">Data</string>
    <string name="report_col_income">Przychód</string>
    <string name="report_col_expense">Wydatek</string>
    <string name="report_col_tax_percent" formatted="false">Podatek %</string>
    <string name="report_col_tax_amount">Kwota podatku</string>
    <string name="report_col_comment">Komentarz</string>
    <string name="report_sheet_name">Raport</string>
    <string name="report_title_month">Raport — Miesiąc</string>
    <string name="report_title_year">Raport — Rok</string>
    <string name="report_title_custom">Raport — Zakres niestandardowy</string>
    <string name="custom_range_invalid">Data końcowa musi być późniejsza niż data początkowa</string>
    <string name="report_total_income">Suma przychodów</string>
    <string name="report_total_expense">Suma wydatków</string>
    <string name="report_total_profit">Suma zysku</string>
    <string name="report_total_tax">Suma podatku</string>
    <string name="report_total_net_profit">Zysk netto (po podatku)</string>
    <string name="report_generating">Generuję raport…</string>
    <string name="report_ready">Raport gotowy</string>
    <string name="report_share_title">Udostępnij raport</string>
    <string name="report_error">Błąd generowania raportu: %1$s</string>
    <string name="about_app">O aplikacji</string>
    <string name="about_description">FinArs to kompleksowa aplikacja do zarządzania finansami działalności nierejestrowanej i jednoosobowej działalności gospodarczej (JDG). Śledź przychody i wydatki, kontroluj limity, automatycznie licz podatki, wystawiaj faktury i generuj gotowe raporty oraz deklaracje PIT — wszystko w jednym miejscu, z pełną historią operacji zawsze pod ręką.\n\n\uD83D\uDCCA Finanse i podatki\n\uD83D\uDCB0 Ewidencja przychodów i wydatków z załącznikami paragonów\n\uD83D\uDCC8 Automatyczne obliczanie zysku i podatku (skala 12%/32%, liniowy 19%, ryczałt)\n\uD83D\uDD01 Transakcje cykliczne (czynsz, abonamenty) tworzone automatycznie co miesiąc\n\uD83D\uDEA6 Kontrola limitów: działalność nierejestrowana, próg 120 000 zł, zwolnienie z VAT (200 000 zł)\n\uD83D\uDD14 Powiadomienia o zbliżających się i przekroczonych limitach\n\n\uD83E\uDDFE Faktury i rachunki (Pro)\n\uD83D\uDCDD Wystawianie faktur/rachunków dla osób fizycznych i firm z generowaniem PDF\n\u2705 Statusy: Zapłacona / Oczekuje na zapłatę / Zaległa, plus przypomnienia o terminie płatności\n\uD83D\uDCB5 Kontrola rocznego limitu gotówki (20 000 zł) dla sprzedaży osobom fizycznym\n\uD83D\uDD0D Historia faktur z wyszukiwaniem i filtrami\n\n\uD83D\uDCC4 Raporty i deklaracje\n\uD83D\uDCCA Wykres przychodów i wydatków za ostatnie 6 miesięcy\n\uD83D\uDCE5 Eksport raportu miesięcznego (bezpłatnie), rocznego i za dowolny okres (Pro) do Excela wraz z paragonami\n\uD83E\uDDEE Generowanie deklaracji PIT-36 / PIT-36L / PIT-28 — pomocniczy PDF oraz wypełnienie oficjalnego formularza (Pro)\n\n\uD83D\uDD12 Bezpieczeństwo i wygoda\n\uD83D\uDD10 Blokada aplikacji kodem PIN oraz odciskiem palca / twarzą\n\uD83D\uDCBE Kopia zapasowa i przywracanie danych (Pro)\n\uD83C\uDF19 Nowoczesny ciemny interfejs\n\uD83C\uDF0D Dostępne w języku polskim, rosyjskim i angielskim\n\uD83D\uDD12 Wszystkie dane są przechowywane lokalnie na urządzeniu\n\nKontakt: p.arsenii@interia.pl</string>
    <string name="about_email">p.arsenii@interia.pl</string>
    <string name="dialog_close">Zamknij</string>
    <string name="dialog_write">Napisz</string>
    <string name="pro_status_locked">Pro jest zablokowane. Odblokuj, aby uzyskać roczne i niestandardowe raporty Excel, kopię zapasową i przywracanie danych oraz usunąć reklamy.</string>
    <string name="pro_status_active">Pro odblokowane. Dziękujemy za wsparcie!</string>
    <string name="pro_unlock_button">Odblokuj Pro</string>
    <string name="pro_unlock_button_price">Odblokuj Pro — %1$s</string>
    <string name="pro_loading">Ładowanie ceny…</string>
    <string name="pro_feature_locked_title">Funkcja Pro</string>
    <string name="pro_feature_locked_message">Raporty roczne i niestandardowe są dostępne tylko w wersji Pro. Odblokuj Pro w ustawieniach.</string>
    <string name="pro_feature_locked_go_settings">Przejdź do ustawień</string>
    <string name="invoice_pro_locked_message">Wystawianie faktur jest dostępne tylko w wersji Pro. Odblokuj Pro w ustawieniach.</string>
    <string name="backup_pro_locked_message">Kopia zapasowa i przywracanie to funkcja Pro. Odblokuj Pro, aby zabezpieczyć swoje dane plikiem kopii zapasowej.</string>
    <string name="pro_purchase_error">Nie udało się otworzyć zakupu. Sprawdź połączenie i spróbuj ponownie.</string>
    <string name="pro_info_title">Wersja Pro</string>
    <string name="pro_info_message">Pro odblokowuje:\n\n\u2022 Wystawianie faktur i rachunków (PDF)\n\u2022 Raport roczny w Excelu\n\u2022 Raport za dowolny okres\n\u2022 Generowanie deklaracji PIT-36 / PIT-36L / PIT-28\n\u2022 Kopia zapasowa i przywracanie danych\n\u2022 Brak reklam\n\nTo jednorazowy zakup — płacisz raz, dostęp zostaje na zawsze.</string>
    <string name="pro_info_continue">Przejdź do zakupu</string>
    <string name="enter_code_button">Masz kod?</string>
    <string name="enter_code_title">Wprowadź kod</string>
    <string name="enter_code_hint">Kod</string>
    <string name="enter_code_apply">Zastosuj</string>
    <string name="enter_code_wrong">Nieprawidłowy kod</string>
    <string name="enter_code_success">Pro odblokowane</string>
    <string name="transaction_history">Historia transakcji</string>
    <string name="stat_net_profit">Zysk netto (po podatku)</string>
    <string name="type_income">Przychód</string>
    <string name="type_expense">Wydatek</string>
    <string name="edit_income_title">Edytuj przychód</string>
    <string name="edit_expense_title">Edytuj wydatek</string>
    <string name="delete_entry">Usuń</string>
    <string name="delete_confirm_title">Usunąć wpis?</string>
    <string name="delete_confirm_message">Wpis zostanie trwale usunięty. Tej czynności nie można cofnąć.</string>
    <string name="delete_confirm_yes">Usuń</string>
    <string name="entry_updated">Zaktualizowano</string>
    <string name="entry_deleted">Usunięto</string>
    <string name="clear_all_button">Wyczyść wszystkie dane</string>
    <string name="clear_all_confirm_title">Na pewno?</string>
    <string name="clear_all_confirm_message">Wszystkie przychody i wydatki zostaną trwale usunięte. Tej czynności nie można cofnąć.</string>
    <string name="clear_all_confirm_yes">Usuń wszystko</string>
    <string name="clear_all_done">Wszystkie dane zostały usunięte</string>

    <string name="settings_menu_tax">Podatek i limity</string>
    <string name="settings_menu_language">Język</string>
    <string name="settings_menu_backup">Kopia zapasowa (Pro)</string>
    <string name="settings_menu_pro">Wersja Pro</string>

    <string name="backup_hint">Zapisz kopię zapasową przychodów/wydatków — kwoty, daty, komentarze i załączone zdjęcia paragonów — jako plik. W oknie zapisu możesz wybrać pamięć telefonu lub Dysk Google (jeśli aplikacja Dysku jest zainstalowana). Przechowuj ten plik w bezpiecznym miejscu — to jedyny sposób odzyskania danych w razie utraty telefonu lub reinstalacji aplikacji.</string>
    <string name="backup_in_progress">Trwa…</string>
    <string name="backup_create">Utwórz kopię zapasową</string>
    <string name="backup_restore">Przywróć z kopii</string>
    <string name="backup_success">Kopia zapisana (%1$d wpisów)</string>
    <string name="backup_error">Błąd: %1$s</string>
    <string name="backup_restore_confirm_title">Przywrócić z kopii?</string>
    <string name="backup_restore_confirm_message">Wpisy z pliku kopii zostaną dodane do tych, które już są na tym urządzeniu (istniejące wpisy nie są usuwane ani nadpisywane). Jeśli potrzebujesz "czystego" przywrócenia — najpierw użyj "Wyczyść wszystkie dane", a potem przywróć kopię.</string>
    <string name="backup_invalid_file">To nie wygląda na poprawny plik kopii zapasowej FinArs</string>
    <string name="backup_restored">Przywrócono wpisów: %1$d</string>
    <string name="backup_never">Ostatnia kopia: nigdy</string>
    <string name="backup_last_time">Ostatnia kopia: %1$s</string>

    <string name="settings_menu_security">Bezpieczeństwo (PIN / odcisk palca)</string>
    <string name="settings_menu_pit36">Generuj PIT (Pro)</string>
    <string name="pit36_pro_locked_message">Generowanie PIT-36 to funkcja Pro. Odblokuj Pro w Ustawieniach, aby z niej skorzystać.</string>

    <string name="lock_title">FinArs jest zablokowany</string>
    <string name="lock_subtitle">Wpisz PIN, aby kontynuować</string>
    <string name="lock_pin_hint">PIN</string>
    <string name="lock_wrong_pin">Błędny PIN, spróbuj ponownie</string>
    <string name="lock_unlock_button">Odblokuj</string>
    <string name="lock_biometric_button">Użyj odcisku palca / twarzy</string>
    <string name="lock_biometric_prompt_title">Odblokuj FinArs</string>
    <string name="lock_biometric_prompt_subtitle">Potwierdź odciskiem palca lub twarzą</string>
    <string name="lock_use_pin">Użyj PIN-u</string>
    <string name="lock_biometric_unavailable">Na tym urządzeniu nie skonfigurowano odcisku palca/twarzy. Dodaj go najpierw w ustawieniach telefonu.</string>

    <string name="security_hint">Zabezpiecz aplikację kodem PIN. Gdy funkcja jest włączona, FinArs poprosi o PIN za każdym razem, gdy wrócisz do aplikacji po jej opuszczeniu. Możesz też włączyć odblokowanie odciskiem palca/twarzą jako szybki skrót zamiast wpisywania tego samego PIN-u.</string>
    <string name="security_pin_switch">Wymagaj PIN-u przy otwieraniu aplikacji</string>
    <string name="security_change_pin">Zmień PIN</string>
    <string name="security_biometric_switch">Odblokowanie odciskiem palca / twarzą</string>
    <string name="security_set_pin_title">Ustaw PIN</string>
    <string name="security_set_pin_message">Wybierz PIN z 4–6 cyfr</string>
    <string name="security_continue">Dalej</string>
    <string name="security_pin_length_error">PIN musi mieć 4–6 cyfr</string>
    <string name="security_confirm_pin_title">Potwierdź PIN</string>
    <string name="security_pin_saved">PIN zapisany</string>
    <string name="security_pin_mismatch">PIN-y się nie zgadzają, spróbuj ponownie</string>
    <string name="security_disable_pin_title">Wpisz aktualny PIN</string>
    <string name="security_enter_current_pin">Wpisz aktualny PIN, aby kontynuować</string>
    <string name="security_pin_disabled">Ochrona PIN-em wyłączona</string>

    <string name="pit_data_title">Dane osobowe do zeznania podatkowego</string>
    <string name="pit_data_hint">Używane wyłącznie do wypełnienia pomocniczego raportu PIT (PIT-36 / PIT-36L / PIT-28 — zależnie od rodzaju działalności). Wszystko zostaje na Twoim urządzeniu.</string>
    <string name="pit_first_name">Imię</string>
    <string name="pit_last_name">Nazwisko</string>
    <string name="pit_pesel">PESEL (opcjonalnie)</string>
    <string name="pit_street">Ulica</string>
    <string name="pit_house_number">Numer domu</string>
    <string name="pit_apartment_number">Numer mieszkania (opcjonalnie)</string>
    <string name="pit_voivodeship">Województwo</string>
    <string name="pit_county">Powiat</string>
    <string name="pit_commune">Gmina</string>
    <string name="pit_postal_code">Kod pocztowy</string>
    <string name="pit_city">Miejscowość</string>
    <string name="pit_tax_office">Urząd skarbowy</string>
    <string name="pit_reliefs_title">Ulgi i odliczenia (opcjonalnie)</string>
    <string name="pit_children_count">Liczba dzieci (ulga na dzieci)</string>
    <string name="pit_internet_relief">Ulga internetowa — poniesiony wydatek</string>
    <string name="pit_ikze">Wpłaty na IKZE</string>
    <string name="pit_donations">Darowizny</string>
    <string name="pit_joint_spouse">Rozliczenie wspólnie z małżonkiem</string>
    <string name="pit_spouse_data_title">Dane osobowe małżonka</string>
    <string name="pit_spouse_id_hint">NIP/PESEL małżonka</string>
    <string name="pit_spouse_first_name_hint">Imię małżonka</string>
    <string name="pit_spouse_last_name_hint">Nazwisko małżonka</string>
    <string name="pit_spouse_birth_date_hint">Data urodzenia (DD.MM.RRRR)</string>
    <string name="pit_spouse_income_hint">Dochód małżonka (opcjonalnie)</string>
    <string name="pit_data_required_error">Uzupełnij najpierw imię, nazwisko i urząd skarbowy</string>

    <string name="pit36_hint">Wybierz pełny rok kalendarzowy, sprawdź swoje dane osobowe, a następnie wygeneruj pomocniczy plik PDF z liczbami i wskazówkami do wypełnienia Twojej właściwej deklaracji na podatki.gov.pl (Twój e-PIT) lub na papierze.</string>
    <string name="pit_row_przychod">Przychód</string>
    <string name="pit_row_koszty">Koszty</string>
    <string name="pit_row_dochod">Dochód</string>
    <string name="pit_row_tax">Szacowany podatek</string>
    <string name="pit_data_status_missing">Dane osobowe nie zostały jeszcze uzupełnione — są wymagane przed wygenerowaniem raportu.</string>
    <string name="pit_data_status_ready">Dane osobowe gotowe: %1$s</string>
    <string name="pit_edit_data_button">Edytuj dane osobowe</string>
    <string name="pit36_generate_button">Wygeneruj pomocniczy PDF</string>
    <string name="pit36_disclaimer">Ten raport ma charakter wyłącznie informacyjny i nie jest oficjalnym formularzem, e-Deklaracją ani poradą podatkową. Zawsze zweryfikuj liczby przed złożeniem deklaracji.</string>
    <string name="pit36_calculating">Trwa obliczanie, chwila…</string>
    <string name="pit36_generated">Raport PDF wygenerowany</string>
    <string name="pit36_generate_official_button">Wypełnij oficjalny formularz (szablon 2025)</string>
    <string name="pit36_official_hint">Wypełnia prawdziwy urzędowy PDF %1$s(32)/2025: Twoje dane, adres i wiersz przychodów/kosztów działalności. Pozostałe źródła dochodu i odliczenia musisz uzupełnić samodzielnie — zobacz zastrzeżenie poniżej.</string>
    <string name="pit36_official_unsupported">Oficjalny wypełniony formularz jest dostępny tylko dla PIT-36 (skala). Twoja aktualna forma to %1$s — użyj przycisku „Wygeneruj pomocniczy PDF”.</string>
    <string name="pit36_official_generated">Oficjalny formularz PIT-36 wypełniony. Sprawdź sekcje E–K i dodaj inne dochody/odliczenia przed złożeniem.</string>

    <!-- Rodzaj działalności / zasady rejestracji -->
    <string name="activity_type_title">Rodzaj działalności</string>
    <string name="activity_type_hint">Wybierz, jak działasz — od tego zależy stosowany limit i to, którą deklarację złożysz.</string>
    <string name="activity_type_niezarejestrowana">Działalność nierejestrowana (bez JDG)</string>
    <string name="activity_type_niezarejestrowana_desc" formatted="false">Przychód nie może przekroczyć 75% minimalnego wynagrodzenia miesięcznie. W razie przekroczenia musisz zarejestrować JDG w ciągu 7 dni. Rozliczenie przez PIT-36, skala podatkowa.</string>
    <string name="activity_type_jdg_skala" formatted="false">Zarejestrowana JDG — skala 12% / 32% (PIT-36)</string>
    <string name="activity_type_jdg_liniowy" formatted="false">Zarejestrowana JDG — podatek liniowy 19% (PIT-36L)</string>
    <string name="activity_type_jdg_ryczalt">Zarejestrowana JDG — ryczałt (PIT-28)</string>
    <string name="ryczalt_rate_label" formatted="false">Stawka ryczałtu dla Twojej działalności (%, zależy od PKD)</string>
    <string name="ryczalt_rate_hint">np. 3, 5.5, 8.5, 12, 17</string>
    <string name="min_wage_label">Minimalne wynagrodzenie miesięczne (zł) — do obliczenia limitu działalności nierejestrowanej</string>
    <string name="monthly_limit_preview" formatted="false">Limit miesięczny (75%): %1$,.2f zł</string>

    <!-- Wskaźniki limitów na ekranie głównym -->
    <string name="limits_title">Limity</string>
    <string name="limit_monthly_label">Działalność nierejestrowana, ten miesiąc: %1$s / %2$s zł</string>
    <string name="limit_bracket_label">Pierwszy próg podatkowy (120 000 zł/rok): %1$s / %2$s zł</string>
    <string name="limit_vat_label">Zwolnienie z VAT (200 000 zł/rok): %1$s / %2$s zł</string>
    <string name="limit_exceeded_warning">Przekroczono limit działalności nierejestrowanej! Musisz zarejestrować JDG w ciągu 7 dni.</string>

    <!-- Dynamiczna etykieta podatku -->
    <string name="tax_label_zero" formatted="false">Podatek (0% — kwota wolna)</string>
    <string name="tax_label_12" formatted="false">Podatek (12%)</string>
    <string name="tax_label_32" formatted="false">Podatek (próg 32%)</string>
    <string name="tax_label_progressive" formatted="false">Podatek (skala progresywna 12% / 32%)</string>
    <string name="tax_label_liniowy" formatted="false">Podatek (liniowy 19%)</string>
    <string name="tax_label_ryczalt">Podatek (ryczałt, od przychodu)</string>
    <string name="pit_form_applicable">Właściwa deklaracja: %1$s</string>

    <!-- Tabela historii -->
    <string name="history_col_receipt">Paragon</string>
    <string name="history_col_amount">Kwota</string>

    <!-- Kolumny raportu -->
    <string name="report_col_receipt">Paragon</string>
    <string name="report_receipt_yes">Tak</string>

    <!-- Powiadomienia -->
    <string name="notif_channel_name">Limity i terminy</string>
    <string name="notif_channel_description">Powiadomienia o limitach działalności i terminach podatkowych</string>
    <string name="notif_limit_exceeded_title">Przekroczono limit działalności nierejestrowanej</string>
    <string name="notif_limit_exceeded_text" formatted="false">Przychód w tym miesiącu przekracza 75% minimalnego wynagrodzenia. Zarejestruj JDG w ciągu 7 dni.</string>
    <string name="notif_limit_95_title" formatted="false">Osiągnięto 95% limitu miesięcznego</string>
    <string name="notif_limit_95_text">Jesteś bardzo blisko limitu działalności nierejestrowanej na ten miesiąc.</string>
    <string name="notif_limit_80_title" formatted="false">Osiągnięto 80% limitu miesięcznego</string>
    <string name="notif_limit_80_text" formatted="false">Wykorzystano 80% limitu działalności nierejestrowanej na ten miesiąc.</string>
    <string name="notif_bracket_title">Zbliżasz się do progu 120 000 zł</string>
    <string name="notif_bracket_text" formatted="false">Roczny dochód zbliża się do 120 000 zł — nadwyżka będzie opodatkowana stawką 32% zamiast 12%.</string>
    <string name="notif_vat_title">Zbliżasz się do limitu zwolnienia z VAT</string>
    <string name="notif_vat_text">Roczny przychód zbliża się do 200 000 zł — progu zwolnienia z VAT.</string>
    <string name="notif_advance_title">Przypomnienie o zaliczce na podatek</string>
    <string name="notif_advance_text">Zaliczki na podatek należy wpłacać do 20 dnia każdego miesiąca.</string>
    <string name="notif_pit_deadline_title">Przypomnienie o rocznym zeznaniu podatkowym</string>
    <string name="notif_pit_deadline_text">Roczne zeznania podatkowe składa się od 15 lutego do 30 kwietnia.</string>
    <string name="terms_title">Regulamin</string>
    <string name="terms_full_text">Regulamin i wyłączenie odpowiedzialności (Terms of Service &amp; Legal Disclaimer)\n\nKlikając „Akceptuję”, potwierdzasz, że przeczytałeś/aś, zrozumiałeś/aś i w pełni akceptujesz warunki niniejszego regulaminu. Jeśli się nie zgadzasz, nie masz prawa korzystać z aplikacji FinArs.\n\n1. Wyłączenie usług księgowych i prawnych\n— Aplikacja FinArs jest wyłącznie narzędziem (kalkulatorem i organizerem danych).\n— Aplikacja, jej twórcy i właściciele NIE są akredytowanym biurem rachunkowym, doradcą podatkowym ani kancelarią prawną.\n— Wszystkie obliczenia i automatyczne generowanie deklaracji (PIT-36, PIT-36L, PIT-28) mają charakter wyłącznie informacyjny.\n\n2. Odpowiedzialność za dane\nUżytkownik ponosi pełną odpowiedzialność za poprawność wprowadzanych danych, weryfikację obliczeń i formularzy PDF przed złożeniem do urzędu skarbowego oraz za terminowość rozliczeń.\n\n3. Ograniczenie odpowiedzialności\nAplikacja jest dostarczana „tak jak jest”, bez żadnych gwarancji. Twórca nie odpowiada za kary, zaległości podatkowe, błędy algorytmów ani utratę danych na urządzeniu.\n\n4. Zmiany w przepisach\nPrzepisy podatkowe RP ulegają zmianom — zalecana jest weryfikacja na podatki.gov.pl lub u licencjonowanego księgowego.\n\n5. Poufność danych\nWszystkie dane i pliki PDF są przechowywane lokalnie na urządzeniu użytkownika.\n\n6. Prawo właściwe\nZastosowanie ma prawo Rzeczypospolitej Polskiej.\n\n7. Wycofanie zgody\nRegulamin akceptowany jest jednorazowo przy pierwszym uruchomieniu. Brak zgody oznacza obowiązek zaprzestania korzystania z aplikacji i jej usunięcia.</string>
    <string name="terms_checkbox_label">Przeczytałem/am i akceptuję regulamin</string>
    <string name="terms_accept_button">Akceptuję i kontynuuję</string>
    <string name="terms_status_accepted">Status: Regulamin zaakceptowano (%1$s)</string>
    <string name="terms_status_unknown">Status: Regulamin zaakceptowano</string>
    <string name="settings_menu_terms">Regulamin</string>


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

    <!-- Historia faktur -->
    <string name="invoice_history_title">Historia faktur</string>
    <string name="no_invoices">Nie wystawiono jeszcze żadnych faktur</string>


    <!-- Etykiety PDF faktury -->
    <string name="invoice_pdf_faktura">FAKTURA</string>
    <string name="invoice_pdf_rachunek">RACHUNEK</string>
    <string name="invoice_pdf_issue_date">Data wystawienia</string>
    <string name="invoice_pdf_sale_date">Data sprzedaży</string>
    <string name="invoice_pdf_seller">Sprzedawca</string>
    <string name="invoice_pdf_buyer">Nabywca</string>
    <string name="invoice_pdf_nip">NIP</string>
    <string name="invoice_pdf_bank_account">Konto</string>
    <string name="invoice_pdf_buyer_private">Osoba fizyczna nieprowadząca działalności gospodarczej (bez NIP).</string>
    <string name="invoice_pdf_table_lp">Lp</string>
    <string name="invoice_pdf_table_name">Nazwa towaru/usługi</string>
    <string name="invoice_pdf_table_unit">Jedn.</string>
    <string name="invoice_pdf_table_qty">Ilość</string>
    <string name="invoice_pdf_table_price">Cena</string>
    <string name="invoice_pdf_table_total">Razem</string>
    <string name="invoice_pdf_unit_piece">szt</string>
    <string name="invoice_pdf_sum_label">Łącznie</string>
    <string name="invoice_pdf_paid_stamp">ZAPŁACONO</string>
    <string name="invoice_pdf_payment_date">Data zapłaty</string>
    <string name="invoice_pdf_footer">Dokument wygenerowany w aplikacji FinArs. Nie stanowi oficjalnej porady księgowej ani podatkowej — w razie wątpliwości skonsultuj się z doradcą podatkowym.</string>
    <string name="seller_bank_account">Numer konta (opcjonalnie)</string>
    <string name="delete_invoice_confirm_title">Usunąć fakturę?</string>
    <string name="delete_invoice_confirm_message">Wpis oraz plik PDF faktury zostaną trwale usunięte. Tej operacji nie można cofnąć.</string>
    <string name="invoice_deleted">Faktura usunięta</string>

    <string name="invoice_status_paid">Zapłacona</string>
    <string name="invoice_status_pending">Oczekuje na zapłatę</string>
    <string name="invoice_status_overdue">Zaległa</string>
    <string name="invoice_paid_switch_label">Zapłacona</string>
    <string name="invoice_due_date_label">Termin płatności</string>
    <string name="notif_invoice_overdue_title">Zaległa faktura</string>
    <string name="notif_invoice_overdue_text">Faktura nr %2$d dla %1$s jest zaległa.</string>
    <string name="notif_invoice_due_soon_title">Zbliża się termin płatności</string>
    <string name="notif_invoice_due_soon_text">Termin płatności faktury nr %2$d dla %1$s upływa w ciągu 3 dni.</string>
    <string name="recurring_switch_label">Powtarzaj co miesiąc</string>
    <string name="chart_title">Przychody i wydatki — ostatnie 6 miesięcy</string>
    <string name="invoice_status_filter_all">Wszystkie</string>

    <string name="invoice_pdf_pending_stamp">OCZEKUJE NA ZAPŁATĘ</string>

    <!-- Update 41: rodzaj działalności, magazyn, kody kreskowe, OCR paragonów -->
    <string name="settings_menu_business">Typ sprzedaży (towar/usługa)</string>
    <string name="business_kind_title">Typ sprzedaży (towar/usługa)</string>
    <string name="business_kind_description">Wybierz to, co najlepiej pasuje do Twojej działalności. Przy wyborze \"Sprzedaż\" lub \"Mieszana\" na ekranie głównym pojawi się przycisk \"Magazyn\".</string>
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
    <string name="product_low_stock">Próg \"kończy się\"</string>
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

    <!-- Update 41 fix 6 -->
    <string name="invoice_mark_paid_confirm_title">Oznaczyć jako opłaconą?</string>
    <string name="invoice_mark_paid_confirm_message">Status faktury zmieni się na „opłacona” z dzisiejszą datą, a zapisany plik PDF zostanie zaktualizowany, by odzwierciedlić nowy status.</string>
    <string name="invoice_marked_paid_toast">Faktura oznaczona jako opłacona</string>
    <string name="invoice_marked_paid_pdf_warning">Status zaktualizowany, ale nie udało się odświeżyć pliku PDF</string>

    <!-- Update 42: inwentaryzacja magazynu + lepsze skanowanie paragonów -->
    <string name="start_inventory">Zrób inwentaryzację</string>
    <string name="inventory_title">Inwentaryzacja magazynu</string>
    <string name="inventory_hint">Sprawdź faktyczną ilość każdego produktu. Zaktualizowane zostaną tylko zmienione pozycje.</string>
    <string name="inventory_current_stock">W systemie: %1$s %2$s</string>
    <string name="inventory_save">Zapisz inwentaryzację</string>
    <string name="inventory_no_changes">Nie znaleziono różnic, nic się nie zmieniło</string>
    <string name="inventory_saved_title">Inwentaryzacja zapisana</string>
    <string name="inventory_diff_line">%1$s: %2$s → %3$s (%4$s)</string>
</resources>
EOF_APP_SRC_MAIN_RES_VALUES_PL_STRINGS_XML
echo "OK: app/src/main/res/values-pl/strings.xml"

mkdir -p "$(dirname "app/src/main/AndroidManifest.xml")"
cat > app/src/main/AndroidManifest.xml << 'EOF_APP_SRC_MAIN_ANDROIDMANIFEST_XML'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />

    <application
        android:name=".FaApp"
        android:allowBackup="true"
        android:label="@string/app_name"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:theme="@style/Theme.FA">

        <!-- ЗАМЕНИТЬ на реальный AdMob App ID из консоли AdMob (Apps -> Ваше приложение -> App settings) -->
        <meta-data
            android:name="com.google.android.gms.ads.APPLICATION_ID"
            android:value="ca-app-pub-9218963926031039~6835956339" />

        <activity android:name=".TermsActivity" android:exported="false" />
        <activity android:name=".SettingsActivity" android:exported="false" />
        <activity android:name=".SettingsProActivity" android:exported="false" />
        <activity android:name=".SettingsBackupActivity" android:exported="false" />
        <activity android:name=".SettingsLanguageActivity" android:exported="false" />
        <activity android:name=".SettingsTaxActivity" android:exported="false" />
        <activity android:name=".SettingsSecurityActivity" android:exported="false" />
        <activity android:name=".LockActivity" android:exported="false"
            android:launchMode="singleTask" android:excludeFromRecents="true" />
        <activity android:name=".PitDataActivity" android:exported="false" />
        <activity android:name=".Pit36Activity" android:exported="false" />
        <activity android:name=".AddEntryActivity" android:exported="false" />
        <activity android:name=".AddInvoiceActivity" android:exported="false" />
        <activity android:name=".InvoiceHistoryActivity" android:exported="false" />
        <activity android:name=".ReportActivity" android:exported="false" />
        <activity android:name=".HistoryActivity" android:exported="false" />
        <activity android:name=".SettingsBusinessActivity" android:exported="false" />
        <activity android:name=".MagazinActivity" android:exported="false" />
        <activity android:name=".InventoryActivity" android:exported="false" />
        <activity android:name=".AddEditProductActivity" android:exported="false" />
        <activity android:name=".SelectProductsActivity" android:exported="false" />
        <activity android:name=".MineActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths" />
        </provider>
    </application>
</manifest>
EOF_APP_SRC_MAIN_ANDROIDMANIFEST_XML
echo "OK: app/src/main/AndroidManifest.xml"

echo ""
echo "=== Готово ==="
echo "Дальше: gradlew assembleDebug (или сборка через Android Studio/CI)."
echo "База данных мигрирует автоматически (v4 -> v5), данные не теряются."
echo "Бэкап старых файлов лежит в $BACKUP_DIR — если что-то пойдёт не так, можно откатить вручную."
