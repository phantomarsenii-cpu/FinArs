#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=== Обновление 48: лимит VAT (240 000 zl), kasa fiskalna, stawki VAT na fakturze, logo, czestotliwosc push ==="
echo "Co sie zmienia:"
echo " 1) Po przekroczeniu rocznego limitu zwolnienia z VAT (240 000 zl) w Ustawieniach"
echo "    -> Podatki pojawia sie czerwona sekcja z checkboxem \"Potwierdzam rejestracje VAT\"."
echo "    Zaznaczenie zapisuje sie JEDNORAZOWO (dialog potwierdzajacy) i nie da sie"
echo "    tego cofnac w aplikacji - checkbox staje sie zablokowany, pokazuje sam status."
echo "    Dopoki nie potwierdzisz - wystawianie faktur jest CALKOWICIE zablokowane"
echo "    (czerwony baner + wylaczony przycisk Generuj PDF na ekranie faktury)."
echo " 2) To samo dla limitu 20 000 zl sprzedazy gotowkowej dla osob fizycznych ->"
echo "    checkbox \"Potwierdzam posiadanie kasy fiskalnej\", tez jednorazowy."
echo " 3) Po potwierdzeniu rejestracji VAT kazda faktura wymaga wyboru stawki VAT"
echo "    (23% / 8% / 5% / 0% / zw / np) - bez wyboru nie da sie wygenerowac PDF."
echo "    Stawka nalicza sie automatycznie, tabela w PDF pokazuje Cene/Wartosc netto,"
echo "    Stawke VAT, Kwote VAT i Wartosc brutto (jak w oficjalnym wzorze faktury VAT)."
echo " 4) Po potwierdzeniu kasy fiskalnej na ekranie faktury pojawia sie przelacznik"
echo "    \"Do paragonu\" - oznacza fakture jako wystawiona do paragonu (widoczne w PDF)."
echo " 5) KAZDA wystawiona faktura (niezaleznie od rodzaju dzialalnosci) ma teraz"
echo "    logo aplikacji w prawym gornym rogu kazdej strony PDF."
echo " 6) Ustawienia -> Podatki: nowe pole \"Czestotliwosc powiadomien push\" (1-50/dzien)."
echo "    Krytyczne powiadomienia (przekroczony limit VAT/kasy, przeterminowane faktury)"
echo "    moga teraz powtarzac sie do wybranej liczby razy dziennie zamiast raz na dobe."
echo ""

if [ ! -f "settings.gradle" ] || [ ! -d "app/src/main/java/com/example/fa_ksiegowy" ]; then
    echo "!!! Uruchom skrypt z korzenia projektu (tam, gdzie jest settings.gradle)"
    exit 1
fi

if ! grep -q "applyBusinessKindUi" "app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt" 2>/dev/null; then
    echo "!!! Nie znaleziono applyBusinessKindUi w AddInvoiceActivity.kt — najpierw zastosuj update_project-47"
    exit 1
fi

if grep -q "vatRate" "app/src/main/java/com/example/fa_ksiegowy/Invoice.kt" 2>/dev/null; then
    echo "!!! Wyglada na to, ze update_project-48 zostal juz zastosowany (Invoice.kt ma juz pole vatRate)"
    exit 1
fi

BACKUP_DIR=".update48_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
for f in \
    "app/src/main/java/com/example/fa_ksiegowy/VatRate.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/VatComplianceHelper.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/Invoice.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/AppDatabase.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/InvoicePdfGenerator.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/SettingsTaxActivity.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/LimitsNotificationWorker.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/InvoiceReminderWorker.kt" \
    "app/src/main/res/layout/activity_add_invoice.xml" \
    "app/src/main/res/layout/activity_settings_tax.xml" \
    "app/src/main/res/values/strings.xml" \
    "app/src/main/res/values-pl/strings.xml" \
    "app/src/main/res/values-ru/strings.xml"
do
    if [ -f "$f" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$f")"
        cp "$f" "$BACKUP_DIR/$f"
    fi
done
echo "--- Backup zmienianych plikow zapisany w $BACKUP_DIR ---"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/VatRate.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/VatRate.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_VATRATE_KT'
package com.example.fa_ksiegowy

/**
 * Stawka VAT wybierana przez użytkownika przy wystawianiu faktury, gdy
 * sprzedawca jest już zarejestrowanym podatnikiem VAT (patrz
 * [VatComplianceHelper]). Przechowywana w [Invoice.vatRate] jako storageKey.
 */
enum class VatRate(val storageKey: String, val percent: Double?) {
    RATE_23("23", 23.0),
    RATE_8("8", 8.0),
    RATE_5("5", 5.0),
    RATE_0("0", 0.0),
    ZW("zw", null),
    NP("np", null);

    val labelResId: Int
        get() = when (this) {
            RATE_23 -> R.string.vat_rate_23
            RATE_8 -> R.string.vat_rate_8
            RATE_5 -> R.string.vat_rate_5
            RATE_0 -> R.string.vat_rate_0
            ZW -> R.string.vat_rate_zw
            NP -> R.string.vat_rate_np
        }

    /** Kwota VAT dla podanej wartości netto (0 dla zw./np., gdzie procent nie istnieje). */
    fun vatAmount(netAmount: Double): Double = (percent ?: 0.0) / 100.0 * netAmount

    companion object {
        fun fromStorageKeyOrNull(key: String?): VatRate? = entries.find { it.storageKey == key }
    }
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_VATRATE_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/VatRate.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/VatComplianceHelper.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/VatComplianceHelper.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_VATCOMPLIANCEHELPER_KT'
package com.example.fa_ksiegowy

import android.content.Context
import android.content.SharedPreferences

/**
 * Kontrola dwóch jednorazowych potwierdzeń, które użytkownik musi zaznaczyć
 * w Ustawieniach po przekroczeniu odpowiednich limitów, zanim będzie mógł
 * dalej wystawiać faktury:
 *
 *  1) VAT_REGISTERED — po przekroczeniu rocznego limitu zwolnienia
 *     podmiotowego z VAT (240 000 zł, zob. [LimitsHelper.VAT_EXEMPT_LIMIT])
 *     użytkownik musi złożyć VAT-R i potwierdzić rejestrację, zanim
 *     wystawi kolejną fakturę — od tego momentu każda faktura wymaga
 *     wyboru stawki VAT (zob. [VatRate]).
 *  2) KASA_FISKALNA — po przekroczeniu rocznego limitu 20 000 zł sprzedaży
 *     gotówkowej dla osób fizycznych (zob. [CashLimitHelper]) użytkownik
 *     musi potwierdzić posiadanie kasy fiskalnej.
 *
 * Oba potwierdzenia są ZAPISYWANE RAZ i nie można ich cofnąć z poziomu
 * aplikacji (checkbox w Ustawieniach staje się nieedytowalny po zaznaczeniu) —
 * to świadome zabezpieczenie przed przypadkowym „odznaczeniem" stanu prawnego,
 * który w rzeczywistości już nastąpił.
 */
object VatComplianceHelper {

    private const val KEY_VAT_REGISTERED = "vat_registered_confirmed"
    private const val KEY_KASA_FISKALNA = "kasa_fiskalna_confirmed"
    const val KEY_PUSH_FREQUENCY = "push_notif_per_day"
    const val DEFAULT_PUSH_FREQUENCY = 3

    fun isVatRegisteredConfirmed(prefs: SharedPreferences): Boolean =
        prefs.getBoolean(KEY_VAT_REGISTERED, false)

    /** Zapisuje potwierdzenie rejestracji VAT — jednorazowo, bez możliwości cofnięcia. */
    fun confirmVatRegistered(prefs: SharedPreferences) {
        prefs.edit().putBoolean(KEY_VAT_REGISTERED, true).apply()
    }

    fun isKasaFiskalnaConfirmed(prefs: SharedPreferences): Boolean =
        prefs.getBoolean(KEY_KASA_FISKALNA, false)

    /** Zapisuje potwierdzenie posiadania kasy fiskalnej — jednorazowo, bez możliwości cofnięcia. */
    fun confirmKasaFiskalna(prefs: SharedPreferences) {
        prefs.edit().putBoolean(KEY_KASA_FISKALNA, true).apply()
    }

    fun getPushFrequency(prefs: SharedPreferences): Int =
        prefs.getInt(KEY_PUSH_FREQUENCY, DEFAULT_PUSH_FREQUENCY).coerceIn(1, 50)

    fun setPushFrequency(prefs: SharedPreferences, perDay: Int) {
        prefs.edit().putInt(KEY_PUSH_FREQUENCY, perDay.coerceIn(1, 50)).apply()
    }

    /** Stan zgodności potrzebny na ekranie wystawiania faktury: czy limit VAT/kasy
     *  jest przekroczony i czy dotyczące go potwierdzenie zostało już złożone. */
    data class ComplianceStatus(
        val vatExceeded: Boolean,
        val vatConfirmed: Boolean,
        val cashExceeded: Boolean,
        val kasaConfirmed: Boolean
    ) {
        /** Wystawianie faktur jest zablokowane, dopóki brakującego potwierdzenia nie złożono. */
        val invoicingBlocked: Boolean
            get() = (vatExceeded && !vatConfirmed) || (cashExceeded && !kasaConfirmed)

        /** Czy sprzedawca jest już podatnikiem VAT — wymaga wyboru stawki na każdej fakturze. */
        val requiresVatRateSelection: Boolean get() = vatConfirmed

        /** Czy pokazać opcję „faktura do paragonu" — dostępna dopiero po potwierdzeniu kasy. */
        val allowsReceiptFlag: Boolean get() = kasaConfirmed
    }

    suspend fun computeStatus(context: Context): ComplianceStatus {
        val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
        val vatConfirmed = isVatRegisteredConfirmed(prefs)
        val kasaConfirmed = isKasaFiskalnaConfirmed(prefs)
        val limits = LimitsHelper.compute(context)
        val cash = CashLimitHelper.computeCurrentYear(context)
        return ComplianceStatus(
            vatExceeded = limits.vat.exceeded,
            vatConfirmed = vatConfirmed,
            cashExceeded = cash.exceeded,
            kasaConfirmed = kasaConfirmed
        )
    }
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_VATCOMPLIANCEHELPER_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/VatComplianceHelper.kt"

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
    val pdfFileName: String,

    /** Status opłacenia — PAID (domyślnie, zgodność wsteczna ze starymi rekordami) lub PENDING. */
    val status: InvoiceStatus = InvoiceStatus.PAID,
    /** Termin płatności — używany tylko gdy status = PENDING (przypomnienia, oznaczenie "zaległa"). */
    val dueDateMillis: Long? = null,

    /** Stawka VAT (storageKey [VatRate]) — wypełniana tylko gdy sprzedawca jest już
     *  zarejestrowanym podatnikiem VAT (zob. [VatComplianceHelper]). null oznacza
     *  fakturę wystawioną przed rejestracją VAT (zwolnienie podmiotowe). */
    val vatRate: String? = null,
    /** true, jeśli ta faktura jest jednocześnie wystawiana "do paragonu" z kasy
     *  fiskalnej (zob. [VatComplianceHelper.confirmKasaFiskalna]) — dotyczy tylko
     *  sprzedaży zarejestrowanej przez kasę fiskalną osobom fizycznym. */
    val isReceipt: Boolean = false
) {
    /** true, jeśli faktura oczekuje na zapłatę i termin już minął. Liczone na bieżąco, nie zapisywane w bazie. */
    val isOverdue: Boolean
        get() = status == InvoiceStatus.PENDING && dueDateMillis != null && dueDateMillis < System.currentTimeMillis()
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICE_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/Invoice.kt"

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
    entities = [Entry::class, Invoice::class, RecurringEntry::class, Product::class, InvoiceItem::class, InventoryRecord::class, InventorySession::class],
    version = 9,
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

    abstract fun inventorySessionDao(): InventorySessionDao

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

        /** v5 -> v6: инвентаризация теперь группируется в "сессии" (inventory_sessions,
         *  одна на каждый проведённый пересчёт склада) с сформированным PDF-отчётом;
         *  у записей расхождений (inventory_records) появляется привязка к сессии
         *  (sessionId) и снимок себестоимости товара на момент инвентаризации
         *  (priceNetAtInventory) — для расчёта денежной разницы. Обычная миграция,
         *  без потери уже накопленных данных склада/истории. */
        private val MIGRATION_5_6 = object : Migration(5, 6) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    "CREATE TABLE IF NOT EXISTS `inventory_sessions` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `number` INTEGER NOT NULL, `dateMillis` INTEGER NOT NULL, `pdfFilePath` TEXT NOT NULL, `totalProducts` INTEGER NOT NULL, `changedProducts` INTEGER NOT NULL, `diffValueNet` REAL NOT NULL)"
                )
                database.execSQL("ALTER TABLE inventory_records ADD COLUMN sessionId INTEGER NOT NULL DEFAULT 0")
                database.execSQL("ALTER TABLE inventory_records ADD COLUMN priceNetAtInventory REAL NOT NULL DEFAULT 0.0")
            }
        }

        /** v6 -> v7: у товара появляются цена продажи (priceSell) и наценка в % (marginPercent),
         *  цена продажи может задаваться либо вручную, либо через процент наценки от цены
         *  закупки — оба поля синхронизируются на экране редактирования товара. Для уже
         *  существующих товаров priceSell по умолчанию берётся равной текущей priceNet
         *  (закупка = продажа, наценка 0%), чтобы позиции фактур со склада не остались с
         *  нулевой ценой сразу после обновления. У записей инвентаризации (inventory_records)
         *  и сессий (inventory_sessions) появляется снимок цены продажи на момент проверки,
         *  чтобы в таблице расхождений показывать не только разницу по себестоимости, но и
         *  упущенную/лишнюю выручку по цене продажи. */
        private val MIGRATION_6_7 = object : Migration(6, 7) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL("ALTER TABLE products ADD COLUMN priceSell REAL NOT NULL DEFAULT 0.0")
                database.execSQL("ALTER TABLE products ADD COLUMN marginPercent REAL NOT NULL DEFAULT 0.0")
                database.execSQL("UPDATE products SET priceSell = priceNet")
                database.execSQL("ALTER TABLE inventory_records ADD COLUMN priceSellAtInventory REAL NOT NULL DEFAULT 0.0")
                database.execSQL("ALTER TABLE inventory_sessions ADD COLUMN diffValueSell REAL NOT NULL DEFAULT 0.0")
            }
        }

        /** v7 -> v8: ryczałt теперь считается не одной глобальной ставкой из настроек,
         *  а по КАЖДОЙ операции отдельно (см. RyczaltCategory) — один человек может
         *  одновременно продавать товары (3%/5,5%) и оказывать услуги (8,5%/12%/14%/17%).
         *  У доходов (entries) и позиций фактур (invoice_items) появляется необязательная
         *  привязка к категории; уже существующие записи остаются с NULL и по-прежнему
         *  считаются по старой единой ставке из настроек (см. TaxHelper.calcRyczaltByCategory) —
         *  обычная миграция, без потери накопленной истории. */
        private val MIGRATION_7_8 = object : Migration(7, 8) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL("ALTER TABLE entries ADD COLUMN ryczaltCategory TEXT")
                database.execSQL("ALTER TABLE invoice_items ADD COLUMN ryczaltCategory TEXT")
            }
        }

        /** v8 -> v9: po przekroczeniu limitu zwolnienia z VAT (240 000 zł) i potwierdzeniu
         *  rejestracji w Ustawieniach użytkownik wybiera stawkę VAT na każdej fakturze
         *  (vatRate) — zapisywana jako storageKey [VatRate]. Po potwierdzeniu posiadania
         *  kasy fiskalnej (limit 20 000 zł gotówki od osób fizycznych) faktura może być
         *  dodatkowo oznaczona jako wystawiona "do paragonu" (isReceipt). Obie kolumny są
         *  opcjonalne — dla wszystkich wcześniejszych faktur pozostają NULL/false, bez
         *  utraty już zapisanych danych. */
        private val MIGRATION_8_9 = object : Migration(8, 9) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL("ALTER TABLE invoices ADD COLUMN vatRate TEXT")
                database.execSQL("ALTER TABLE invoices ADD COLUMN isReceipt INTEGER NOT NULL DEFAULT 0")
            }
        }

        @Volatile private var INSTANCE: AppDatabase? = null
        fun getInstance(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "fa_ksiegowy.db"
                ).addMigrations(MIGRATION_3_4, MIGRATION_4_5, MIGRATION_5_6, MIGRATION_6_7, MIGRATION_7_8, MIGRATION_8_9).fallbackToDestructiveMigration().build().also { INSTANCE = it }
            }
        }
    }
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_APPDATABASE_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/AppDatabase.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_ADDINVOICEACTIVITY_KT'
package com.example.fa_ksiegowy

import android.app.DatePickerDialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
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
 * Pozycje "Usługa / towar" są teraz WIELOKROTNE (do MAX_ITEMS pozycji na jedną
 * fakturę) — każda pozycja to osobna karta z nazwą, ilością i ceną (zob.
 * item_invoice_line.xml / addItemRow), dodawana przyciskiem "+" (btn_add_item_row).
 * Jeśli użytkownik wybierze pozycje ze magazynu (btn_add_warehouse_items), są one
 * dopisywane do tego samego kontenera jako kolejne wiersze, a nie osobnym polem —
 * jedna faktura może więc jednocześnie zawierać towar dodany ze magazynu i ręcznie
 * wpisaną usługę. Gdy w ustawieniach wybrano ActivityType.JDG_RYCZALT, każda
 * pozycja ma dodatkowo wybór kategorii ryczałtu (zob. RyczaltCategory) — jedna
 * osoba może jednocześnie sprzedawać towary i świadczyć różne usługi z różnymi
 * stawkami, dlatego stawka jest właściwością pozycji, a nie jednego ustawienia.
 */
class AddInvoiceActivity : BaseActivity() {

    companion object {
        private const val MAX_ITEMS = 20
    }

    private var isPhysicalPerson: Boolean = true
    private var paymentMethod: PaymentMethod = PaymentMethod.CASH
    private var serviceDateMillis: Long = System.currentTimeMillis()
    private var paymentDateMillis: Long = System.currentTimeMillis()
    private var invoiceStatus: InvoiceStatus = InvoiceStatus.PAID
    private var dueDateMillis: Long = System.currentTimeMillis() + 14L * 24 * 60 * 60 * 1000
    private var lastSavedUri: Uri? = null

    /** Stan limitu VAT/kasy fiskalnej — odświeżany w onCreate/onResume (zob. refreshComplianceStatus). */
    private var compliance: VatComplianceHelper.ComplianceStatus? = null
    private var selectedVatRate: VatRate? = null

    private val activityType: ActivityType by lazy {
        ActivityTypeHelper.get(getSharedPreferences("settings", MODE_PRIVATE))
    }

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

        // Позиции фактуры: сразу одна пустая строка, дальше можно добавлять кнопкой "+".
        addItemRow()
        findViewById<Button>(R.id.btn_add_item_row).setOnClickListener { addItemRow() }

        findViewById<Button>(R.id.btn_generate).setOnClickListener { generateInvoice() }
        findViewById<Button>(R.id.btn_open_pdf).setOnClickListener { openLastPdf() }
        findViewById<Button>(R.id.btn_share).setOnClickListener { shareLastPdf() }
        findViewById<Button>(R.id.btn_open_folder).setOnClickListener { openInvoicesFolder() }
        findViewById<Button>(R.id.btn_invoice_history).setOnClickListener {
            startActivity(Intent(this, InvoiceHistoryActivity::class.java))
        }

        findViewById<Button>(R.id.btn_vat_rate).setOnClickListener { showVatRatePicker() }

        loadSellerData()
        refreshCashLimit()
        applyBusinessKindUi()
        refreshComplianceStatus()
    }

    override fun onResume() {
        super.onResume()
        // Настройка "Тип продаж" в Ustawieniach могла измениться, пока пользователь
        // был на другом экране — перепроверяем при каждом возврате.
        applyBusinessKindUi()
        // Потверждение регистрации VAT / posiadania kasy fiskalnej могло появиться
        // (или лимиты могли измениться), пока пользователь был в Ustawieniach —
        // перепроверяем блокировку и видимость stawki VAT при каждом возврате.
        refreshComplianceStatus()
    }

    /**
     * Проверяет, превышен ли лимит zwolnienia z VAT (240 000 zł) и лимит gotówki
     * dla osób fizycznych (20 000 zł), и подтверждены ли соответствующие статусы
     * в Ustawieniach (zob. VatComplianceHelper). Пока подтверждения не хватает —
     * выставление фактур полностью заблокировано (btn_generate отключена, показан
     * красный баннер). Если VAT уже подтверждён — показываем обязательный выбор
     * stawki VAT; если kasa fiskalna подтверждена — показываем переключатель
     * "Do paragonu".
     */
    private fun refreshComplianceStatus() {
        CoroutineScope(Dispatchers.IO).launch {
            val status = VatComplianceHelper.computeStatus(applicationContext)
            withContext(Dispatchers.Main) {
                compliance = status
                val banner = findViewById<TextView>(R.id.tv_compliance_block_banner)
                val btnGenerate = findViewById<Button>(R.id.btn_generate)
                if (status.invoicingBlocked) {
                    val messages = mutableListOf<String>()
                    if (status.vatExceeded && !status.vatConfirmed) messages.add(getString(R.string.vat_limit_block_message))
                    if (status.cashExceeded && !status.kasaConfirmed) messages.add(getString(R.string.kasa_limit_block_message))
                    banner.text = messages.joinToString("\n\n")
                    banner.visibility = View.VISIBLE
                    btnGenerate.isEnabled = false
                    btnGenerate.alpha = 0.5f
                } else {
                    banner.visibility = View.GONE
                    btnGenerate.isEnabled = true
                    btnGenerate.alpha = 1.0f
                }

                val btnVatRate = findViewById<Button>(R.id.btn_vat_rate)
                if (status.requiresVatRateSelection) {
                    btnVatRate.visibility = View.VISIBLE
                    refreshVatRateButtonText()
                } else {
                    btnVatRate.visibility = View.GONE
                    selectedVatRate = null
                }

                findViewById<View>(R.id.row_is_receipt).visibility =
                    if (status.allowsReceiptFlag) View.VISIBLE else View.GONE
            }
        }
    }

    private fun refreshVatRateButtonText() {
        val btn = findViewById<Button>(R.id.btn_vat_rate)
        val rate = selectedVatRate
        btn.text = if (rate != null) getString(R.string.vat_rate_selected, getString(rate.labelResId))
        else getString(R.string.vat_rate_choose)
    }

    private fun showVatRatePicker() {
        AppDialog.showOptionPicker(
            context = this,
            title = getString(R.string.vat_rate_picker_title),
            options = VatRate.entries.map { it.storageKey to getString(it.labelResId) }
        ) { selected ->
            selectedVatRate = VatRate.fromStorageKeyOrNull(selected)
            refreshVatRateButtonText()
        }
    }

    /** Кнопка "Dodaj towary z magazynu" видна только для Sprzedaż/Mieszana — для чистых
     *  Usługi склада нет, кнопка была бы просто непонятной и бесполезной. */
    private fun applyBusinessKindUi() {
        val prefs = getSharedPreferences("settings", MODE_PRIVATE)
        findViewById<Button>(R.id.btn_add_warehouse_items).visibility =
            if (BusinessKindHelper.get(prefs).showsMagazin) View.VISIBLE else View.GONE
    }

    /**
     * Добавляет одну строку позиции фактуры (item_invoice_line.xml) в контейнер
     * ll_invoice_items — товар или услуга, до MAX_ITEMS штук на одну фактуру.
     * productId != null означает, что позиция пришла со склада (см. applyPickedItems) —
     * тогда при сохранении фактуры остаток этого товара будет автоматически списан.
     */
    private fun addItemRow(
        name: String = "",
        qty: Double = 1.0,
        price: Double = 0.0,
        category: String? = null,
        productId: Long? = null
    ) {
        val container = findViewById<LinearLayout>(R.id.ll_invoice_items)
        if (container.childCount >= MAX_ITEMS) {
            Toast.makeText(this, getString(R.string.invoice_items_limit_reached, MAX_ITEMS), Toast.LENGTH_SHORT).show()
            return
        }
        val inflater = LayoutInflater.from(this)
        val row = inflater.inflate(R.layout.item_invoice_line, container, false)

        row.findViewById<EditText>(R.id.et_item_name).setText(name)
        row.findViewById<EditText>(R.id.et_item_qty).setText(formatQty(qty))
        if (price > 0.0) row.findViewById<EditText>(R.id.et_item_price).setText(formatMoney(price))

        row.setTag(R.id.tag_ryczalt_category, category)
        row.setTag(R.id.tag_product_id, productId)

        val btnRemove = row.findViewById<Button>(R.id.btn_item_remove)
        btnRemove.setOnClickListener {
            if (container.childCount <= 1) {
                Toast.makeText(this, getString(R.string.invoice_item_min_required), Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            container.removeView(row)
            renumberItemRows()
            recalcInvoiceTotal()
        }

        val btnCategory = row.findViewById<Button>(R.id.btn_item_ryczalt_category)
        if (activityType == ActivityType.JDG_RYCZALT) {
            btnCategory.visibility = View.VISIBLE
            refreshItemCategoryButtonText(row, btnCategory)
            btnCategory.setOnClickListener {
                AppDialog.showOptionPicker(
                    context = this,
                    title = getString(R.string.ryczalt_category_picker_title),
                    options = RyczaltCategory.entries.map { it.name to getString(it.labelRes) }
                ) { selected ->
                    row.setTag(R.id.tag_ryczalt_category, selected)
                    refreshItemCategoryButtonText(row, btnCategory)
                }
            }
        } else {
            btnCategory.visibility = View.GONE
        }

        val watcher = object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: android.text.Editable?) { recalcInvoiceTotal() }
        }
        row.findViewById<EditText>(R.id.et_item_qty).addTextChangedListener(watcher)
        row.findViewById<EditText>(R.id.et_item_price).addTextChangedListener(watcher)

        container.addView(row)
        renumberItemRows()
        recalcInvoiceTotal()
    }

    private fun refreshItemCategoryButtonText(row: View, btn: Button) {
        val cat = RyczaltCategory.fromStorageKeyOrNull(row.getTag(R.id.tag_ryczalt_category) as? String)
        btn.text = if (cat != null) getString(R.string.ryczalt_category_selected, getString(cat.labelRes))
        else getString(R.string.ryczalt_category_choose)
    }

    private fun renumberItemRows() {
        val container = findViewById<LinearLayout>(R.id.ll_invoice_items)
        for (i in 0 until container.childCount) {
            container.getChildAt(i).findViewById<TextView>(R.id.tv_item_number).text =
                getString(R.string.invoice_item_number_label, i + 1)
        }
    }

    private fun recalcInvoiceTotal() {
        val container = findViewById<LinearLayout>(R.id.ll_invoice_items)
        var total = 0.0
        for (i in 0 until container.childCount) {
            val row = container.getChildAt(i)
            val qty = parseAmount(row.findViewById<EditText>(R.id.et_item_qty).text.toString()) ?: 0.0
            val price = parseAmount(row.findViewById<EditText>(R.id.et_item_price).text.toString()) ?: 0.0
            total += qty * price
        }
        findViewById<TextView>(R.id.tv_invoice_total).text = getString(R.string.invoice_total_label, formatMoney(total))
    }

    /** Позиции со склада выбраны: добавляем их как отдельные строки в тот же контейнер,
     *  что и ручные позиции (см. addItemRow). Списание остатков происходит только
     *  после успешного сохранения фактуры (см. generateInvoice). */
    private fun applyPickedItems(serialized: String) {
        val picked = serialized.lines().filter { it.isNotBlank() }.mapNotNull { line ->
            val parts = line.split("|")
            if (parts.size == 4) {
                try {
                    PickedProduct(parts[0].toLong(), parts[1], parts[2].toDouble(), parts[3].toDouble())
                } catch (e: Exception) {
                    null
                }
            } else null
        }
        for (p in picked) {
            addItemRow(name = p.name, qty = p.quantity, price = p.unitPrice, category = null, productId = p.productId)
        }
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

    /** Один прочитанный и провалидированный ряд позиции фактуры перед сохранением. */
    private data class InvoiceLineInput(
        val name: String,
        val qty: Double,
        val price: Double,
        val category: String?,
        val productId: Long?
    )

    /** Считывает все заполненные строки контейнера ll_invoice_items — пустые
     *  (без названия или без корректной цены) пропускаются. */
    private fun collectItemRows(): List<InvoiceLineInput> {
        val container = findViewById<LinearLayout>(R.id.ll_invoice_items)
        val result = mutableListOf<InvoiceLineInput>()
        for (i in 0 until container.childCount) {
            val row = container.getChildAt(i)
            val name = row.findViewById<EditText>(R.id.et_item_name).text.toString().trim()
            val qty = parseAmount(row.findViewById<EditText>(R.id.et_item_qty).text.toString())
            val price = parseAmount(row.findViewById<EditText>(R.id.et_item_price).text.toString())
            if (name.isBlank() || price == null || price <= 0.0) continue
            result.add(
                InvoiceLineInput(
                    name = name,
                    qty = if (qty == null || qty <= 0.0) 1.0 else qty,
                    price = price,
                    category = row.getTag(R.id.tag_ryczalt_category) as? String,
                    productId = row.getTag(R.id.tag_product_id) as? Long
                )
            )
        }
        return result
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

        val lines = collectItemRows()

        if (buyerName.isBlank() || lines.isEmpty()) {
            Toast.makeText(this, getString(R.string.invoice_fill_required_fields), Toast.LENGTH_SHORT).show()
            return
        }
        // Przekroczono limit VAT lub limit gotówki, a wymaganego potwierdzenia w
        // Ustawieniach jeszcze nie złożono — wystawianie kolejnych faktur jest
        // zablokowane (zob. refreshComplianceStatus/VatComplianceHelper).
        if (compliance?.invoicingBlocked == true) {
            Toast.makeText(this, getString(R.string.invoice_blocked_toast), Toast.LENGTH_LONG).show()
            return
        }
        // Sprzedawca jest już podatnikiem VAT — stawka VAT jest obowiązkowa na każdej fakturze.
        if (compliance?.requiresVatRateSelection == true && selectedVatRate == null) {
            Toast.makeText(this, getString(R.string.vat_rate_required_error), Toast.LENGTH_LONG).show()
            return
        }
        // Ryczałt: каждая позиция обязана иметь категорию, чтобы налог считался
        // корректно — без неё непонятно, по какой ставке облагать эту позицию.
        if (activityType == ActivityType.JDG_RYCZALT && lines.any { it.category == null }) {
            Toast.makeText(this, getString(R.string.ryczalt_category_required_error), Toast.LENGTH_LONG).show()
            return
        }

        val amount = lines.sumOf { it.qty * it.price }
        val serviceName = lines.joinToString(", ") { it.name }

        findViewById<Button>(R.id.btn_generate).isEnabled = false
        val seller = InvoiceSellerData(sellerName, sellerNip, sellerStreet, sellerPostal, sellerCity, sellerBankAccount)
        val issueDateMillis = System.currentTimeMillis()
        val vatRateForInvoice = selectedVatRate
        val isReceiptForInvoice = compliance?.allowsReceiptFlag == true &&
            findViewById<android.widget.Switch>(R.id.sw_is_receipt).isChecked

        CoroutineScope(Dispatchers.IO).launch {
            try {
                InvoiceSellerDataStore.save(applicationContext, seller)
                val dao = AppDatabase.getInstance(applicationContext).invoiceDao()
                val invoiceNumber = (dao.getMaxInvoiceNumber() ?: 0) + 1
                val fileName = FileNaming.invoiceFileName(invoiceNumber, issueDateMillis)

                val itemsForPdf = lines.map {
                    InvoiceItem(
                        invoiceId = 0, productId = it.productId, name = it.name,
                        quantity = it.qty, unitPrice = it.price, ryczaltCategory = it.category
                    )
                }

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
                        items = itemsForPdf,
                        vatRate = vatRateForInvoice,
                        isReceipt = isReceiptForInvoice,
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
                        dueDateMillis = if (invoiceStatus == InvoiceStatus.PENDING) dueDateMillis else null,
                        vatRate = vatRateForInvoice?.storageKey,
                        isReceipt = isReceiptForInvoice
                    )
                )

                // Многопозиционная разбивка — теперь всегда (и вручную введённые позиции,
                // и позиции со склада) + автосписание остатков там, где есть productId.
                val itemsToInsert = lines.map {
                    InvoiceItem(
                        invoiceId = invoiceId, productId = it.productId, name = it.name,
                        quantity = it.qty, unitPrice = it.price, ryczaltCategory = it.category
                    )
                }
                AppDatabase.getInstance(applicationContext).invoiceItemDao().insertAll(itemsToInsert)
                val productDao = AppDatabase.getInstance(applicationContext).productDao()
                for (item in itemsToInsert) {
                    if (item.productId != null) {
                        productDao.decrementQuantity(item.productId, item.quantity)
                    }
                }

                // Zarejestrowana JDG (skala/liniowy/ryczałt): доход из фактуры теперь
                // ЗАПИСЫВАЕТСЯ АВТОМАТИЧЕСКИ как приход (Entry) — чтобы налог на главном
                // экране и в Historii считался сразу после каждой фактуры, без ручного
                // дублирования пользователем. Для niezarejestrowanej ничего не меняется —
                // доходы по-прежнему добавляются вручную, как и раньше.
                if (activityType != ActivityType.NIEZAREJESTROWANA) {
                    val entryDao = AppDatabase.getInstance(applicationContext).entryDao()
                    if (activityType == ActivityType.JDG_RYCZALT) {
                        // Разные категории ryczałtu облагаются разными ставками — если в
                        // одной фактуре смешаны товар и услуга, создаём отдельный приход
                        // на каждую категорию, чтобы налог считался корректно по каждой ставке.
                        val byCategory = lines.groupBy { it.category }
                        for ((category, group) in byCategory) {
                            val sum = group.sumOf { it.qty * it.price }
                            val itemNames = group.joinToString(", ") { it.name }
                            entryDao.insert(
                                Entry(
                                    amount = sum,
                                    isIncome = true,
                                    comment = getString(R.string.invoice_income_comment, invoiceNumber, itemNames),
                                    dateMillis = issueDateMillis,
                                    receiptPath = null,
                                    ryczaltCategory = category
                                )
                            )
                        }
                    } else {
                        entryDao.insert(
                            Entry(
                                amount = amount,
                                isIncome = true,
                                comment = getString(R.string.invoice_income_comment, invoiceNumber, serviceName),
                                dateMillis = issueDateMillis,
                                receiptPath = null,
                                ryczaltCategory = null
                            )
                        )
                    }
                }

                withContext(Dispatchers.Main) {
                    lastSavedUri = saved.uri
                    // Возвращаем форму позиций к одной пустой строке для следующей фактуры.
                    findViewById<LinearLayout>(R.id.ll_invoice_items).removeAllViews()
                    addItemRow()
                    selectedVatRate = null
                    findViewById<android.widget.Switch>(R.id.sw_is_receipt).isChecked = false
                    refreshVatRateButtonText()
                    findViewById<Button>(R.id.btn_generate).isEnabled = true
                    findViewById<View>(R.id.row_after_generate).visibility = View.VISIBLE
                    Toast.makeText(
                        this@AddInvoiceActivity,
                        getString(R.string.invoice_generated_toast, fileName),
                        Toast.LENGTH_LONG
                    ).show()
                    refreshCashLimit()
                    refreshComplianceStatus()
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
        // openPdfSafely сам ловит SecurityException (известная проблема MediaStore
        // на части устройств) и ActivityNotFoundException, с фолбэком через
        // локальную копию файла.
        val opened = InvoiceFileStorage.openPdfSafely(this, uri.toString())
        if (!opened) {
            Toast.makeText(this, getString(R.string.open_folder_error, InvoiceFileStorage.displayFolderPath), Toast.LENGTH_LONG).show()
        }
    }

    private fun shareLastPdf() {
        val uri = lastSavedUri ?: return
        try {
            startActivity(Intent.createChooser(InvoiceFileStorage.shareIntent(uri), getString(R.string.share_invoice_button)))
        } catch (e: Exception) {
            val fallback = InvoiceFileStorage.resolveViewableUri(this, uri)
            try {
                startActivity(Intent.createChooser(InvoiceFileStorage.shareIntent(fallback), getString(R.string.share_invoice_button)))
            } catch (e2: Exception) {
                Toast.makeText(this, getString(R.string.open_folder_error, InvoiceFileStorage.displayFolderPath), Toast.LENGTH_LONG).show()
            }
        }
    }

    private fun openInvoicesFolder() {
        try {
            startActivity(InvoiceFileStorage.openFolderIntent())
        } catch (e: ActivityNotFoundException) {
            Toast.makeText(this, getString(R.string.open_folder_error, InvoiceFileStorage.displayFolderPath), Toast.LENGTH_LONG).show()
        }
    }

    private fun formatMoney(v: Double): String = String.format(Locale.getDefault(), "%.2f", v)

    /** Читает сумму из поля независимо от того, каким разделителем введены копейки —
     *  запятой (как показывает formatMoney на pl/ru локали) или точкой (как ожидает
     *  стандартный toDoubleOrNull). */
    private fun parseAmount(raw: String): Double? = raw.trim().replace(",", ".").toDoubleOrNull()
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_ADDINVOICEACTIVITY_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/InvoicePdfGenerator.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/InvoicePdfGenerator.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEPDFGENERATOR_KT'
package com.example.fa_ksiegowy

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import java.io.OutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Buduje PDF dokumentu sprzedaży dla osoby fizycznej (Faktura imienna, gdy
 * sprzedawca jest VAT-owcem, lub Rachunek, gdy nie jest) — z pozycją
 * towaru/usługi w formie tabeli, danymi sprzedawcy/nabywcy obok siebie
 * i pieczątką statusu płatności ("ZAPŁACONO" dla opłaconych, "OCZEKUJE NA
 * ZAPŁATĘ" + termin płatności dla nieopłaconych — patrz [InvoiceStatus]).
 * Wszystkie etykiety pochodzą z zasobów string — dokument jest w pełni w
 * języku aktualnie wybranym w aplikacji (kontekst przekazywany przez
 * wywołującego musi mieć już zastosowaną lokalizację, patrz
 * [BaseActivity]/[LocaleHelper] — nie używamy tu applicationContext).
 */
object InvoicePdfGenerator {

    private const val PAGE_WIDTH = 595
    private const val PAGE_HEIGHT = 842
    private const val MARGIN = 48f

    private data class Labels(
        val docKind: String,
        val issueDate: String,
        val saleDate: String,
        val seller: String,
        val buyer: String,
        val nip: String,
        val bankAccount: String,
        val buyerPrivate: String,
        val tableLp: String,
        val tableName: String,
        val tableUnit: String,
        val tableQty: String,
        val tablePrice: String,
        val tableTotal: String,
        val unitPiece: String,
        val sumLabel: String,
        val paidStamp: String,
        val pendingStamp: String,
        val paymentDateLabel: String,
        val dueDateLabel: String,
        val paymentMethodLabel: String,
        val paymentStatusLine: String,
        val tableNetto: String,
        val tableVatRate: String,
        val tableVatAmount: String,
        val tableBrutto: String,
        val receiptLabel: String
    )

    private fun buildLabels(context: Context, isVatPayer: Boolean, paymentMethod: PaymentMethod): Labels = Labels(
        docKind = context.getString(if (isVatPayer) R.string.invoice_pdf_faktura else R.string.invoice_pdf_rachunek),
        issueDate = context.getString(R.string.invoice_pdf_issue_date),
        saleDate = context.getString(R.string.invoice_pdf_sale_date),
        seller = context.getString(R.string.invoice_pdf_seller),
        buyer = context.getString(R.string.invoice_pdf_buyer),
        nip = context.getString(R.string.invoice_pdf_nip),
        bankAccount = context.getString(R.string.invoice_pdf_bank_account),
        buyerPrivate = context.getString(R.string.invoice_pdf_buyer_private),
        tableLp = context.getString(R.string.invoice_pdf_table_lp),
        tableName = context.getString(R.string.invoice_pdf_table_name),
        tableUnit = context.getString(R.string.invoice_pdf_table_unit),
        tableQty = context.getString(R.string.invoice_pdf_table_qty),
        tablePrice = context.getString(R.string.invoice_pdf_table_price),
        tableTotal = context.getString(R.string.invoice_pdf_table_total),
        unitPiece = context.getString(R.string.invoice_pdf_unit_piece),
        sumLabel = context.getString(R.string.invoice_pdf_sum_label),
        paidStamp = context.getString(R.string.invoice_pdf_paid_stamp),
        pendingStamp = context.getString(R.string.invoice_pdf_pending_stamp),
        paymentDateLabel = context.getString(R.string.invoice_pdf_payment_date),
        dueDateLabel = context.getString(R.string.invoice_due_date_label),
        paymentMethodLabel = context.getString(R.string.payment_method_label),
        paymentStatusLine = context.getString(paymentMethod.paidLabelResId),
        tableNetto = context.getString(R.string.invoice_pdf_table_netto),
        tableVatRate = context.getString(R.string.invoice_pdf_table_vat_rate),
        tableVatAmount = context.getString(R.string.invoice_pdf_table_vat_amount),
        tableBrutto = context.getString(R.string.invoice_pdf_table_brutto),
        receiptLabel = context.getString(R.string.invoice_pdf_receipt_label)
    )

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
        invoiceStatus: InvoiceStatus = InvoiceStatus.PAID,
        dueDateMillis: Long? = null,
        /** Позиции склада, выбранные для этой фактуры — если не пусто, таблица PDF
         *  рисует отдельную строку на каждую позицию (с реальным количеством) вместо
         *  одной строки на всю сумму. Если пусто — поведение как раньше: одна строка
         *  из serviceName/amount (ручной ввод без склада). */
        items: List<InvoiceItem> = emptyList(),
        /** Stawka VAT wybrana przy wystawianiu — niepusta tylko dla sprzedawców już
         *  zarejestrowanych jako podatnicy VAT (zob. VatComplianceHelper). Gdy podana,
         *  tabela pozycji pokazuje dodatkowo Cenę/Wartość netto, Stawkę VAT, Kwotę VAT
         *  i Wartość brutto (jak w oficjalnym wzorze faktury VAT), a kwota końcowa jest
         *  liczona brutto (netto + VAT). */
        vatRate: VatRate? = null,
        /** true, jeśli faktura jest jednocześnie wystawiana "do paragonu" z kasy fiskalnej. */
        isReceipt: Boolean = false,
        out: OutputStream
    ) {
        val isVatPayer = seller.nip.isNotBlank()
        val l = buildLabels(context, isVatPayer, paymentMethod)

        val document = PdfDocument()
        var pageNumber = 1
        var page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
        var canvas = page.canvas

        // Logo aplikacji w prawym górnym rogu — na KAŻDEJ wystawionej fakturze,
        // niezależnie od rodzaju działalności (zob. treść zgłoszenia funkcji).
        val logoBitmap: Bitmap? = try {
            BitmapFactory.decodeResource(context.resources, R.drawable.logo)
        } catch (e: Exception) {
            null
        }
        fun drawLogo() {
            if (logoBitmap == null) return
            val logoSize = 46f
            val scaled = Bitmap.createScaledBitmap(logoBitmap, logoSize.toInt(), logoSize.toInt(), true)
            canvas.drawBitmap(scaled, PAGE_WIDTH - MARGIN - logoSize, MARGIN - 20f, null)
        }
        drawLogo()

        val titlePaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 20f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val sectionPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 11.5f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val textPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 10.5f; isAntiAlias = true }
        val hintPaint = Paint().apply { color = 0xFF555555.toInt(); textSize = 9f; isAntiAlias = true }
        val tableHeaderPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 9.5f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val tableCellPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 10f; isAntiAlias = true }
        val stampPaint = Paint().apply { color = 0xFF1B7F3C.toInt(); textSize = 13f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val pendingStampPaint = Paint().apply { color = 0xFFCC6A00.toInt(); textSize = 13f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val linePaint = Paint().apply { color = 0xFFB0B0B0.toInt(); strokeWidth = 0.75f; isAntiAlias = true }
        val headerFillPaint = Paint().apply { color = 0xFFEDEEF5.toInt() }

        var y = MARGIN

        fun newPageIfNeeded(needed: Float) {
            if (y + needed > PAGE_HEIGHT - MARGIN) {
                document.finishPage(page)
                pageNumber++
                page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
                canvas = page.canvas
                y = MARGIN
                drawLogo()
            }
        }

        fun line(text: String, paint: Paint = textPaint, gap: Float = 15f, x: Float = MARGIN) {
            newPageIfNeeded(gap)
            canvas.drawText(text, x, y, paint)
            y += gap
        }

        fun wrappedLines(text: String, maxCharsPerLine: Int, paint: Paint, gap: Float, x: Float = MARGIN): Float {
            val words = text.split(" ")
            var current = StringBuilder()
            var startY = y
            for (w in words) {
                if (current.length + w.length + 1 > maxCharsPerLine) {
                    newPageIfNeeded(gap)
                    canvas.drawText(current.toString(), x, y, paint)
                    y += gap
                    current = StringBuilder()
                }
                if (current.isNotEmpty()) current.append(" ")
                current.append(w)
            }
            if (current.isNotEmpty()) {
                newPageIfNeeded(gap)
                canvas.drawText(current.toString(), x, y, paint)
                y += gap
            }
            return y - startY
        }

        val money: (Double) -> String = {
            String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") + " zł"
        }
        val dateFmt = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())

        // --- Nagłówek ---
        line("${l.docKind} nr $invoiceNumber", titlePaint, 26f)
        line("${l.issueDate}: ${dateFmt.format(Date(issueDateMillis))}    ${l.saleDate}: ${dateFmt.format(Date(serviceDateMillis))}", hintPaint, 22f)

        // --- Sprzedawca / Nabywca obok siebie ---
        val colLeftX = MARGIN
        val colRightX = MARGIN + (PAGE_WIDTH - 2 * MARGIN) / 2 + 8f
        val blockTopY = y

        y = blockTopY
        line(l.seller, sectionPaint, 17f, colLeftX)
        if (seller.name.isNotBlank()) line(seller.name, textPaint, 14f, colLeftX)
        val sellerAddress = listOfNotNull(
            seller.street.ifBlank { null },
            listOf(seller.postalCode, seller.city).filter { it.isNotBlank() }.joinToString(" ").ifBlank { null }
        ).joinToString(", ")
        if (sellerAddress.isNotBlank()) line(sellerAddress, textPaint, 14f, colLeftX)
        if (seller.nip.isNotBlank()) line("${l.nip}: ${seller.nip}", textPaint, 14f, colLeftX)
        if (seller.bankAccount.isNotBlank()) line("${l.bankAccount}: ${seller.bankAccount}", textPaint, 14f, colLeftX)
        val leftBottomY = y

        y = blockTopY
        line(l.buyer, sectionPaint, 17f, colRightX)
        line(buyerName, textPaint, 14f, colRightX)
        val buyerAddress = listOfNotNull(
            buyerStreet.ifBlank { null },
            listOf(buyerPostalCode, buyerCity).filter { it.isNotBlank() }.joinToString(" ").ifBlank { null }
        ).joinToString(", ")
        if (buyerAddress.isNotBlank()) line(buyerAddress, textPaint, 14f, colRightX)
        if (!isPhysicalPerson && !buyerNip.isNullOrBlank()) {
            line("${l.nip}: $buyerNip", textPaint, 14f, colRightX)
        } else {
            wrappedLines(l.buyerPrivate, 46, hintPaint, 12f, colRightX)
        }
        val rightBottomY = y

        y = maxOf(leftBottomY, rightBottomY) + 18f

        // --- Tabela pozycji ---
        val tableLeft = MARGIN
        val tableRight = PAGE_WIDTH - MARGIN
        val qtyStr: (Double) -> String = { q -> if (q == q.toLong().toDouble()) q.toLong().toString() else q.toString() }
        val vatLabel: String = vatRate?.let { context.getString(it.labelResId) } ?: ""

        // Список строк таблицы: если переданы позиции склада — по строке на каждую
        // (с реальным количеством), иначе — одна строка на всю сумму (как раньше,
        // для счетов без привязки к складу).
        data class Row(val name: String, val qty: Double, val unitPrice: Double)
        val rows: List<Row> = if (items.isNotEmpty()) items.map { Row(it.name, it.quantity, it.unitPrice) }
            else listOf(Row(serviceName, 1.0, amount))
        val totalAmount = rows.sumOf { it.qty * it.unitPrice }

        val headerRowHeight = 20f
        val dataRowHeight = 22f
        val totalRowHeight = 22f

        newPageIfNeeded(70f)
        var segmentTop = y - 10f

        if (vatRate == null) {
            // --- Tabela bez VAT (zwolnienie podmiotowe / rachunek) — jak dotychczas. ---
            val colLp = tableLeft
            val colName = colLp + 28f
            val colUnit = colName + 232f
            val colQty = colUnit + 46f
            val colPrice = colQty + 46f
            val colTotal = colPrice + 72f
            val colStops = floatArrayOf(colLp, colName, colUnit, colQty, colPrice, colTotal, tableRight)

            fun drawHeaderRow() {
                canvas.drawRect(tableLeft, segmentTop, tableRight, segmentTop + headerRowHeight, headerFillPaint)
                val headerBaselineY = segmentTop + headerRowHeight - 6f
                canvas.drawText(l.tableLp, colLp + 4f, headerBaselineY, tableHeaderPaint)
                canvas.drawText(l.tableName, colName + 4f, headerBaselineY, tableHeaderPaint)
                canvas.drawText(l.tableUnit, colUnit + 4f, headerBaselineY, tableHeaderPaint)
                canvas.drawText(l.tableQty, colQty + 4f, headerBaselineY, tableHeaderPaint)
                canvas.drawText(l.tablePrice, colPrice + 4f, headerBaselineY, tableHeaderPaint)
                canvas.drawText(l.tableTotal, colTotal + 4f, headerBaselineY, tableHeaderPaint)
                y = segmentTop + headerRowHeight
                canvas.drawLine(tableLeft, y, tableRight, y, linePaint)
            }

            fun closeSegment(colLinesBottom: Float) {
                canvas.drawRect(tableLeft, segmentTop, tableRight, y, linePaint.apply { style = Paint.Style.STROKE })
                for (i in 1 until colStops.size - 1) {
                    canvas.drawLine(colStops[i], segmentTop, colStops[i], colLinesBottom, linePaint)
                }
            }

            drawHeaderRow()
            for ((idx, row) in rows.withIndex()) {
                // Оставляем место под итоговую строку на этой же странице — если не
                // помещается, закрываем таблицу на текущей странице и продолжаем с
                // новым заголовком на следующей (для счетов с большим числом позиций).
                if (y + dataRowHeight + totalRowHeight > PAGE_HEIGHT - MARGIN) {
                    closeSegment(y)
                    document.finishPage(page)
                    pageNumber++
                    page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
                    canvas = page.canvas
                    y = MARGIN
                    drawLogo()
                    segmentTop = y - 10f
                    drawHeaderRow()
                }
                val baselineY = y + dataRowHeight - 7f
                canvas.drawText((idx + 1).toString(), colLp + 4f, baselineY, tableCellPaint)
                canvas.drawText(row.name.take(38), colName + 4f, baselineY, tableCellPaint)
                canvas.drawText(l.unitPiece, colUnit + 4f, baselineY, tableCellPaint)
                canvas.drawText(qtyStr(row.qty), colQty + 4f, baselineY, tableCellPaint)
                canvas.drawText(money(row.unitPrice), colPrice + 4f, baselineY, tableCellPaint)
                canvas.drawText(money(row.qty * row.unitPrice), colTotal + 4f, baselineY, tableCellPaint)
                y += dataRowHeight
                canvas.drawLine(tableLeft, y, tableRight, y, linePaint)
            }

            val gridBottom = y
            val totalRowTop = y
            val totalBaselineY = totalRowTop + totalRowHeight - 7f
            canvas.drawText(l.sumLabel + ":", colPrice - 60f, totalBaselineY, sectionPaint)
            canvas.drawText(money(totalAmount), colTotal + 4f, totalBaselineY, sectionPaint)
            y = totalRowTop + totalRowHeight
            closeSegment(gridBottom)
        } else {
            // --- Tabela VAT (sprzedawca zarejestrowany jako podatnik VAT) —
            // Lp / Nazwa / Jm. / Ilość / Cena netto / Wartość netto / Stawka VAT /
            // Kwota VAT / Wartość brutto, zgodnie z oficjalnym wzorem faktury VAT.
            // Kolumny są węższe niż w wariancie bez VAT (mniejsza czcionka),
            // żeby wszystkie dziewięć kolumn zmieściło się na szerokości strony A4.
            val vatCellPaint = Paint(tableCellPaint).apply { textSize = 8.5f }
            val vatHeaderPaint = Paint(tableHeaderPaint).apply { textSize = 8f }
            val vatMoney: (Double) -> String = { String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") }

            val colLp = tableLeft
            val colName = colLp + 22f
            val colUnit = colName + 132f
            val colQty = colUnit + 28f
            val colNetPrice = colQty + 30f
            val colNetValue = colNetPrice + 58f
            val colVatRateCol = colNetValue + 58f
            val colVatAmount = colVatRateCol + 34f
            val colBrutto = colVatAmount + 58f
            val colStops = floatArrayOf(colLp, colName, colUnit, colQty, colNetPrice, colNetValue, colVatRateCol, colVatAmount, colBrutto, tableRight)

            fun drawHeaderRow() {
                canvas.drawRect(tableLeft, segmentTop, tableRight, segmentTop + headerRowHeight, headerFillPaint)
                val headerBaselineY = segmentTop + headerRowHeight - 6f
                canvas.drawText(l.tableLp, colLp + 3f, headerBaselineY, vatHeaderPaint)
                canvas.drawText(l.tableName, colName + 3f, headerBaselineY, vatHeaderPaint)
                canvas.drawText(l.tableUnit, colUnit + 3f, headerBaselineY, vatHeaderPaint)
                canvas.drawText(l.tableQty, colQty + 3f, headerBaselineY, vatHeaderPaint)
                canvas.drawText(l.tableNetto, colNetPrice + 3f, headerBaselineY, vatHeaderPaint)
                canvas.drawText(l.tableNetto, colNetValue + 3f, headerBaselineY, vatHeaderPaint)
                canvas.drawText(l.tableVatRate, colVatRateCol + 3f, headerBaselineY, vatHeaderPaint)
                canvas.drawText(l.tableVatAmount, colVatAmount + 3f, headerBaselineY, vatHeaderPaint)
                canvas.drawText(l.tableBrutto, colBrutto + 3f, headerBaselineY, vatHeaderPaint)
                y = segmentTop + headerRowHeight
                canvas.drawLine(tableLeft, y, tableRight, y, linePaint)
            }

            fun closeSegment(colLinesBottom: Float) {
                canvas.drawRect(tableLeft, segmentTop, tableRight, y, linePaint.apply { style = Paint.Style.STROKE })
                for (i in 1 until colStops.size - 1) {
                    canvas.drawLine(colStops[i], segmentTop, colStops[i], colLinesBottom, linePaint)
                }
            }

            drawHeaderRow()
            var vatSum = 0.0
            var bruttoSum = 0.0
            for ((idx, row) in rows.withIndex()) {
                if (y + dataRowHeight + totalRowHeight > PAGE_HEIGHT - MARGIN) {
                    closeSegment(y)
                    document.finishPage(page)
                    pageNumber++
                    page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
                    canvas = page.canvas
                    y = MARGIN
                    drawLogo()
                    segmentTop = y - 10f
                    drawHeaderRow()
                }
                val netValue = row.qty * row.unitPrice
                val vatAmount = vatRate.vatAmount(netValue)
                val bruttoValue = netValue + vatAmount
                vatSum += vatAmount
                bruttoSum += bruttoValue

                val baselineY = y + dataRowHeight - 7f
                canvas.drawText((idx + 1).toString(), colLp + 3f, baselineY, vatCellPaint)
                canvas.drawText(row.name.take(20), colName + 3f, baselineY, vatCellPaint)
                canvas.drawText(l.unitPiece, colUnit + 3f, baselineY, vatCellPaint)
                canvas.drawText(qtyStr(row.qty), colQty + 3f, baselineY, vatCellPaint)
                canvas.drawText(vatMoney(row.unitPrice), colNetPrice + 3f, baselineY, vatCellPaint)
                canvas.drawText(vatMoney(netValue), colNetValue + 3f, baselineY, vatCellPaint)
                canvas.drawText(vatLabel + "%".takeIf { vatRate.percent != null }.orEmpty(), colVatRateCol + 3f, baselineY, vatCellPaint)
                canvas.drawText(vatMoney(vatAmount), colVatAmount + 3f, baselineY, vatCellPaint)
                canvas.drawText(vatMoney(bruttoValue), colBrutto + 3f, baselineY, vatCellPaint)
                y += dataRowHeight
                canvas.drawLine(tableLeft, y, tableRight, y, linePaint)
            }

            val gridBottom = y
            val totalRowTop = y
            val totalBaselineY = totalRowTop + totalRowHeight - 7f
            canvas.drawText(l.sumLabel + ":", colNetPrice, totalBaselineY, sectionPaint)
            canvas.drawText(vatMoney(totalAmount), colNetValue + 3f, totalBaselineY, tableCellPaint.apply { textSize = 9f })
            canvas.drawText(vatMoney(vatSum), colVatAmount + 3f, totalBaselineY, tableCellPaint.apply { textSize = 9f })
            canvas.drawText(vatMoney(bruttoSum), colBrutto + 3f, totalBaselineY, tableCellPaint.apply { textSize = 9f })
            y = totalRowTop + totalRowHeight
            closeSegment(gridBottom)
        }

        y += 26f

        if (isReceipt) {
            line(l.receiptLabel, hintPaint, 16f)
        }

        // --- Status płatności / pieczątka ---
        // Dokument musi wiernie odzwierciedlać rzeczywisty status faktury:
        // dla PAID pokazujemy datę zapłaty i pieczątkę "ZAPŁACONO", a dla
        // PENDING — termin płatności i pieczątkę "OCZEKUJE NA ZAPŁATĘ".
        // Wcześniej PDF zawsze pokazywał "ZAPŁACONO" niezależnie od
        // rzeczywistego statusu faktury — to był błąd.
        newPageIfNeeded(40f)
        if (invoiceStatus == InvoiceStatus.PAID) {
            line("${l.paymentDateLabel}: ${dateFmt.format(Date(paymentDateMillis))}", textPaint, 16f)
            line(l.paymentStatusLine, textPaint, 20f)
            val stampText = "✓ ${l.paidStamp}"
            canvas.drawText(stampText, tableRight - stampPaint.measureText(stampText), y - 4f, stampPaint)
        } else {
            val due = dueDateMillis ?: paymentDateMillis
            line("${l.dueDateLabel}: ${dateFmt.format(Date(due))}", textPaint, 16f)
            line("${l.paymentMethodLabel}: ${context.getString(paymentMethod.labelResId)}", textPaint, 20f)
            val stampText = "⏳ ${l.pendingStamp}"
            canvas.drawText(stampText, tableRight - pendingStampPaint.measureText(stampText), y - 4f, pendingStampPaint)
        }
        y += 4f

        document.finishPage(page)
        document.writeTo(out)
        document.close()
    }
}

EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEPDFGENERATOR_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/InvoicePdfGenerator.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/SettingsTaxActivity.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/SettingsTaxActivity.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_SETTINGSTAXACTIVITY_KT'
package com.example.fa_ksiegowy

import android.content.SharedPreferences
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.RadioGroup
import android.widget.TextView
import android.widget.Toast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Настройки налогов и формы деятельности:
 *  1) Тип деятельности (niezarejestrowana / JDG: skala, liniowy, ryczałt) —
 *     от него зависит применяемый лимит и то, какая декларация актуальна
 *     (PIT-36 / PIT-36L / PIT-28), см. ActivityTypeHelper.
 *  2) Минимальное вознаграждение (minimalne wynagrodzenie) и месячный лимит 75% —
 *     ЭТО АКТУАЛЬНО ТОЛЬКО ДЛЯ NIEZAREJESTROWANA (лимит přychodu, при превышении
 *     которого возникает обязанность зарегистрировать JDG). Для любого из трёх
 *     вариантов Zarejestrowana JDG (skala/liniowy/ryczałt) этот блок скрыт — у
 *     зарегистрированной деятельности такого месячного лимита просто нет.
 *  3) Ставки ryczałtu больше НЕ настраиваются здесь одной общей цифрой — теперь
 *     категория (и, соответственно, ставка 3%/5,5%/8,5%/12%/14%/17%) выбирается
 *     для каждой операции дохода отдельно — см. AddEntryActivity (доход) и
 *     AddInvoiceActivity (позиция фактуры). Это важно, так как один человек может
 *     одновременно продавать товары и оказывать услуги с разными ставками.
 *  4) "Прочие доходы" — как и раньше, влияют на то, какая часть прибыли
 *     из приложения облагается по 12%, а какая — по 32% (только для skali).
 *
 * Налог всегда считается автоматически по официальной формуле для выбранной
 * формы (см. TaxHelper) — ручного ввода единого процента ryczałtu больше нет.
 */
class SettingsTaxActivity : BaseActivity() {
    private lateinit var prefs: SharedPreferences

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings_tax)
        prefs = getSharedPreferences("settings", MODE_PRIVATE)

        val year = TaxHelper.currentYear()
        try {
            findViewById<TextView>(R.id.tv_other_income_label).text =
                getString(R.string.other_income_label, year)
        } catch (e: Exception) {
            // Fallback if string resource has invalid format
            findViewById<TextView>(R.id.tv_other_income_label).text = 
                "Other income ($year)"
        }

        setupActivityType()
        setupMinWage()
        setupVatCompliance()
        setupKasaCompliance()
        setupPushFrequency()

        val etOtherIncome = findViewById<EditText>(R.id.et_other_income)
        etOtherIncome.setText(TaxHelper.getOtherIncome(prefs, year).toString())
        findViewById<Button>(R.id.btn_save_other_income).setOnClickListener {
            val v = etOtherIncome.text.toString().toDoubleOrNull() ?: 0.0
            TaxHelper.setOtherIncome(prefs, year, v)

            // Minimalne wynagrodzenie учитывается только для niezarejestrowana —
            // для JDG блок скрыт (см. updateNierejestrowanaFieldsVisibility), поле
            // может быть невидимым, тогда его значение не сохраняем.
            val minWageField = findViewById<EditText>(R.id.et_min_wage)
            if (minWageField.visibility == View.VISIBLE) {
                val minWage = minWageField.text.toString().toDoubleOrNull()
                if (minWage != null && minWage > 0.0) {
                    ActivityTypeHelper.setMinWage(prefs, minWage)
                    updateMonthlyLimitPreview()
                }
            }

            // Отметить, что тип деятельности выбран
            prefs.edit()
                .putBoolean("is_tax_type_selected", true)
                .apply()

            Toast.makeText(this, getString(R.string.saved), Toast.LENGTH_SHORT).show()
        }
    }

    private fun setupActivityType() {
        val rg = findViewById<RadioGroup>(R.id.rg_activity_type)
        val current = ActivityTypeHelper.get(prefs)
        val idFor = mapOf(
            ActivityType.NIEZAREJESTROWANA to R.id.rb_niezarejestrowana,
            ActivityType.JDG_SKALA to R.id.rb_jdg_skala,
            ActivityType.JDG_LINIOWY to R.id.rb_jdg_liniowy,
            ActivityType.JDG_RYCZALT to R.id.rb_jdg_ryczalt
        )
        rg.check(idFor[current] ?: R.id.rb_niezarejestrowana)
        updateNierejestrowanaFieldsVisibility(current)

        rg.setOnCheckedChangeListener { _, checkedId ->
            val type = when (checkedId) {
                R.id.rb_niezarejestrowana -> ActivityType.NIEZAREJESTROWANA
                R.id.rb_jdg_skala -> ActivityType.JDG_SKALA
                R.id.rb_jdg_liniowy -> ActivityType.JDG_LINIOWY
                R.id.rb_jdg_ryczalt -> ActivityType.JDG_RYCZALT
                else -> ActivityType.NIEZAREJESTROWANA
            }
            ActivityTypeHelper.set(prefs, type)
            updateNierejestrowanaFieldsVisibility(type)
        }
    }

    /** Блок "Minimalne wynagrodzenie / Monthly limit (75%)" нужен только для
     *  niezarejestrowana — для любого из трёх Zarejestrowana JDG (skala/liniowy/
     *  ryczałt) такого лимита не существует, поэтому блок полностью скрывается.
     *  Подсказка про перенос ставки ryczałtu показывается, только если выбран ryczałt. */
    private fun updateNierejestrowanaFieldsVisibility(type: ActivityType) {
        val visible = type == ActivityType.NIEZAREJESTROWANA
        findViewById<View>(R.id.layout_min_wage).visibility = if (visible) View.VISIBLE else View.GONE
        findViewById<View>(R.id.layout_ryczalt_rate_hint).visibility =
            if (type == ActivityType.JDG_RYCZALT) View.VISIBLE else View.GONE
    }

    private fun setupMinWage() {
        val etMinWage = findViewById<EditText>(R.id.et_min_wage)
        try {
            etMinWage.setText(
                String.format("%.2f", ActivityTypeHelper.getMinWage(prefs))
            )
        } catch (e: Exception) {
            etMinWage.setText("0.00")
        }
        updateMonthlyLimitPreview()
    }

    private fun updateMonthlyLimitPreview() {
        val tvPreview = findViewById<TextView>(R.id.tv_monthly_limit_preview)
        try {
            val limit = ActivityTypeHelper.nierejestrowanaMonthlyLimit(prefs)
            tvPreview.text = String.format("Monthly limit (75%%): %.2f zł", limit)
        } catch (e: Exception) {
            tvPreview.text = "Monthly limit: could not calculate"
        }
    }

    override fun onResume() {
        super.onResume()
        // Лимит мог быть превышен, пока пользователь был на другом экране (например,
        // сразу после выставления фактуры) — перепроверяем видимость блока при возврате.
        setupVatCompliance()
        setupKasaCompliance()
    }

    /**
     * Блок подтверждения регистрации VAT: появляется только после превышения
     * годового лимита zwolnienia z VAT (240 000 zł) — либо если подтверждение
     * уже было дано ранее (тогда чекбокс показывается заблокированным как
     * информация о статусе, без возможности снять галочку).
     */
    private fun setupVatCompliance() {
        val layout = findViewById<View>(R.id.layout_vat_compliance)
        val cb = findViewById<CheckBox>(R.id.cb_vat_registered)
        val alreadyConfirmed = VatComplianceHelper.isVatRegisteredConfirmed(prefs)
        if (alreadyConfirmed) {
            layout.visibility = View.VISIBLE
            cb.setOnCheckedChangeListener(null)
            cb.isChecked = true
            cb.isEnabled = false
            cb.text = getString(R.string.cb_vat_registered_confirmed_label)
            return
        }
        CoroutineScope(Dispatchers.IO).launch {
            val limits = LimitsHelper.compute(applicationContext)
            withContext(Dispatchers.Main) {
                layout.visibility = if (limits.vat.exceeded) View.VISIBLE else View.GONE
                cb.isChecked = false
                cb.isEnabled = true
                cb.text = getString(R.string.cb_vat_registered_label)
                cb.setOnCheckedChangeListener { _, checked ->
                    if (checked) {
                        AppDialog.show(
                            context = this@SettingsTaxActivity,
                            title = getString(R.string.vat_confirm_dialog_title),
                            message = getString(R.string.vat_confirm_dialog_message),
                            positiveText = getString(R.string.confirm_yes),
                            onPositive = {
                                VatComplianceHelper.confirmVatRegistered(prefs)
                                setupVatCompliance()
                            },
                            negativeText = getString(R.string.confirm_cancel),
                            onNegative = { cb.isChecked = false }
                        )
                    }
                }
            }
        }
    }

    /**
     * Блок подтверждения наличия kasy fiskalnej — аналогично [setupVatCompliance],
     * появляется после превышения лимита 20 000 zł gotówki dla osób fizycznych.
     */
    private fun setupKasaCompliance() {
        val layout = findViewById<View>(R.id.layout_kasa_compliance)
        val cb = findViewById<CheckBox>(R.id.cb_kasa_fiskalna)
        val alreadyConfirmed = VatComplianceHelper.isKasaFiskalnaConfirmed(prefs)
        if (alreadyConfirmed) {
            layout.visibility = View.VISIBLE
            cb.setOnCheckedChangeListener(null)
            cb.isChecked = true
            cb.isEnabled = false
            cb.text = getString(R.string.cb_kasa_confirmed_label)
            return
        }
        CoroutineScope(Dispatchers.IO).launch {
            val cash = CashLimitHelper.computeCurrentYear(applicationContext)
            withContext(Dispatchers.Main) {
                layout.visibility = if (cash.exceeded) View.VISIBLE else View.GONE
                cb.isChecked = false
                cb.isEnabled = true
                cb.text = getString(R.string.cb_kasa_label)
                cb.setOnCheckedChangeListener { _, checked ->
                    if (checked) {
                        AppDialog.show(
                            context = this@SettingsTaxActivity,
                            title = getString(R.string.kasa_confirm_dialog_title),
                            message = getString(R.string.kasa_confirm_dialog_message),
                            positiveText = getString(R.string.confirm_yes),
                            onPositive = {
                                VatComplianceHelper.confirmKasaFiskalna(prefs)
                                setupKasaCompliance()
                            },
                            negativeText = getString(R.string.confirm_cancel),
                            onNegative = { cb.isChecked = false }
                        )
                    }
                }
            }
        }
    }

    /** Częstotliwość powiadomień push (ile razy dziennie mogą przychodzić alerty
     *  o przekroczonych limitach i zaległych fakturach) — zob. VatComplianceHelper. */
    private fun setupPushFrequency() {
        val et = findViewById<EditText>(R.id.et_push_frequency)
        et.setText(VatComplianceHelper.getPushFrequency(prefs).toString())
        findViewById<Button>(R.id.btn_save_push_frequency).setOnClickListener {
            val value = et.text.toString().toIntOrNull()
            if (value == null || value < 1) {
                Toast.makeText(this, getString(R.string.push_frequency_invalid), Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            VatComplianceHelper.setPushFrequency(prefs, value)
            et.setText(VatComplianceHelper.getPushFrequency(prefs).toString())
            Toast.makeText(this, getString(R.string.push_frequency_saved), Toast.LENGTH_SHORT).show()
        }
    }
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_SETTINGSTAXACTIVITY_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/SettingsTaxActivity.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/LimitsNotificationWorker.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/LimitsNotificationWorker.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_LIMITSNOTIFICATIONWORKER_KT'
package com.example.fa_ksiegowy

import android.Manifest
import android.app.NotificationChannel
import android.app.PendingIntent
import android.content.Intent
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.Calendar
import java.util.concurrent.TimeUnit

/**
 * Ежедневная фоновая проверка лимитов и сроков, запускается через WorkManager
 * (переживает перезапуски устройства и не требует, чтобы приложение было открыто).
 * Уведомления показываются не чаще одного раза в день на каждый повод — состояние
 * "уже показали сегодня" хранится в prefs, чтобы не спамить пользователя при
 * каждом запуске воркера.
 */
class LimitsNotificationWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        try {
            // Уведомления должны быть на языке, выбранном В ПРИЛОЖЕНИИ (LocaleHelper),
            // а не на системном языке телефона — раньше ctx.getString(...)
            // брал системную локаль напрямую, из-за чего уведомления могли отличаться
            // от языка интерфейса приложения.
            val ctx = LocaleHelper.applyLocale(applicationContext)
            val limits = LimitsHelper.compute(applicationContext)
            val prefs = applicationContext.getSharedPreferences("settings", Context.MODE_PRIVATE)
            val today = SDF_DAY.format(java.util.Date())

            // 1) Лимит działalności nierejestrowanej — 80% / 95% / превышение.
            if (limits.activityType == ActivityType.NIEZAREJESTROWANA) {
                val m = limits.monthly
                when {
                    m.exceeded -> notifyOnce(
                        prefs, "n_exceeded_$today",
                        ctx.getString(R.string.notif_limit_exceeded_title),
                        ctx.getString(R.string.notif_limit_exceeded_text)
                    )
                    m.percent >= 95 -> notifyOnce(
                        prefs, "n_95_$today",
                        ctx.getString(R.string.notif_limit_95_title),
                        ctx.getString(R.string.notif_limit_95_text)
                    )
                    m.percent >= 80 -> notifyOnce(
                        prefs, "n_80_$today",
                        ctx.getString(R.string.notif_limit_80_title),
                        ctx.getString(R.string.notif_limit_80_text)
                    )
                }
            }

            // 2) Приближение к порогу 120 000 zł (переход на 32%).
            if (limits.bracket.percent in 90..999) {
                notifyOnce(
                    prefs, "bracket90_${TaxHelper.currentYear()}",
                    ctx.getString(R.string.notif_bracket_title),
                    ctx.getString(R.string.notif_bracket_text)
                )
            }

            // 3) Приближение к лимиту zwolnienia z VAT (240 000 zł) — раз в день.
            if (limits.vat.percent in 90..999) {
                notifyOnce(
                    prefs, "vat90_${TaxHelper.currentYear()}",
                    ctx.getString(R.string.notif_vat_title),
                    ctx.getString(R.string.notif_vat_text)
                )
            }

            // 3b) Лимит zwolnienia z VAT ПРЕВЫШЕН, а регистрация ещё не подтверждена —
            // это уже юридически срочный вопрос (7 дней на подачу VAT-R), поэтому
            // повторяем оповещение до N раз в день (см. настройку частоты в Ustawieniach),
            // а не один раз, как для мягких предупреждений выше.
            if (limits.vat.exceeded && !VatComplianceHelper.isVatRegisteredConfirmed(prefs)) {
                notifyRepeatable(
                    prefs, "vat_exceeded_${TaxHelper.currentYear()}",
                    ctx.getString(R.string.notif_vat_exceeded_critical_title),
                    ctx.getString(R.string.notif_vat_exceeded_critical_text)
                )
            }

            // 3c) Лимит 20 000 zł gotówki dla osób fizycznych ПРЕВЫШЕН, а kasa fiskalna
            // ещё не подтверждена — тоже повторяем до N раз в день.
            val cashStatus = CashLimitHelper.computeCurrentYear(applicationContext)
            if (cashStatus.exceeded && !VatComplianceHelper.isKasaFiskalnaConfirmed(prefs)) {
                notifyRepeatable(
                    prefs, "kasa_exceeded_${TaxHelper.currentYear()}",
                    ctx.getString(R.string.notif_kasa_exceeded_title),
                    ctx.getString(R.string.notif_kasa_exceeded_text)
                )
            }

            // 4) Напоминание об авансовом платеже — до 20 числа каждого месяца.
            val cal = Calendar.getInstance()
            val day = cal.get(Calendar.DAY_OF_MONTH)
            if (day in 15..20) {
                notifyOnce(
                    prefs, "advance_${cal.get(Calendar.YEAR)}_${cal.get(Calendar.MONTH)}",
                    ctx.getString(R.string.notif_advance_title),
                    ctx.getString(R.string.notif_advance_text)
                )
            }

            // 5) Напоминание о сроке подачи PIT (15 lutego – 30 kwietnia).
            val month = cal.get(Calendar.MONTH) // 0-based
            if (month == Calendar.FEBRUARY || month == Calendar.MARCH ||
                (month == Calendar.APRIL && day <= 30)
            ) {
                notifyOnce(
                    prefs, "pit_deadline_${cal.get(Calendar.YEAR)}_$month",
                    ctx.getString(R.string.notif_pit_deadline_title),
                    ctx.getString(R.string.notif_pit_deadline_text)
                )
            }

            return Result.success()
        } catch (e: Exception) {
            return Result.retry()
        }
    }

    private fun notifyOnce(prefs: android.content.SharedPreferences, key: String, title: String, text: String) {
        if (prefs.getBoolean("notif_shown_$key", false)) return
        prefs.edit().putBoolean("notif_shown_$key", true).apply()
        showNotification(applicationContext, key.hashCode(), title, text)
    }

    /** Как notifyOnce, но допускает до N повторов В ТЕЧЕНИЕ ОДНОГО ДНЯ — N задаётся
     *  пользователем в Ustawieniach (zob. VatComplianceHelper.getPushFrequency,
     *  по умолчанию 3). Используется только для действительно срочных ситуаций
     *  (превышен лимit VAT/kasy, просроченная фактура) — обычные предупреждения
     *  "приближаетесь к лимиту" по-прежнему используют notifyOnce (раз в день). */
    private fun notifyRepeatable(prefs: android.content.SharedPreferences, key: String, title: String, text: String) {
        notifyRepeatableStatic(applicationContext, prefs, key, title, text)
    }

    companion object {
        private val SDF_DAY = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
        const val CHANNEL_ID = "fa_limits_channel"
        private const val UNIQUE_WORK_NAME = "fa_limits_daily_check"

        /** Общая реализация повторяемого (до N раз/день) оповещения — используется
         *  и здесь, и в InvoiceReminderWorker (просроченные фактуры). */
        fun notifyRepeatableStatic(
            context: Context, prefs: android.content.SharedPreferences,
            key: String, title: String, text: String, targetActivity: Class<*>? = null
        ) {
            val today = SDF_DAY.format(java.util.Date())
            val maxPerDay = VatComplianceHelper.getPushFrequency(prefs)
            val countKey = "notif_count_${key}_$today"
            val shown = prefs.getInt(countKey, 0)
            if (shown >= maxPerDay) return
            prefs.edit().putInt(countKey, shown + 1).apply()
            showNotification(context, (key + "_" + shown).hashCode(), title, text, targetActivity)
        }

        fun createChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.notif_channel_name),
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = context.getString(R.string.notif_channel_description)
                }
                mgr.createNotificationChannel(channel)
            }
        }

        fun showNotification(context: Context, id: Int, title: String, text: String, targetActivity: Class<*>? = null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val granted = ActivityCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED
                if (!granted) return
            }
            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setAutoCancel(true)
            // Тап по уведомлению должен открывать соответствующий экран приложения —
            // раньше при тапе ничего не происходило, так как contentIntent не задавался.
            if (targetActivity != null) {
                val openIntent = Intent(context, targetActivity).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val pendingIntent = PendingIntent.getActivity(
                    context, id, openIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                builder.setContentIntent(pendingIntent)
            }
            val notification = builder.build()
            androidx.core.app.NotificationManagerCompat.from(context).apply {
                try {
                    notify(id, notification)
                } catch (e: SecurityException) {
                    // Разрешение отозвано между проверкой и вызовом — просто пропускаем.
                }
            }
        }

        /** Планирует проверку лимитов/сроков. Интервал — 1 час (не 24), потому что
         *  критические оповещения (превышен лимит VAT/kasy) теперь могут повторяться
         *  до N раз в день (см. notifyRepeatableStatic, частота задаётся пользователем
         *  в Ustawieniach) — при проверке раз в сутки повторы были бы невозможны.
         *  Обычные мягкие предупреждения (notifyOnce) по-прежнему показываются не
         *  чаще одного раза в день независимо от того, как часто отрабатывает воркер. */
        fun schedule(context: Context) {
            createChannel(context)
            val request = PeriodicWorkRequestBuilder<LimitsNotificationWorker>(1, TimeUnit.HOURS).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                request
            )
        }
    }
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_LIMITSNOTIFICATIONWORKER_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/LimitsNotificationWorker.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/InvoiceReminderWorker.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/InvoiceReminderWorker.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEREMINDERWORKER_KT'
package com.example.fa_ksiegowy

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Ежедневная проверка неоплаченных (PENDING) фактур. Использует тот же
 * канал уведомлений, что и LimitsNotificationWorker. Каждое напоминание
 * ("скоро срок" / "просрочена") показывается только один раз на фактуру —
 * состояние хранится в prefs, чтобы не спамить при каждом запуске воркера.
 */
class InvoiceReminderWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        return try {
            // Уведомления должны быть на языке, выбранном В ПРИЛОЖЕНИИ (LocaleHelper),
            // а не на системном языке телефона — раньше ctx.getString(...)
            // брал системную локаль напрямую, из-за чего уведомления могли отличаться
            // от языка интерфейса приложения.
            val ctx = LocaleHelper.applyLocale(applicationContext)
            val dao = AppDatabase.getInstance(applicationContext).invoiceDao()
            val prefs = applicationContext.getSharedPreferences("settings", Context.MODE_PRIVATE)
            val now = System.currentTimeMillis()
            val threeDaysMs = 3L * 24 * 60 * 60 * 1000

            val pending = dao.getAll().filter { it.status == InvoiceStatus.PENDING && it.dueDateMillis != null }
            for (inv in pending) {
                val due = inv.dueDateMillis ?: continue
                when {
                    due < now -> LimitsNotificationWorker.notifyRepeatableStatic(
                        applicationContext, prefs, "invoice_overdue_${inv.id}",
                        ctx.getString(R.string.notif_invoice_overdue_title),
                        ctx.getString(R.string.notif_invoice_overdue_text, inv.buyerName, inv.invoiceNumber),
                        InvoiceHistoryActivity::class.java
                    )
                    due - now <= threeDaysMs -> notifyOnce(
                        prefs, "invoice_due_soon_${inv.id}",
                        ctx.getString(R.string.notif_invoice_due_soon_title),
                        ctx.getString(R.string.notif_invoice_due_soon_text, inv.buyerName, inv.invoiceNumber),
                        InvoiceHistoryActivity::class.java
                    )
                }
            }
            Result.success()
        } catch (e: Exception) {
            Result.retry()
        }
    }

    private fun notifyOnce(
        prefs: android.content.SharedPreferences, key: String, title: String, text: String,
        targetActivity: Class<*>? = null
    ) {
        if (prefs.getBoolean("notif_shown_$key", false)) return
        prefs.edit().putBoolean("notif_shown_$key", true).apply()
        LimitsNotificationWorker.showNotification(applicationContext, key.hashCode(), title, text, targetActivity)
    }

    companion object {
        private const val UNIQUE_WORK_NAME = "fa_invoice_reminders_daily_check"

        /** Планирует проверку сроков оплаты фактур. Интервал — 1 час (не 24), чтобы
         *  оповещения о просроченных фактурах могли повторяться до N раз в день —
         *  N задаётся пользователем в Ustawieniach (zob. VatComplianceHelper). */
        fun schedule(context: Context) {
            LimitsNotificationWorker.createChannel(context)
            val request = PeriodicWorkRequestBuilder<InvoiceReminderWorker>(1, TimeUnit.HOURS).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                request
            )
        }
    }
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEREMINDERWORKER_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/InvoiceReminderWorker.kt"

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

    <Button
        android:id="@+id/btn_invoice_history"
        android:layout_width="match_parent"
        android:layout_height="48dp"
        android:layout_marginBottom="16dp"
        android:background="@drawable/btn_pill_outline"
        android:text="@string/invoice_history_title"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="14sp"/>

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
        <EditText android:id="@+id/et_seller_bank_account" style="@style/InvoiceInput" android:hint="@string/seller_bank_account" android:inputType="text"/>

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

        <!-- Позиции фактуры (до 20 шт., товар или услуга) — заполняются динамически,
             см. AddInvoiceActivity.addItemRow/item_invoice_line.xml. Кнопка "Dodaj
             towary z magazynu" добавляет позиции сюда же, а не отдельным полем. -->
        <LinearLayout
            android:id="@+id/ll_invoice_items"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"/>

        <Button
            android:id="@+id/btn_add_item_row"
            android:layout_width="match_parent"
            android:layout_height="48dp"
            android:layout_marginBottom="10dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/add_invoice_item_row"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="14sp"/>

        <TextView
            android:id="@+id/tv_invoice_total"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:textColor="@color/accent_cyan"
            android:textSize="15sp"
            android:textStyle="bold"
            android:gravity="end"
            android:layout_marginBottom="10dp"/>

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
            android:textSize="13sp"/>

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

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical"
            android:layout_marginBottom="14dp">
            <Switch
                android:id="@+id/sw_invoice_paid"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:checked="true"
                android:text="@string/invoice_paid_switch_label"
                android:textColor="@color/text_primary"/>
        </LinearLayout>

        <Button
            android:id="@+id/btn_due_date"
            android:layout_width="match_parent"
            android:layout_height="56dp"
            android:layout_marginBottom="14dp"
            android:background="@drawable/input_field_bg"
            android:text="@string/invoice_due_date_label"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="15sp"
            android:gravity="start|center_vertical"
            android:paddingStart="18dp"
            android:paddingEnd="18dp"
            android:visibility="gone"/>

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
                android:background="@drawable/btn_pill_payment_selected"
                android:text="@string/payment_method_cash"
                android:textAllCaps="false" android:textColor="@color/text_primary" android:textSize="13sp"/>

            <Button
                android:id="@+id/btn_payment_transfer"
                android:layout_width="0dp" android:layout_height="46dp" android:layout_weight="1"
                android:layout_marginStart="3dp" android:layout_marginEnd="3dp"
                android:background="@drawable/btn_pill_payment_unselected"
                android:text="@string/payment_method_transfer"
                android:textAllCaps="false" android:textColor="@color/text_primary" android:textSize="13sp"/>

            <Button
                android:id="@+id/btn_payment_blik"
                android:layout_width="0dp" android:layout_height="46dp" android:layout_weight="1"
                android:layout_marginStart="6dp"
                android:background="@drawable/btn_pill_payment_unselected"
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

    <!-- Blokada wystawiania faktur: pokazywana, gdy przekroczono limit VAT (240 000 zł)
         lub limit gotówki dla osób fizycznych (20 000 zł), a odpowiednie potwierdzenie
         nie zostało jeszcze złożone w Ustawieniach (zob. VatComplianceHelper). -->
    <TextView
        android:id="@+id/tv_compliance_block_banner"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:background="@drawable/card_bg"
        android:backgroundTint="#33FF3B30"
        android:padding="14dp"
        android:layout_marginBottom="14dp"
        android:textColor="#FF3B30"
        android:textSize="13sp"
        android:textStyle="bold"
        android:visibility="gone"/>

    <!-- Stawka VAT — widoczna tylko gdy sprzedawca jest już zarejestrowanym podatnikiem VAT. -->
    <Button
        android:id="@+id/btn_vat_rate"
        android:layout_width="match_parent"
        android:layout_height="52dp"
        android:layout_marginBottom="10dp"
        android:background="@drawable/input_field_bg"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="14sp"
        android:gravity="start|center_vertical"
        android:paddingStart="16dp"
        android:paddingEnd="16dp"
        android:visibility="gone"/>

    <!-- "Do paragonu" — widoczne tylko po potwierdzeniu posiadania kasy fiskalnej. -->
    <LinearLayout
        android:id="@+id/row_is_receipt"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:gravity="center_vertical"
        android:layout_marginBottom="14dp"
        android:visibility="gone">

        <TextView
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="@string/invoice_is_receipt_label"
            android:textColor="@color/text_primary"
            android:textSize="14sp"/>

        <Switch
            android:id="@+id/sw_is_receipt"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"/>

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

mkdir -p "$(dirname "app/src/main/res/layout/activity_settings_tax.xml")"
cat > app/src/main/res/layout/activity_settings_tax.xml << 'EOF_APP_SRC_MAIN_RES_LAYOUT_ACTIVITY_SETTINGS_TAX_XML'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent" android:layout_height="match_parent"
    android:fillViewport="true">

<LinearLayout
    android:orientation="vertical" android:padding="24dp"
    android:layout_width="match_parent" android:layout_height="wrap_content">

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/settings_menu_tax" android:textSize="22sp" android:textStyle="bold"
        android:textColor="@color/accent_cyan" android:layout_marginBottom="16dp"/>

    <!-- Форма деятельности -->
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/activity_type_title" android:textSize="16sp" android:textStyle="bold"
        android:textColor="@color/text_primary" android:layout_marginBottom="4dp"/>
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/activity_type_hint" android:textSize="12sp"
        android:textColor="#9AA0C0" android:layout_marginBottom="10dp"/>

    <RadioGroup android:id="@+id/rg_activity_type" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:background="@drawable/card_bg" android:padding="12dp"
        android:layout_marginBottom="16dp">

        <RadioButton android:id="@+id/rb_niezarejestrowana" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/activity_type_niezarejestrowana" android:textColor="@color/text_primary" android:textSize="14sp"
            android:paddingBottom="10dp"/>
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/activity_type_niezarejestrowana_desc" android:textSize="12sp"
            android:textColor="#9AA0C0" android:paddingStart="32dp" android:paddingBottom="14dp"/>

        <RadioButton android:id="@+id/rb_jdg_skala" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/activity_type_jdg_skala" android:textColor="@color/text_primary" android:textSize="14sp"
            android:paddingBottom="10dp"/>

        <RadioButton android:id="@+id/rb_jdg_liniowy" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/activity_type_jdg_liniowy" android:textColor="@color/text_primary" android:textSize="14sp"
            android:paddingBottom="10dp"/>

        <RadioButton android:id="@+id/rb_jdg_ryczalt" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/activity_type_jdg_ryczalt" android:textColor="@color/text_primary" android:textSize="14sp"/>

    </RadioGroup>

    <!-- Ставка ryczałtu больше не задаётся здесь одной общей цифрой — теперь она
         выбирается для каждой операции отдельно (доход / позиция фактуры), так как
         один человек может продавать товары и оказывать услуги с разными ставками. -->
    <LinearLayout android:id="@+id/layout_ryczalt_rate_hint" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:background="@drawable/card_bg" android:padding="14dp"
        android:visibility="gone" android:layout_marginBottom="16dp">
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/ryczalt_rate_moved_title" android:textSize="13sp" android:textStyle="bold"
            android:textColor="@color/accent_cyan" android:layout_marginBottom="4dp"/>
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/ryczalt_rate_moved_hint" android:textSize="12sp"
            android:textColor="@color/text_secondary"/>
    </LinearLayout>

    <!-- Минимальное вознаграждение (для лимита 75%) — актуально ТОЛЬКО для
         niezarejestrowana, для любого Zarejestrowana JDG блок скрыт целиком. -->
    <LinearLayout android:id="@+id/layout_min_wage" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical">
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/min_wage_label" android:textSize="13sp"
            android:textColor="@color/text_secondary" android:layout_marginBottom="8dp"/>
        <EditText android:id="@+id/et_min_wage" android:layout_width="match_parent" android:layout_height="56dp"
            android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:textColor="@color/text_primary" android:inputType="numberDecimal"
            android:layout_marginBottom="8dp"/>
        <TextView android:id="@+id/tv_monthly_limit_preview" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:textSize="12sp" android:textColor="#9AA0C0" android:layout_marginBottom="20dp"/>
    </LinearLayout>

    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:background="@drawable/card_bg" android:padding="16dp"
        android:layout_marginBottom="24dp">
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/tax_scale_title" android:textSize="15sp" android:textStyle="bold"
            android:textColor="@color/text_primary" android:layout_marginBottom="8dp"/>
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/tax_scale_description" android:textSize="13sp"
            android:textColor="@color/text_secondary"/>
    </LinearLayout>

    <!-- VAT: pole z galką pojawia się dopiero po przekroczeniu limitu 240 000 zł
         (widoczne też po już złożonym potwierdzeniu — jako informacja bez możliwości edycji). -->
    <LinearLayout android:id="@+id/layout_vat_compliance" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:background="@drawable/card_bg" android:padding="14dp"
        android:visibility="gone" android:layout_marginBottom="16dp">
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/vat_compliance_title" android:textSize="15sp" android:textStyle="bold"
            android:textColor="#FF3B30" android:layout_marginBottom="6dp"/>
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/vat_compliance_hint" android:textSize="12sp"
            android:textColor="@color/text_secondary" android:layout_marginBottom="10dp"/>
        <CheckBox android:id="@+id/cb_vat_registered" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/cb_vat_registered_label" android:textColor="@color/text_primary" android:textSize="13sp"/>
    </LinearLayout>

    <!-- Kasa fiskalna: analogiczne pole z galką po przekroczeniu limitu 20 000 zł gotówki. -->
    <LinearLayout android:id="@+id/layout_kasa_compliance" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:background="@drawable/card_bg" android:padding="14dp"
        android:visibility="gone" android:layout_marginBottom="16dp">
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/kasa_compliance_title" android:textSize="15sp" android:textStyle="bold"
            android:textColor="#FF3B30" android:layout_marginBottom="6dp"/>
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/kasa_compliance_hint" android:textSize="12sp"
            android:textColor="@color/text_secondary" android:layout_marginBottom="10dp"/>
        <CheckBox android:id="@+id/cb_kasa_fiskalna" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/cb_kasa_label" android:textColor="@color/text_primary" android:textSize="13sp"/>
    </LinearLayout>

    <!-- Częstotliwość powiadomień push — ile razy dziennie mogą przychodzić alerty
         o przekroczonych limitach i zaległych fakturach. -->
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/push_frequency_title" android:textSize="16sp" android:textStyle="bold"
        android:textColor="@color/text_primary" android:layout_marginBottom="4dp"/>
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/push_frequency_hint" android:textSize="12sp"
        android:textColor="#9AA0C0" android:layout_marginBottom="10dp"/>
    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="horizontal" android:layout_marginBottom="24dp">
        <EditText android:id="@+id/et_push_frequency" android:layout_width="0dp" android:layout_height="56dp"
            android:layout_weight="1" android:layout_marginEnd="10dp"
            android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:textColor="@color/text_primary" android:inputType="number" android:maxLength="2"/>
        <Button android:id="@+id/btn_save_push_frequency" android:layout_width="wrap_content" android:layout_height="56dp"
            android:text="@string/save" android:textAllCaps="false" android:textSize="14sp"
            android:paddingStart="20dp" android:paddingEnd="20dp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_primary"/>
    </LinearLayout>

    <TextView android:id="@+id/tv_other_income_label" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/other_income_title" android:textSize="18sp"
        android:textColor="@color/text_primary" android:layout_marginBottom="6dp"/>

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/other_income_hint" android:textSize="13sp"
        android:textColor="#9AA0C0" android:layout_marginBottom="10dp"/>

    <EditText android:id="@+id/et_other_income" android:layout_width="match_parent" android:layout_height="56dp"
        android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
        android:textColor="@color/text_primary" android:inputType="numberDecimal"
        android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_save_other_income" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/save" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_primary"/>

</LinearLayout>
</ScrollView>
EOF_APP_SRC_MAIN_RES_LAYOUT_ACTIVITY_SETTINGS_TAX_XML
echo "OK: app/src/main/res/layout/activity_settings_tax.xml"

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
    <string name="about_description">FinArs is a comprehensive app for managing the finances of unregistered business activity and sole proprietorships (JDG). Track income and expenses, monitor limits, automatically calculate taxes, issue invoices, and generate ready-made reports and tax returns — all in one place, with the full history of operations always at hand.\n\n\uD83D\uDCCA Finances and taxes\n\uD83D\uDCB0 Income and expense tracking with attached receipts\n\uD83D\uDCC8 Automatic profit and tax calculation (12%/32% scale, 19% flat, lump-sum)\n\uD83D\uDD01 Recurring transactions (rent, subscriptions) created automatically every month\n\uD83D\uDEA6 Limit tracking: unregistered activity, 120,000 zł tax bracket, VAT exemption (240,000 zł)\n\uD83D\uDD14 Notifications when limits are approaching or exceeded\n\n\uD83E\uDDFE Invoices and receipts (Pro)\n\uD83D\uDCDD Issue invoices/receipts to individuals and companies with PDF generation\n\u2705 Statuses: Paid / Pending / Overdue, plus due-date reminders\n\uD83D\uDCB5 Tracking of the annual 20,000 zł cash-sales limit for private individuals\n\uD83D\uDD0D Invoice history with search and filters\n\n\uD83D\uDCC4 Reports and tax returns\n\uD83D\uDCCA Income/expense chart for the last 6 months\n\uD83D\uDCE5 Export monthly report (free), yearly and custom-period reports (Pro) to Excel with receipts\n\uD83E\uDDEE Generate PIT-36 / PIT-36L / PIT-28 tax returns — helper PDF and official form filling (Pro)\n\n\uD83D\uDD12 Security and convenience\n\uD83D\uDD10 App lock with PIN code and fingerprint / face unlock\n\uD83D\uDCBE Backup and restore your data (Pro)\n\uD83C\uDF19 Modern dark interface\n\uD83C\uDF0D Available in Polish, Russian and English\n\uD83D\uDD12 All data is stored locally on your device\n\nContact: p.arsenii@interia.pl</string>
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
    <string name="ryczalt_rate_moved_title">Ryczałt rate by category</string>
    <string name="ryczalt_rate_moved_hint">Each income and each invoice item has its own category — goods, production, services, IT, medical, freelance. The tax rate is applied automatically based on the category chosen.</string>
    <string name="min_wage_label">Minimum monthly wage (zł) — used to calculate the unregistered-activity limit</string>
    <string name="monthly_limit_preview" formatted="false">Monthly limit (75%): %1$,.2f zł</string>

    <!-- Main screen limit gauges -->
    <string name="limits_title">Limits</string>
    <string name="limit_monthly_label">Unregistered activity, this month: %1$s / %2$s zł</string>
    <string name="limit_bracket_label">First tax bracket (120,000 zł/year): %1$s / %2$s zł</string>
    <string name="limit_vat_label">VAT exemption (240,000 zł/year): %1$s / %2$s zł</string>
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
    <string name="notif_vat_text">Your yearly revenue is close to 240,000 zł — the VAT exemption threshold.</string>
    <string name="notif_vat_exceeded_critical_title">VAT limit exceeded</string>
    <string name="notif_vat_exceeded_critical_text" formatted="false">You have exceeded the 240,000 zł VAT exemption limit. File form VAT-R within 7 days and confirm your registration in Settings — invoicing is blocked until then.</string>
    <string name="notif_kasa_exceeded_title">Fiscal cash register may be required</string>
    <string name="notif_kasa_exceeded_text" formatted="false">You have exceeded the 20,000 zł annual cash-sales limit for private individuals. Confirm in Settings once you have a kasa fiskalna — invoicing is blocked until then.</string>
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
    <string name="buyer_name">First and last name / company name</string>
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
    <string name="invoice_blocked_toast">Invoicing is blocked — confirm your VAT/cash-register status in Settings first</string>
    <string name="invoice_is_receipt_label">This invoice is issued as a receipt (paragon)</string>
    <string name="vat_rate_choose">Choose VAT rate</string>
    <string name="vat_rate_selected" formatted="false">VAT rate: %1$s</string>
    <string name="vat_rate_picker_title">VAT rate</string>
    <string name="vat_rate_required_error">Choose a VAT rate for this invoice</string>
    <string name="vat_rate_23">23% (standard)</string>
    <string name="vat_rate_8">8% (reduced)</string>
    <string name="vat_rate_5">5% (minimum)</string>
    <string name="vat_rate_0">0% (export/WDT)</string>
    <string name="vat_rate_zw">zw (exempt)</string>
    <string name="vat_rate_np">np (not subject to tax)</string>
    <string name="vat_limit_block_message" formatted="false">You have exceeded the 240,000 zł VAT exemption limit. Confirm your VAT-R registration in Settings → Taxes to keep invoicing.</string>
    <string name="kasa_limit_block_message" formatted="false">You have exceeded the 20,000 zł annual cash-sales limit for private individuals. Confirm that you have a kasa fiskalna in Settings → Taxes to keep invoicing.</string>

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
    <string name="invoice_pdf_table_netto">Net</string>
    <string name="invoice_pdf_table_vat_rate">VAT rate</string>
    <string name="invoice_pdf_table_vat_amount">VAT amount</string>
    <string name="invoice_pdf_table_brutto">Gross</string>
    <string name="invoice_pdf_receipt_label">Issued as a receipt (paragon) for a private individual</string>
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
    <string name="product_price">Purchase price</string>
    <string name="product_price_sell">Sale price</string>
    <string name="product_margin">Margin %</string>
    <string name="product_margin_hint">Enter sale price directly, or enter a margin % to calculate it automatically from the purchase price (e.g. 60 = purchase price +60%).</string>
    <string name="gallery_scan_receipt_button">Scan receipt from gallery</string>
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

    <!-- Update 43: inventory PDF report + history + barcode scan, receipt item parsing fix -->
    <string name="inventory_scan_button">Scan product</string>
    <string name="inventory_history_button">Inventory history</string>
    <string name="inventory_scan_not_found">No product found for code %1$s</string>
    <string name="inventory_scan_found">%1$s: %2$s</string>
    <string name="inventory_history_title">Inventory history</string>
    <string name="inventory_history_empty">No inventory counts yet</string>
    <string name="inventory_session_number">Inventory #%1$s</string>
    <string name="inventory_session_meta">%1$s items · changed: %2$s</string>
    <string name="inventory_session_meta_sell">Missed/extra revenue: %1$s</string>
    <string name="inventory_pdf_title">Inventory report #%1$s</string>
    <string name="inventory_pdf_date">Date</string>
    <string name="inventory_pdf_col_product">Product</string>
    <string name="inventory_pdf_col_unit">Unit</string>
    <string name="inventory_pdf_col_before">Before</string>
    <string name="inventory_pdf_col_after">After</string>
    <string name="inventory_pdf_col_diff">Diff</string>
    <string name="inventory_pdf_col_diff_value">Cost diff</string>
    <string name="inventory_pdf_col_diff_value_sell">Missed revenue</string>
    <string name="inventory_pdf_total_products">Total items checked</string>
    <string name="inventory_pdf_total_changed">Items changed</string>
    <string name="inventory_pdf_total_diff_value">Total cost value difference</string>
    <string name="inventory_pdf_total_diff_value_sell">Total missed/extra revenue (sale price)</string>

    <!-- Ryczałt categories: rate applied per transaction instead of one flat setting -->
    <string name="ryczalt_cat_3">3% — goods (towar)</string>
    <string name="ryczalt_cat_5_5">5.5% — production / manufactured products</string>
    <string name="ryczalt_cat_8_5">8.5% — services</string>
    <string name="ryczalt_cat_12">12% — IT services</string>
    <string name="ryczalt_cat_14">14% — medical services</string>
    <string name="ryczalt_cat_17">17% — freelance profession</string>
    <string name="ryczalt_category_picker_title">Ryczałt category</string>
    <string name="ryczalt_category_choose">Choose ryczałt category ▾</string>
    <string name="ryczalt_category_selected">Category: %1$s</string>
    <string name="ryczalt_category_required_error">Choose a ryczałt category for every item</string>
    <string name="income_ryczalt_category_required_error">Choose a ryczałt category for this income</string>

    <!-- VAT / kasa fiskalna compliance (Settings → Taxes) -->
    <string name="vat_compliance_title">VAT registration</string>
    <string name="vat_compliance_hint" formatted="false">You have exceeded the 240,000 zł annual VAT exemption limit. You must file form VAT-R within 7 days of the day you crossed the limit, and start charging VAT on the transaction that crossed it. Confirm below once you have registered — invoicing stays blocked until you do.</string>
    <string name="cb_vat_registered_label">I confirm I have registered as a VAT payer (filed VAT-R)</string>
    <string name="cb_vat_registered_confirmed_label">Confirmed: registered as a VAT payer</string>
    <string name="kasa_compliance_title">Fiscal cash register (kasa fiskalna)</string>
    <string name="kasa_compliance_hint">You have exceeded the 20,000 zł annual limit of cash sales to private individuals. A fiscal cash register may now be required. Confirm below once you have one — invoicing stays blocked until you do.</string>
    <string name="cb_kasa_label">I confirm I have a fiscal cash register (kasa fiskalna)</string>
    <string name="cb_kasa_confirmed_label">Confirmed: fiscal cash register in use</string>
    <string name="vat_confirm_dialog_title">Confirm VAT registration</string>
    <string name="vat_confirm_dialog_message">This confirms you have filed VAT-R and are now a VAT payer. This cannot be undone in the app. Continue?</string>
    <string name="kasa_confirm_dialog_title">Confirm fiscal cash register</string>
    <string name="kasa_confirm_dialog_message">This confirms you have a fiscal cash register (kasa fiskalna). This cannot be undone in the app. Continue?</string>
    <string name="confirm_yes">Yes, confirm</string>
    <string name="confirm_cancel">Cancel</string>

    <!-- Push notification frequency (Settings → Taxes) -->
    <string name="push_frequency_title">Push notification frequency</string>
    <string name="push_frequency_hint">How many times per day you can receive alerts about exceeded limits and overdue invoices (1–50).</string>
    <string name="push_frequency_saved">Notification frequency saved</string>
    <string name="push_frequency_invalid">Enter a number between 1 and 50</string>
    <string name="income_ryczalt_category_label">Ryczałt category for this income</string>

    <!-- Multi-item invoices -->
    <string name="invoice_item_number_label">Item %1$d</string>
    <string name="add_invoice_item_row">+ Add item</string>
    <string name="invoice_items_limit_reached">You can add up to %1$d items per invoice</string>
    <string name="invoice_item_min_required">An invoice needs at least one item</string>
    <string name="invoice_total_label">Total: %1$s zł</string>
    <string name="item_qty_hint">Qty</string>
    <string name="invoice_income_comment">Invoice #%1$d — %2$s</string>
</resources>
EOF_APP_SRC_MAIN_RES_VALUES_STRINGS_XML
echo "OK: app/src/main/res/values/strings.xml"

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
    <string name="about_description">FinArs to kompleksowa aplikacja do zarządzania finansami działalności nierejestrowanej i jednoosobowej działalności gospodarczej (JDG). Śledź przychody i wydatki, kontroluj limity, automatycznie licz podatki, wystawiaj faktury i generuj gotowe raporty oraz deklaracje PIT — wszystko w jednym miejscu, z pełną historią operacji zawsze pod ręką.\n\n\uD83D\uDCCA Finanse i podatki\n\uD83D\uDCB0 Ewidencja przychodów i wydatków z załącznikami paragonów\n\uD83D\uDCC8 Automatyczne obliczanie zysku i podatku (skala 12%/32%, liniowy 19%, ryczałt)\n\uD83D\uDD01 Transakcje cykliczne (czynsz, abonamenty) tworzone automatycznie co miesiąc\n\uD83D\uDEA6 Kontrola limitów: działalność nierejestrowana, próg 120 000 zł, zwolnienie z VAT (240 000 zł)\n\uD83D\uDD14 Powiadomienia o zbliżających się i przekroczonych limitach\n\n\uD83E\uDDFE Faktury i rachunki (Pro)\n\uD83D\uDCDD Wystawianie faktur/rachunków dla osób fizycznych i firm z generowaniem PDF\n\u2705 Statusy: Zapłacona / Oczekuje na zapłatę / Zaległa, plus przypomnienia o terminie płatności\n\uD83D\uDCB5 Kontrola rocznego limitu gotówki (20 000 zł) dla sprzedaży osobom fizycznym\n\uD83D\uDD0D Historia faktur z wyszukiwaniem i filtrami\n\n\uD83D\uDCC4 Raporty i deklaracje\n\uD83D\uDCCA Wykres przychodów i wydatków za ostatnie 6 miesięcy\n\uD83D\uDCE5 Eksport raportu miesięcznego (bezpłatnie), rocznego i za dowolny okres (Pro) do Excela wraz z paragonami\n\uD83E\uDDEE Generowanie deklaracji PIT-36 / PIT-36L / PIT-28 — pomocniczy PDF oraz wypełnienie oficjalnego formularza (Pro)\n\n\uD83D\uDD12 Bezpieczeństwo i wygoda\n\uD83D\uDD10 Blokada aplikacji kodem PIN oraz odciskiem palca / twarzą\n\uD83D\uDCBE Kopia zapasowa i przywracanie danych (Pro)\n\uD83C\uDF19 Nowoczesny ciemny interfejs\n\uD83C\uDF0D Dostępne w języku polskim, rosyjskim i angielskim\n\uD83D\uDD12 Wszystkie dane są przechowywane lokalnie na urządzeniu\n\nKontakt: p.arsenii@interia.pl</string>
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
    <string name="ryczalt_rate_moved_title">Stawka ryczałtu według kategorii</string>
    <string name="ryczalt_rate_moved_hint">Każdy przychód i każda pozycja faktury ma swoją kategorię — towar, produkcja, usługi, usługi IT, usługi medyczne, wolny zawód. Stawka podatku dobierana jest automatycznie na podstawie wybranej kategorii.</string>
    <string name="min_wage_label">Minimalne wynagrodzenie miesięczne (zł) — do obliczenia limitu działalności nierejestrowanej</string>
    <string name="monthly_limit_preview" formatted="false">Limit miesięczny (75%): %1$,.2f zł</string>

    <!-- Wskaźniki limitów na ekranie głównym -->
    <string name="limits_title">Limity</string>
    <string name="limit_monthly_label">Działalność nierejestrowana, ten miesiąc: %1$s / %2$s zł</string>
    <string name="limit_bracket_label">Pierwszy próg podatkowy (120 000 zł/rok): %1$s / %2$s zł</string>
    <string name="limit_vat_label">Zwolnienie z VAT (240 000 zł/rok): %1$s / %2$s zł</string>
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
    <string name="notif_vat_text">Roczny przychód zbliża się do 240 000 zł — progu zwolnienia z VAT.</string>
    <string name="notif_vat_exceeded_critical_title">Przekroczono limit VAT</string>
    <string name="notif_vat_exceeded_critical_text" formatted="false">Przekroczono roczny limit zwolnienia z VAT (240 000 zł). Złóż VAT-R w ciągu 7 dni i potwierdź rejestrację w Ustawieniach — do tego czasu wystawianie faktur jest zablokowane.</string>
    <string name="notif_kasa_exceeded_title">Może być wymagana kasa fiskalna</string>
    <string name="notif_kasa_exceeded_text" formatted="false">Przekroczono roczny limit 20 000 zł sprzedaży gotówkowej dla osób fizycznych. Potwierdź w Ustawieniach posiadanie kasy fiskalnej — do tego czasu wystawianie faktur jest zablokowane.</string>
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
    <string name="buyer_name">Imię i nazwisko / nazwa firmy</string>
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
    <string name="invoice_blocked_toast">Wystawianie faktur zablokowane — najpierw potwierdź status VAT/kasy fiskalnej w Ustawieniach</string>
    <string name="invoice_is_receipt_label">Ta faktura jest wystawiana jako paragon</string>
    <string name="vat_rate_choose">Wybierz stawkę VAT</string>
    <string name="vat_rate_selected" formatted="false">Stawka VAT: %1$s</string>
    <string name="vat_rate_picker_title">Stawka VAT</string>
    <string name="vat_rate_required_error">Wybierz stawkę VAT dla tej faktury</string>
    <string name="vat_rate_23">23% (podstawowa)</string>
    <string name="vat_rate_8">8% (obniżona)</string>
    <string name="vat_rate_5">5% (minimalna)</string>
    <string name="vat_rate_0">0% (eksport/WDT)</string>
    <string name="vat_rate_zw">zw (zwolnienie)</string>
    <string name="vat_rate_np">np (nie podlega opodatkowaniu)</string>
    <string name="vat_limit_block_message" formatted="false">Przekroczono roczny limit zwolnienia z VAT (240 000 zł). Potwierdź rejestrację VAT-R w Ustawienia → Podatki, aby dalej wystawiać faktury.</string>
    <string name="kasa_limit_block_message" formatted="false">Przekroczono roczny limit 20 000 zł sprzedaży gotówkowej dla osób fizycznych. Potwierdź posiadanie kasy fiskalnej w Ustawienia → Podatki, aby dalej wystawiać faktury.</string>

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
    <string name="invoice_pdf_table_netto">Netto</string>
    <string name="invoice_pdf_table_vat_rate">Stawka VAT</string>
    <string name="invoice_pdf_table_vat_amount">Kwota VAT</string>
    <string name="invoice_pdf_table_brutto">Brutto</string>
    <string name="invoice_pdf_receipt_label">Wystawiono jako paragon dla osoby fizycznej</string>
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
    <string name="product_price">Cena zakupu</string>
    <string name="product_price_sell">Cena sprzedaży</string>
    <string name="product_margin">Marża %</string>
    <string name="product_margin_hint">Wpisz cenę sprzedaży bezpośrednio albo podaj % marży — cena sprzedaży zostanie wyliczona automatycznie od ceny zakupu (np. 60 = zakup +60%).</string>
    <string name="gallery_scan_receipt_button">Skanuj paragon z galerii</string>
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

    <!-- Update 43: raport PDF inwentaryzacji + historia + skanowanie kodów, naprawa parsowania pozycji paragonu -->
    <string name="inventory_scan_button">Skanuj towar</string>
    <string name="inventory_history_button">Historia inwentaryzacji</string>
    <string name="inventory_scan_not_found">Nie znaleziono produktu o kodzie %1$s</string>
    <string name="inventory_scan_found">%1$s: %2$s</string>
    <string name="inventory_history_title">Historia inwentaryzacji</string>
    <string name="inventory_history_empty">Brak przeprowadzonych inwentaryzacji</string>
    <string name="inventory_session_number">Inwentaryzacja nr %1$s</string>
    <string name="inventory_session_meta">pozycji: %1$s · zmienionych: %2$s</string>
    <string name="inventory_session_meta_sell">Utracona/dodatkowa sprzedaż: %1$s</string>
    <string name="inventory_pdf_title">Inwentaryzacja nr %1$s</string>
    <string name="inventory_pdf_date">Data</string>
    <string name="inventory_pdf_col_product">Produkt</string>
    <string name="inventory_pdf_col_unit">Jedn.</string>
    <string name="inventory_pdf_col_before">Było</string>
    <string name="inventory_pdf_col_after">Jest</string>
    <string name="inventory_pdf_col_diff">Różnica</string>
    <string name="inventory_pdf_col_diff_value">Różnica zakup</string>
    <string name="inventory_pdf_col_diff_value_sell">Utracona sprzedaż</string>
    <string name="inventory_pdf_total_products">Sprawdzonych pozycji</string>
    <string name="inventory_pdf_total_changed">Zmienionych pozycji</string>
    <string name="inventory_pdf_total_diff_value">Łączna różnica wg kosztu zakupu</string>
    <string name="inventory_pdf_total_diff_value_sell">Łączna utracona/dodatkowa sprzedaż (cena sprzedaży)</string>

    <!-- Kategorie ryczałtu: stawka dobierana dla każdej operacji zamiast jednego ustawienia -->
    <string name="ryczalt_cat_3">3% — towar</string>
    <string name="ryczalt_cat_5_5">5,5% — produkt/produkcja</string>
    <string name="ryczalt_cat_8_5">8,5% — usługi</string>
    <string name="ryczalt_cat_12">12% — usługi IT</string>
    <string name="ryczalt_cat_14">14% — usługi medyczne</string>
    <string name="ryczalt_cat_17">17% — wolny zawód</string>
    <string name="ryczalt_category_picker_title">Kategoria ryczałtu</string>
    <string name="ryczalt_category_choose">Wybierz kategorię ryczałtu ▾</string>
    <string name="ryczalt_category_selected">Kategoria: %1$s</string>
    <string name="ryczalt_category_required_error">Wybierz kategorię ryczałtu dla każdej pozycji</string>
    <string name="income_ryczalt_category_required_error">Wybierz kategorię ryczałtu dla tego przychodu</string>

    <!-- Zgodność VAT / kasa fiskalna (Ustawienia → Podatki) -->
    <string name="vat_compliance_title">Rejestracja VAT</string>
    <string name="vat_compliance_hint" formatted="false">Przekroczono roczny limit zwolnienia z VAT (240 000 zł). Musisz złożyć formularz VAT-R w ciągu 7 dni od dnia przekroczenia limitu i zacząć naliczać VAT na transakcji, która przekroczyła próg. Potwierdź poniżej po zarejestrowaniu — wystawianie faktur pozostaje zablokowane do tego czasu.</string>
    <string name="cb_vat_registered_label">Potwierdzam, że zarejestrowałem/-am się jako podatnik VAT (złożono VAT-R)</string>
    <string name="cb_vat_registered_confirmed_label">Potwierdzono: zarejestrowany podatnik VAT</string>
    <string name="kasa_compliance_title">Kasa fiskalna</string>
    <string name="kasa_compliance_hint">Przekroczono roczny limit 20 000 zł sprzedaży gotówkowej dla osób fizycznych. Może być wymagana kasa fiskalna. Potwierdź poniżej, gdy ją posiadasz — wystawianie faktur pozostaje zablokowane do tego czasu.</string>
    <string name="cb_kasa_label">Potwierdzam, że posiadam kasę fiskalną</string>
    <string name="cb_kasa_confirmed_label">Potwierdzono: kasa fiskalna w użyciu</string>
    <string name="vat_confirm_dialog_title">Potwierdź rejestrację VAT</string>
    <string name="vat_confirm_dialog_message">To potwierdza, że złożono VAT-R i jesteś podatnikiem VAT. Nie można tego cofnąć w aplikacji. Kontynuować?</string>
    <string name="kasa_confirm_dialog_title">Potwierdź kasę fiskalną</string>
    <string name="kasa_confirm_dialog_message">To potwierdza posiadanie kasy fiskalnej. Nie można tego cofnąć w aplikacji. Kontynuować?</string>
    <string name="confirm_yes">Tak, potwierdzam</string>
    <string name="confirm_cancel">Anuluj</string>

    <!-- Częstotliwość powiadomień push (Ustawienia → Podatki) -->
    <string name="push_frequency_title">Częstotliwość powiadomień push</string>
    <string name="push_frequency_hint">Ile razy dziennie mogą przychodzić powiadomienia o przekroczonych limitach i zaległych fakturach (1–50).</string>
    <string name="push_frequency_saved">Zapisano częstotliwość powiadomień</string>
    <string name="push_frequency_invalid">Podaj liczbę od 1 do 50</string>
    <string name="income_ryczalt_category_label">Kategoria ryczałtu dla tego przychodu</string>

    <!-- Wiele pozycji na fakturze -->
    <string name="invoice_item_number_label">Pozycja %1$d</string>
    <string name="add_invoice_item_row">+ Dodaj pozycję</string>
    <string name="invoice_items_limit_reached">Możesz dodać maksymalnie %1$d pozycji na fakturę</string>
    <string name="invoice_item_min_required">Faktura musi mieć przynajmniej jedną pozycję</string>
    <string name="invoice_total_label">Razem: %1$s zł</string>
    <string name="item_qty_hint">Ilość</string>
    <string name="invoice_income_comment">Faktura nr %1$d — %2$s</string>
</resources>
EOF_APP_SRC_MAIN_RES_VALUES_PL_STRINGS_XML
echo "OK: app/src/main/res/values-pl/strings.xml"

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
    <string name="about_description">FinArs — комплексное приложение для управления финансами нерегистрируемой деятельности и ИП (JDG). Ведите учёт доходов и расходов, контролируйте лимиты, автоматически считайте налоги, выставляйте счета и формируйте готовые отчёты и налоговые декларации — всё в одном месте, с полной историей операций под рукой.\n\n\uD83D\uDCCA Финансы и налоги\n\uD83D\uDCB0 Учёт доходов и расходов с прикреплением чеков\n\uD83D\uDCC8 Автоматический расчёт прибыли и налога (шкала 12%/32%, плоский 19%, ryczałt)\n\uD83D\uDD01 Регулярные транзакции (аренда, подписки) создаются автоматически каждый месяц\n\uD83D\uDEA6 Контроль лимитов: незарегистрированная деятельность, порог 120 000 zł, освобождение от VAT (240 000 zł)\n\uD83D\uDD14 Уведомления о приближении и превышении лимитов\n\n\uD83E\uDDFE Счета и фактуры (Pro)\n\uD83D\uDCDD Выставление счетов/фактур физлицам и компаниям с генерацией PDF\n\u2705 Статусы: Оплачена / Ожидает оплаты / Просрочена, плюс напоминания о сроке оплаты\n\uD83D\uDCB5 Контроль годового лимита наличных (20 000 zł) для продаж физлицам\n\uD83D\uDD0D История счетов с поиском и фильтрами\n\n\uD83D\uDCC4 Отчёты и декларации\n\uD83D\uDCCA График доходов и расходов за последние 6 месяцев\n\uD83D\uDCE5 Экспорт отчёта за месяц (бесплатно), год и произвольный период (Pro) в Excel вместе с чеками\n\uD83E\uDDEE Формирование деклараций PIT-36 / PIT-36L / PIT-28 — вспомогательный PDF и заполнение официального бланка (Pro)\n\n\uD83D\uDD12 Безопасность и удобство\n\uD83D\uDD10 Блокировка приложения PIN-кодом и отпечатком пальца / лицом\n\uD83D\uDCBE Резервное копирование и восстановление данных (Pro)\n\uD83C\uDF19 Современный тёмный интерфейс\n\uD83C\uDF0D Доступно на польском, русском и английском языках\n\uD83D\uDD12 Все данные хранятся локально на устройстве\n\nСвязь: p.arsenii@interia.pl</string>
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
    <string name="ryczalt_rate_moved_title">Ставка ryczałtu по категориям</string>
    <string name="ryczalt_rate_moved_hint">У каждого дохода и каждой позиции фактуры есть своя категория — товар, продукция, услуги, IT-услуги, медицинские услуги, свободная профессия. Ставка налога подбирается автоматически на основе выбранной категории.</string>
    <string name="min_wage_label">Минимальная месячная зарплата (zł) — для расчёта лимита незарегистрированной деятельности</string>
    <string name="monthly_limit_preview" formatted="false">Месячный лимит (75%): %1$.2f zł</string>

    <!-- Гейджи лимитов на главном экране -->
    <string name="limits_title">Лимиты</string>
    <string name="limit_monthly_label">Незарегистрированная деятельность, этот месяц: %1$s / %2$s zł</string>
    <string name="limit_bracket_label">Первый налоговый порог (120 000 zł/год): %1$s / %2$s zł</string>
    <string name="limit_vat_label">Освобождение от VAT (240 000 zł/год): %1$s / %2$s zł</string>
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
    <string name="notif_vat_text">Годовой доход приближается к 240 000 zł — порогу освобождения от VAT.</string>
    <string name="notif_vat_exceeded_critical_title">Превышен лимит VAT</string>
    <string name="notif_vat_exceeded_critical_text" formatted="false">Превышен годовой лимит освобождения от VAT (240 000 zł). Подайте VAT-R в течение 7 дней и подтвердите регистрацию в Настройках — до этого выставление фактур заблокировано.</string>
    <string name="notif_kasa_exceeded_title">Может понадобиться кассовый аппарат</string>
    <string name="notif_kasa_exceeded_text" formatted="false">Превышен годовой лимит 20 000 zł наличной продажи физическим лицам. Подтвердите в Настройках наличие кассового аппарата — до этого выставление фактур заблокировано.</string>
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
    <string name="buyer_name">Имя и фамилия / название фирмы</string>
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
    <string name="invoice_blocked_toast">Выставление фактур заблокировано — сначала подтвердите статус VAT/кассы в Настройках</string>
    <string name="invoice_is_receipt_label">Эта фактура выставляется как чек</string>
    <string name="vat_rate_choose">Выбрать ставку VAT</string>
    <string name="vat_rate_selected" formatted="false">Ставка VAT: %1$s</string>
    <string name="vat_rate_picker_title">Ставка VAT</string>
    <string name="vat_rate_required_error">Выберите ставку VAT для этой фактуры</string>
    <string name="vat_rate_23">23% (базовая)</string>
    <string name="vat_rate_8">8% (сниженная)</string>
    <string name="vat_rate_5">5% (минимальная)</string>
    <string name="vat_rate_0">0% (экспорт/WDT)</string>
    <string name="vat_rate_zw">zw (освобождение)</string>
    <string name="vat_rate_np">np (не подлежит налогообложению)</string>
    <string name="vat_limit_block_message" formatted="false">Превышен годовой лимит освобождения от VAT (240 000 zł). Подтвердите регистрацию VAT-R в Настройки → Налоги, чтобы продолжить выставлять фактуры.</string>
    <string name="kasa_limit_block_message" formatted="false">Превышен годовой лимит 20 000 zł наличной продажи физическим лицам. Подтвердите наличие кассового аппарата в Настройки → Налоги, чтобы продолжить выставлять фактуры.</string>

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
    <string name="invoice_pdf_table_netto">Нетто</string>
    <string name="invoice_pdf_table_vat_rate">Ставка VAT</string>
    <string name="invoice_pdf_table_vat_amount">Сумма VAT</string>
    <string name="invoice_pdf_table_brutto">Брутто</string>
    <string name="invoice_pdf_receipt_label">Выставлено как чек для физического лица</string>
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
    <string name="product_price">Цена закупки</string>
    <string name="product_price_sell">Цена продажи</string>
    <string name="product_margin">Наценка %</string>
    <string name="product_margin_hint">Введите цену продажи напрямую, либо укажите % наценки — цена продажи посчитается автоматически от цены закупки (например, 60 = закупка +60%).</string>
    <string name="gallery_scan_receipt_button">Сканировать чек из галереи</string>
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

    <!-- Update 43: PDF-отчёт инвентаризации + история + сканирование штрихкода, починка разбора позиций чека -->
    <string name="inventory_scan_button">Сканировать товар</string>
    <string name="inventory_history_button">История инвентаризаций</string>
    <string name="inventory_scan_not_found">Товар с кодом %1$s не найден</string>
    <string name="inventory_scan_found">%1$s: %2$s</string>
    <string name="inventory_history_title">История инвентаризаций</string>
    <string name="inventory_history_empty">Пока нет проведённых инвентаризаций</string>
    <string name="inventory_session_number">Инвентаризация №%1$s</string>
    <string name="inventory_session_meta">позиций: %1$s · изменено: %2$s</string>
    <string name="inventory_session_meta_sell">Упущено/лишнее по продаже: %1$s</string>
    <string name="inventory_pdf_title">Инвентаризация №%1$s</string>
    <string name="inventory_pdf_date">Дата</string>
    <string name="inventory_pdf_col_product">Товар</string>
    <string name="inventory_pdf_col_unit">Ед.</string>
    <string name="inventory_pdf_col_before">Было</string>
    <string name="inventory_pdf_col_after">Стало</string>
    <string name="inventory_pdf_col_diff">Разница</string>
    <string name="inventory_pdf_col_diff_value">Разница по закупке</string>
    <string name="inventory_pdf_col_diff_value_sell">Упущ. выручка</string>
    <string name="inventory_pdf_total_products">Всего проверено позиций</string>
    <string name="inventory_pdf_total_changed">Изменено позиций</string>
    <string name="inventory_pdf_total_diff_value">Итоговая разница по себестоимости</string>
    <string name="inventory_pdf_total_diff_value_sell">Итоговая упущенная/лишняя выручка (по цене продажи)</string>

    <!-- Категории ryczałtu: ставка выбирается по каждой операции, а не одной общей настройкой -->
    <string name="ryczalt_cat_3">3% — товар</string>
    <string name="ryczalt_cat_5_5">5,5% — продукт/производство</string>
    <string name="ryczalt_cat_8_5">8,5% — услуги</string>
    <string name="ryczalt_cat_12">12% — IT-услуги</string>
    <string name="ryczalt_cat_14">14% — медицинские услуги</string>
    <string name="ryczalt_cat_17">17% — свободная профессия</string>
    <string name="ryczalt_category_picker_title">Категория ryczałt</string>
    <string name="ryczalt_category_choose">Выберите категорию ryczałt ▾</string>
    <string name="ryczalt_category_selected">Категория: %1$s</string>
    <string name="ryczalt_category_required_error">Выберите категорию ryczałt для каждой позиции</string>
    <string name="income_ryczalt_category_required_error">Выберите категорию ryczałt для этого дохода</string>

    <!-- Соответствие VAT / кассового аппарата (Настройки → Налоги) -->
    <string name="vat_compliance_title">Регистрация VAT</string>
    <string name="vat_compliance_hint" formatted="false">Превышен годовой лимит освобождения от VAT (240 000 zł). Вы обязаны подать форму VAT-R в течение 7 дней с даты превышения лимита и начислить VAT на транзакции, которая превысила порог. Подтвердите ниже после регистрации — до этого выставление фактур остаётся заблокированным.</string>
    <string name="cb_vat_registered_label">Подтверждаю, что зарегистрировался как плательщик VAT (подана VAT-R)</string>
    <string name="cb_vat_registered_confirmed_label">Подтверждено: зарегистрированный плательщик VAT</string>
    <string name="kasa_compliance_title">Кассовый аппарат</string>
    <string name="kasa_compliance_hint">Превышен годовой лимит 20 000 zł наличной продажи физическим лицам. Может понадобиться кассовый аппарат. Подтвердите ниже, когда он у вас появится — до этого выставление фактур остаётся заблокированным.</string>
    <string name="cb_kasa_label">Подтверждаю, что у меня есть кассовый аппарат</string>
    <string name="cb_kasa_confirmed_label">Подтверждено: кассовый аппарат используется</string>
    <string name="vat_confirm_dialog_title">Подтвердить регистрацию VAT</string>
    <string name="vat_confirm_dialog_message">Это подтверждает, что вы подали VAT-R и являетесь плательщиком VAT. Отменить это в приложении нельзя. Продолжить?</string>
    <string name="kasa_confirm_dialog_title">Подтвердить кассовый аппарат</string>
    <string name="kasa_confirm_dialog_message">Это подтверждает наличие у вас кассового аппарата. Отменить это в приложении нельзя. Продолжить?</string>
    <string name="confirm_yes">Да, подтверждаю</string>
    <string name="confirm_cancel">Отмена</string>

    <!-- Частота push-уведомлений (Настройки → Налоги) -->
    <string name="push_frequency_title">Частота push-уведомлений</string>
    <string name="push_frequency_hint">Сколько раз в день могут приходить уведомления о превышенных лимитах и просроченных фактурах (1–50).</string>
    <string name="push_frequency_saved">Частота уведомлений сохранена</string>
    <string name="push_frequency_invalid">Введите число от 1 до 50</string>
    <string name="income_ryczalt_category_label">Категория ryczałt для этого дохода</string>

    <!-- Несколько позиций в фактуре -->
    <string name="invoice_item_number_label">Позиция %1$d</string>
    <string name="add_invoice_item_row">+ Добавить позицию</string>
    <string name="invoice_items_limit_reached">Можно добавить не более %1$d позиций на счёт</string>
    <string name="invoice_item_min_required">В счёте должна остаться хотя бы одна позиция</string>
    <string name="invoice_total_label">Итого: %1$s zł</string>
    <string name="item_qty_hint">Кол-во</string>
    <string name="invoice_income_comment">Счёт №%1$d — %2$s</string>
</resources>
EOF_APP_SRC_MAIN_RES_VALUES_RU_STRINGS_XML
echo "OK: app/src/main/res/values-ru/strings.xml"


mkdir -p "$(dirname "app/src/main/res/drawable/logo.png")"
echo "--- Zapisuje nowe logo do app/src/main/res/drawable/logo.png ---"
base64 -d << 'B64EOF_LOGO' > app/src/main/res/drawable/logo.png
iVBORw0KGgoAAAANSUhEUgAABOYAAATmCAYAAACF/K4qAAABomVYSWZNTQAqAAAACAAEAQAABAAAAAEAAAAAAQEABAAAAAEAAAAA
h2kABAAAAAEAAAA+ARIABAAAAAEAAAAAAAAAAAACkoYAAgAAAUYAAABckggABAAAAAEAAAAAAAAAAHsicmVtaXhfZGF0YSI6W10s
InJlbWl4X2VudHJ5X3BvaW50IjoiY2hhbGxlbmdlcyIsInNvdXJjZV90YWdzIjpbImxvY2FsIl0sIm9yaWdpbiI6InVua25vd24i
LCJ0b3RhbF9kcmF3X3RpbWUiOjAsInRvdGFsX2RyYXdfYWN0aW9ucyI6MCwibGF5ZXJzX3VzZWQiOjAsImJydXNoZXNfdXNlZCI6
MCwicGhvdG9zX2FkZGVkIjowLCJ0b3RhbF9lZGl0b3JfYWN0aW9ucyI6e30sInRvb2xzX3VzZWQiOnsicmVtb3ZlX2JnIjoxfSwi
aXNfc3RpY2tlciI6ZmFsc2UsImVkaXRlZF9zaW5jZV9sYXN0X3N0aWNrZXJfc2F2ZSI6dHJ1ZSwiY29udGFpbnNGVEVTdGlja2Vy
IjpmYWxzZX0A1v6a6AAAAARzQklUCAgICHwIZIgAAAABc1JHQgCuzhzpAAAgAElEQVR4nOzd6bMk2Xnf999zMmu5e+/LdM/0LD0L
ZrAQGwkREhUibQm2+IJawlY4wmGFwg7/fZQXhRRymDBpEaABkBzMgtlnemZ6X+5+b1VlnscvcjuZdRsCKYDAzHw/geqqm5XLyayq
O7d+eM45EgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAvzr2624AAADA5427p39jDR+nt/CYx8ObBo97h0vuT7rF5F7Jzz7YNr2vDmjW+xkAAAC/XARzAAAAj3FC
wHZSsNbcsuQ2OpZGJo0OpHGx0GgmjaMpn0ujRVGMCtOokOVFqbw0jeZSXkblpZTNo8JCyudmIUghRpmpukXJguT1QT1I8qDoko/c
y7EUcylaUBmkIgsqcqmYuIo8UzGVL0auRcjzIrgWE2mxMtJ8JC3G0kLVrUhupaowr7lPg76lQI8wDwAA4BdHMAcAAL6QktDtcSFb
Xt8ySfm2NCqk8fFck5lpfGSaHBSaHJkmR2U5nUdN5qbxUdTkwGwyd01nhaZHHqfH0mTumpRu46KM44WrCubcssI1iq68dGWFx8wV
srksLEzBXcFM5lHW3EuuUJ2BQpDL5VFSNMWRFHM3z8yjXDGYl5mpyCyUY4/FOFMxMS3GZkVuWmQK82nms3Gm2UYWjlddszzXfOqa
rQSfTaXZatAsl2bT4Meryo9Wcs0m0mwqHY+l+eTkIK+5DUM8AjwAAIAEwRwAAPhcqwO4NHhrQrdRc9upK9tmC02PpOleWazOzFZ2
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
o+ja0bWnWb8d365+YZrzas5ykNV1566+tt7PkvWbnrXNa96culyhbk9hUmlyc5XBtFCm48x8d8v04FTmty+O7MYzub33TO5vXQnZ
xxsj3TtXdX+dSSrNLAoAAODvGMEcAAD4L5aGb5LG+9LKgbT+cKHTN01nb0edv7vQ5XsxPnEv6tJutLNHMZ72aKcVfT0zm+aucXAb
mRTcFVxeTzbaTa/gg/6XngQ2vRBoWLnVds2s96NmWXIOvQqyKkpKQ6FqU2+7qrp3oVSaqfXCMSUBV1uPpm7lmAaMw3K0LjrzZF9p
ktXmcmnilQR6XYVcF8x5ff7DoCwN6bz51/sTSlSn3M3+mgaOSZ1dL+TsHjzuz876aOn1SxoVeudfHb8JEK1+DZrATmYK1cvopdxL
97IwFQvzuYKOpkEHp3PbeSKEB+dHfudM0McXQrjx1EQ3L2S6d156NKnCumZiiWZSCarqAADArwTBHAAA+BsbjA83OZTWdqStO9KZ
u6XO3yp04XYZL31S6PJDt0tHMZ4p3TY9ajO41nLX1NxGkufultXxlLVZV1KxZUnHUuuFYNZVtrmpV0rWzkbQJjZJpVxSAZaGevb4
YK4rivO6kivpktlO7tBtqSSkUtvkZFnTvKYBTYvScG4pmEtK+fqzoNbXpUkpq/P2JMBK6tDaYK5p14l/DHr/Ybr7JhxrzqwLzZIj
tBsNUstBjV6v/cnx2utgVcjavB/UtCMNHZuyxsH+mxCxft5lFqMUC1lZSDPP/Mik3an5o3Pj8OBK7nefzHXryijcfsp052LQ/VO5
HqxJO5L21U0qQfdXAADwS0MwBwAA/rOSIC5XHcQdSpt3pVM3S537OOrCJ6Uu34rx0vZCF49KOzeXn/VSZ3LXRnBNM1NW9Tys5jPV
CR0H+0PADbptdnVzvQo0a2cx7XcPtbYCLg27uoDH02RIXffLYSiVXIN+W5oE0SwpK6vW60+/kKR/TbDVHjvpUNrP8rqunG5VF9Z2
d90kFP2rlXY27R96aDnGGi5NywSTa9W7ZidV9CV7G16vNsrrH9V6D4aN9eQuaZ8pCR29GnIvyUc9eT3ahnsT7LVtdnf30qxYmM8K
074FbU9yf3A2C/efHvv965nuPDUKdy7nuv1Epnub0oOx9FBVUNdW1BHSAQCAvy2COQAAsKQO4qQujFu5JW09lE7fK3TuRtSlj8v4
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
WM3lw0wraWd35lV71FsyvP52wjVcDsJOqkrr7zc9eu95G1TQPaYCLo2wlvcxqLbz4Stiy9sN3mJa6ja7XG2XtiIN/EzD1XstbQoC
24M118/TQLd91LwXu1wySAqhyiMXruLYfb4wHa7k2r020r0vT+3Dl8d656k8vHs110fnc92UtK1uAomSgA4AgM8/gjkAAD4HmnHj
7kkrd6UzHxe68rNC199ZxK/eKuyb+6VfK6POjKKtjN1zk8xc5rELh9pujGkRULOgKjFLi6gkqe3O1yxsg6ZenNBVzPU27h9ksCxZ
v1/Y1ouMmnAvDc4ek631nxvmgL2spQt4enVp1uU4bXWb9y/XScer1vSuC2ty0C5E7Lq3Ll+Friqx1/DBw6bFYanSb/lUk7itH661
55pcKE8uS1t2dvIr11wk97T9yfX0LiBsljb7iPUkEKH9OXlZTnrdhifUPxtVV66/YXvOaSjYnoi1gW56OsvZcXNNvO19HN3bj0c3
GUe361DfZKbS3I8lHbnKken40kgPnp/Ye1+b+o9fGYefPLuit05JtyTtSJrTzRUAgM83gjkAAD6DkgkcRnvVBA5n3i2Ky28W9vzb
pV3/ZO7PHkVdk9ulUdSpzDWRWx5dwaptZW5K63G6HC7t5Nc9MuuCi6aaqQvietFbb4e9yjJ1wUVTdaWlLatUJw1P2vDLexlK/9le
iVP3XDvWnVkXKjUpZHr+TQ7YzhLaTLCQtK+pNutW6VfJNcuS9CkN39JrJdVhqHf79+RcesGcV0lqmoo1oZDVaV/VzCaM6gdRqp9b
DtOWRqvrrlUvhU1r8NLysf7+u3NuwkYfvLT9YK5/5k2b69AyfX3T8KzX8jq2TF/HbjrWLvhrz6lpf7cva8f2W56oY3lCiv5r2ASp
Ppg8I93KZMnno7qumVXXYeGKh+7FoetoZNq5MvUbX1uxd7811TsvTMK7V8b6YEu6LWlP0rGkhURXVwAAPk8I5gAA+Ixw96bwZrwn
rT6Uzn9U6PKbXl792cKu3Vj4MztFuDZyvziOOpO5bZRRE5cyc1kcfJW3OhXqVckprU5KY7F+UNff1UlJS1cytdQ71rswpjpeU4qW
Vr7Vx2wDlK7raBfA1d0HLT2CDRrXHKPf3JOq6qqs7jHVac0hk9PrfvK2Umo5mqk7fNZhVXJZkueWd9wLmurzbULT5nWxpHpNddur
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
ehNytO+v3lu0+5ym7+vqqS7OPKnu1OWKzWek7h4egtyCfO6+2HU/cOnR9Yl/+r0te/v3VvTmsyvhnQ3pI0k3Vb1vFgR0AAD8ehHM
AQDwK1SHcqNdaf2mdO4vZ3r2B0X86ruF/9Z+oRembpdXorbkNq3GyKqTLW96dnq9UINYJAmp6lDA1Q/m2v/Ip9U9aVfNwTf9LlSq
wqnHBXDNLJQ2eK6NFEz9YG7Q5rrIT10UccKfI57OqvlzAjyvqtKCDZ9bbnp6uunevE5Ofm6RoSeBSJLkNXNdtCVg6rpDRkllrCrh
irqoMch9FCxOpXIl1/xUpvmlXMeXgg7Ojnz3TBYenRr79rlc2+dHeng2hO1c2lH/tifpUNLxnjQrpMVcKi72A7dhwKbPa/dFXy6r
HIZ4uZbDu1VJ65I2JZ0updMPC525V8bz9+Y6d3duZ+4t4qm7hZ26W/ja/TKs7ERNjgqNZtHzhZRFyTJzy12WV+PXWbDuXRa9eq+0
1XNJvFZVciafVq+r4Koz6k6jPpN0Zt7uvJtu69VnvUx+J2Ry5aH6eBzJi0Np99JEn/7eut7+nVW9+pVx+PHVXO9KeqDqvcRsrgAA
/JoQzAEA8CvQjCH3oTS6e6zLP47lV35Y2Lc/nts3XXp5UzqbuyZFVPCoENvsqSmvSgIkb7KuQUDVVG01wVyvGKfXc1DWm3K0/vof
k0Xqwr32HDSoHxtUBLVVYskT3nZa9OY6JHuw+n9dKNF1hR3qZkxtpwhN8oqmKq9abBrkHhrGgm0OWHegbJtoSVuSffb2O3gu7YPZ
/FuqqoRbqBoTTjLPTJq6ayX3uBVUXhqpuJjZ8aWR7V/Mdf/i1G5ezPXJlUy3c+mupHuquhpuKwnfVO9Wy1Vu3dUiUPm5Tgjvmiq8
NLybSFpTFdadknRa0rkd6dLNRbx4pwgX7x7pwp0iXrhZ6NSnC60+msfxYal8v7DsSMpKc+UuG5s0klX9Yuv3a9P3t/dR7FXTaamU
0+r3aLOP9DNX7cvb97N79aZsupLLqxMbZ5Jn8j2p3F748VrmD767pne+t2V/9rVR+IvLE709qd57h2ImVwAA/s4RzAEA8EvSVMdJ
Wrs705k3XU/8+WLx/E+Ow9cfFnppLHtyJeicudZLt1yu4HV3R/d0FlL1KrTaCSLb41Q/pV/mPb1XFSqF5PmGWdfVtAuhLKliS/fR
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
r2yE2y9O442LIbwzkT6SdGsu3SuknZl0eLqbmKGZFZUuqfiFDbrAZpLGe9J0oxqn7pSky0fS9dd24/W/2rWn3zqKlz+e6/ydUpt7
paYLhVEICrkp5KH9kJ5QaZvU0g7/0vdkSt/ks9+uaCaPrtykPJO7VO5Eny1kj76zoXf+5Wn/0Tcm4YdXx3pdVUh9IKmggg4AgL89
gjkAAE7g7k2Fy+YN6dKrpZ7983l8+Y2y/Orhwl6alHYpj2GzdJ+6FORWB3J1hZt3XVS7CR7qfSf3pqbrZ9vJrN2i+RLdVpCpq4Lr
Hnd7GpyAekmYulCum/2xO2pMquXaLX046ULS+jQls+5wnu6kVbc37fOaRHOxPvuQPp18ze8V5VlzLkko117D6jrmVq3nJi1iVRVn
7p6bzdaDHz4xtt3rE3/0ylq4+8LEb16b6Na6wqeqKuLuzKT7C2lvvZqZspmggeog/FIlQV0mKZc0VTc+3QVJlz6a6+qr+/HJVw/s
4nuH8cLHhZ17tNCpmWvdTPk4KBuZ1TO9dl1Tu9LX5ljN57wX27XBf1NF2z5jqiaQMNM0uMfcyvsL3y9Nt7+9bu/+qzP++m9Pw08v
ZnpL0ieqqkgZgw4AgL8FgjkAABL1l+WRpPXb0uW/mpcv/mlhX3qr0ItHM39+bPZUiDpbRuUeLbRhU9INs9pROvZaF7i1FWiDajlL
87K2Mc2u29SrCtfqjeJjvwJbu336Nbw/MUPTkrTb6cn78mG5nLX/KB1vbmnsuza4S47rw46oTVjgMk/yxCTfS4/udWVdVDeZRbBq
mtuQVePEzcqqq6rc44p8fi63g6dybb+4qluvrNrNL6/r5sUQbqsK4m4vpPul9GhajZ91pLoqjiAOf5eSGZ5zSdMjaX2lqqS7IOni
Q+nSawfxyqt7uvrmgV/58NjP3y/s9KHbussnY7NslFU7MFW/K5qi1q7iNun+nlSk2uDjbKoqVJuZlLMoZSP5UabFw0J7o+i3/2DT
3vvnZ/ynr0zCaxczva1qkohHqiro+OwAAPALIpgDAED9QO5D6cLPZuWzf17Y196b+28dzvVcJl12t63omropuFSNf+bdGHFpuNX7
VppkXunytsPosEtaWxU3qLLzdL2ue2laRVd9sX5M1VpSgbfcrXSpmE1p6NZbbl2g16/K64d9vQ3qe2/SxLrEx2O3lSdVcL1ztq6K
z+vwrh6sXkGu0qSjwnRUyOfHHkfu5fmxDq6vaPvr67r722fCzS9N/MPNED6QdENVVdyDhbSz3o0VV0p0TcVvhsFEEuM9aXUsbU6k
s5Iuz6Qnf3oUr/1kR0+9euhX3j3yC/dndvrAbDWYRpOmki7ImkkeYlOZ63WNXBPyN+WqzQHritPm4J6MUxdcyoI8uordQgfjkT75
5oa99b1N++lvT8ufXh5nb6oag44urgAA/III5gAAX2jJGHKTO8e68CMrXvjT4/D1D0r/1qz0L2fRLrrbqruypoakDYy86u6VBlrV
c9Z222yeTavV0ikbbDAIlDf51qBqrH2uve++YKchXTfDadXQ9vjVkq6qLxkjzgfH6f3QzETRb2VSCThUVwY2gZ7b8tOSYqjXrI8f
vasoHI6Z1ZxBHrox4+al6aCUZkfuPlPMjr04HW3+zNQPv3PeH33zQvbhK6f9zU2FNyS9r6qa56G67qkEcfjMGHR7HUtaUTXT6+VS
evqtQ734o11/4SeH8cn3D3T+3kJbe7IVDxqNg7LMqt80zWys1S+ytha3q5SzbpIUs+bzZ20X8ub3mEnKg3whlTuFH4Sgu/9gw9/9
F2fsP31lGn54Mdd7kh6oCr5LPmcAADwewRwA4AurHkdu8rF0+rUjPfOns/gHb5b+9+elXhxJZy3aVHWvLkntWGZNuNWvcGs0Uy/Y
IEjrVk1HbmtHorOk6i6ZVCHpKds7dnc36Gpq3T67wLA/9UQbqvlw2eN+6Np4YjFeb7NhlVzS7q5Hbz2VaXdy7dhYLkWrurUGmbIg
5UGyUHVRPZi75seuxYE8HHs8G7V4cWx7v3PG7vzuU/bRl07726MQfiLpTVVdVfdUdU0tmsYREuCzLJnpNQ3qVlUFdc98cBS/+sNt
ffWH+/78WzNduTPX6UO3sZuycWaWt6F5VyxnbRhnbdXc8sckmfU4GRUzBPnCFHcXvhgH7f7ulv31vzxl/8/Xp/rB2VxvSbonaUH1
HAAAJyOYAwB84dSB3Non0qU3yvL69w/tq2+U/s3Zwr40cl0y14aij9ybMpNkblXvh2RNhVtvPDlTHZYloVkSTrUdPb2rmPOkis3d
226b3dhz1usu2+7XwtIYcE1NS/v1PdmuX82WXJP6H2smhEhDQLN0x1041wSEyUQQZkklX1Nxk8zeUCdjivK6W213LZprG4JrHKQ8
mBaFtF9Ih4eu4khxdBwXl0o/eGns29+5YPe+eznceO6cvS+FdyV9MJduLaSHa1UgNxfVOvicS8amG6mqpDsj6QlJ117b1/U/244v
/GTfn33n2C49KHXq2LSSBeUTk2VdMVwXzNULzOrfT71fCKp/v1k9NqSprH8PZMF9YVZuu3bXzT/5p2f05j/fCj9+ZUU/WpfeUTX+
3MzMyr+rawMAwGcBwRwA4Auh/vKaS5rekc79ZVG88P1Z+PLPSv/KbKYXx7KnvdSWXGOXgjWBWx3MSSdUryUhXe9Y9b8nVcyp3dNJ
W9TPpV3M0gkS6sAutolgUhmXfGnu9t4laV0+aL2AzfsPkib1q2MGm7X/eLJP651s125LFlXd6Kpgrvm+r7r7XBaqC19Eaf9Ymu3L
j/e99GNbXFQ8+K0N3f+vLtvt37tqn55b0w0pfFxKn8wWumWF7q2saFtVV9WS6hx8EaW/546krRXpnKSrM+nZV3fjs3/y0K79aD9e
+XCmS3ulTnmmyThYNskUmplZe5/gwa+q9HdgPfm0XPUYdqpnrsgVS9fxw1IPz451449O+Wv/7FT4yfMTvTmVPlLVxfWIzygAABWC
OQDA51oyhtz6Penca0Vx7T8swpdenfvXZgu9NJWesoXOyjWVLISmQs2Hw6tZF0yl1XJSv/KsDcD8MYFcb6fJpklFmw/HcEsq9dpj
pP1D6z33/qtubVB2QjPVzsaaBmlL4Vx999i/FpLAz9o6vXZTd+t9yfduM8lMFlyjrOqqWkTpcC7tb8sPHsay3PXZmRj3X9kMD/+b
p7Pb/+iaf3JlcymMezBb0e6pKowrqMQBKukMrzvS6lQ6M5EuS7ryoNC17z+Iz/75tl17feZP3F3o7JG0aWbTSa4sC13G3uT/Vv8y
TP9PAHeptPR3Xrc8M/kos/LYdbxd+P1ra3rvX5/11/7JRvjpkyO9IelDVWM+MkEEAOALj2AOAPC5VX85nTyUzr1W6Nnvl/Gr/9+s
/Nbe3F5Zd7sSStsq3ccmC01S1f+KmHZQbarTukCrFzQl9+2sqc2idkUbJFRVPzLvrVQHc00aVq+fBn3eT7iWKuTa6K/XZbXrVttO
GNFep377rXm+6VrbXVEtPTQpNlv0uuM24Vy/6i5TFcTlI8kz0+HMtf/IdXhP8eihl6tHOn5lLT763nN267+9bh89dS57W9LPJH0w
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
NqckP0q+WYRJ5XL43WgCFueTMsYltekIYs0bLkZxmxOMbMshRj4NxHWM+82CUQw0zf7BOf2JJ7fhxyhwkZmv5bFLxggMpwjru0us
vVNhqAr3cjlyncX7xsbPHKi8OODZVzf54L1jmEF2l5GRkWGRLeYyMm5jOP9yz5+k3b2ad5QKZXip5Sx7YilvmQmWI16lUHWXUfe7
djDBoMhKzq1rtOflGhQOc9zEGmXBGGwO9ecf33X9sSPTbwJ4FWZJYCY5bg06l7vV3m+dqQ91ZlvzUIDWsY+lCI6Xlfxswqs6nUr6
cXKOy73lnP1onSwNijKyRxwIsMhqz4ekyHIhtZwIH+mtReQh6+OVw9hSNFUpAbiNWb2FhdYEVsDmAFh/s8Iz96juvUv0NoCz48B6
VKmMjIxbAruEdfEPXl999OurY0+OzXV2UwmzeQ24IQM0RmwqI2SLAYWvd7Eii61zxTX3kSTPiPxG1seW08taW45UjskdTNMNHeL0
nPVXcDfQlGjOfDDIvsgi72aSi6hxyhNV4juV2XFdQx3jeqbx5FJUI/N11A6xzPauEby1tyhr1A9R4/65snma0fVPHDq2qHzJb2cl
SJqpXaL1by/RPae3cB+ARWRfYBmjUU20i/WlMazVNQ8UgYmFHJLCyH6VgOpqTL22yQcBLABo5+WsGRkZQLaYy8i43VH0Kiy8eI52
6YK2tQhFPDB3c8ZBoZBzvsRmXtmFqtevgastoACIDSHnHP0w2Md1eZDNIhpRKABDDYy3+l/5uZ3nj+1ovdbr4cz4OKo843zLMPvs
+frQSzf4wI4DxdSwYnLWBBQpqgIsrD/SAM5gjpMIPjw1bc6Y4ocpSc8EG2VvIlOPlTepeHJyZuQv9zy6B5hc2eKKsbAIlEq/ZkBX
gJoAeucJ6Nb8xUfbN2Ym1WkYC89efmYzMm4t/I7Sy5sP/C8vVE8VCxMPjXVoYjj0ggaxpZQgpG7GZAGBcJJBouBCzsRCoxlhZD6j
iCDXvyYWvCxlm5M4oT9+b8h+fNQUQ3MCwoWL/lv2jKOQQs4yR83aXFb6nqVrFnNE2b2fPpBoo+aEy2gLvECivVt/Iq2ym2WCrado
CV8MS9rZk8SEdgl1bYilP7xUP/DbR4pXAJwHMBiRdcbdjWqmRHd/h1c1qB+LlKZlKANoE9QG0fjLW2o/UC8CxQSyL9uMjAxki7mM
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
SHdSlISifuKdILTyZV9U3td7blj2IvhMYPLgIoBzMLvwruZ+oUSJ9zxKYq5Eifc+CMDgs69PrWvHaozq5I092fmYuvZaYDpxzfh1
Yi/QGnMj8jOpbBRWaFUMZX1VJdCWMNF2+ZfhTdZ4pdVrtzSKlHODQo+L3yI/H6FJSZgryF5eadV85ZtDYTz3mw8SCoc5ks2fFDJ8
vff0kIZFLEz4rkyZdw/UT9jmmyKGEApMQLfL6Gdg68ZmC0BL65u7AQLMC1WffG1yfbLQGZeDfXUGETImrJwlT4BsneHcDy5WS1pR
4AHe7EomwTFYDtWW9+0YugJgGjfJv5zblOVPnj276cLZ+S1UjQZJQlBiyifbLovqQSgkOiYylw/23b1oSbA7nFqSkoAkBleSSmfP
/g2XfvAHdh/+wU+tfXmkT7wM4Ging9nlZSwrha4aRDKcbtqSTcA7h/wzMoLKZYAkIKJZyChCVQ6i/sA9g8MP3DO48cf/5ra9v/Gf
Dz3w67//+oHZZb0xqtcbKk6kiVTnosu3QZeXoaRYkByvKReG0yBODOHJiqZmWjUANSGExPsQ1q9c44lzav8//rL80FINeyuEAWYO
utxUJzlDoPREBs9OcVgLc/1+Xh8Z1jcBSQF0oeoVzPyzh+m1e8fxZQCHh4GFGy2UWnPWxe1D8vydW5IzXzlKS8RoCNuhGZcHdvwK
xlbmvPPU7HYCYb5kqMceTs/UTapAHr6C0UfPYNvtd2INgGlmVqtYM6bW6mD9F97ETil5GDBGotpWLj+8pjsJZIdxl4+6KLd7h3y/
3GE1Z1kAShNzjO66Ecx+/4dw5ofvEi/uH8ErSHC0q3FBtTC30If2oCHF3k6fWshTvc0w+cmFhplM3cjxfuAbF7Ht6ZO0nTSPQICg
yWh2+iD5nHTzzJxXVc73C7AuKoLffLkSmJhVG3r9IM997kE6/WMfxCs76uJFAEdi4HIbmFXAcn+a95w78nirxNy7Fdci9xQsMbmK
+4MSJVYNSmKuRIn3PgSAkVePXN3QVXq4QhKKyewAkHGknkdO26AIwUql8wWU3UHOChmUXkq1tiw14mUzYzDQs1FaBtSzPpgR4kJi
IpjkZRKc2VkR2TAken8L4yqEe5+UkAvn/EVCY3pbnmDLPb7QEbT7DJ3mFzgFDj0b+89g3mmfHwlLhhIDCaM+INXtO0emgWR2cDC6
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
ettbek5WkD6IPUZJ99FeW0AhCgokgaB1hbhcc6wZTV3pdFRjqw68sVzj+sKILy8EXIXNF3cV5opbhwlxLcwdtxvFYsdxClyYc5x3
kNTYXgCwCmAfgNHMIXSLv3nkffPm6elnT7ZjprCndGdhy6/vliFzzlsgr+YGYAV9XrXxR4BiksbZWQ6ezafzhI55+ThvS/Y5VLB8
eh6WVzfvVeO1SO8qgAMpPmlJ1W7Finlx3+n97LbZpVzz3xbsyflNAJPd1FhXG+e7CGB/es3jfrMtcxaa837evbb3UxBGg3MUlr+u
IbkV7ub9ziuUwsrMXgBLaVfOP71nqY9rOSdZma4yzlq8x5z3+bwcXnau3QRwA0CzG8Te9xupfCzA8tMKLG+VdccsO9U98+qhW7Up
ctuhhYkKV2APDN50WblFm2e2TOxUBubl/9m0l+Up26u2YOV8A7t0iGC69xX6e7+I3o/Yor/3wLD+KOaguKN+YxnGLPPq7Nsxr51w
J+fvVCZutX+nfTtdqyx/Of/mvxbmSp7A6t9+ZSt3xTmOMwcX5hznXUJqNL3dbLvGbur4O3eHe5RXgULYeycbsfcwvQDgQ/5wb+/5
vbrf89I0e+23K92ep95/3Ot6Cbi7+ej9WMbfK6R7X44Jde4ynuccx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ec
x3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ec
x3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ec
x3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ec
x3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ec
x3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ec
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
sLn0OIqagzMSNSaOUmzBE1GOU3AUTgtBgCUKR1GWvCqrJAFSwTEKNYIQo3KMbO5PiZ0YmhbDIAUoiskNokJJRDTBE2kIt4mWndsy
GabSnINEAiKFIkaQklJMUzXmeQEjkJyUStYrtgnJ+nn9kiZpIghJVtRUCqdeyg4qyUCZ1xtAUt76sXggyoY+zTYVINlXOE+eTzbx
fgVwZXNiUa0II6AaMSjYqq1aATqCWdJqgMbQegFYqBXH9gY9sEgRApk00KtT6NYU2Noi2rwRabMFNZsAJkSyBWoiSFoBNWBpbVI1
ESK06IaWat91pu5zlhRg+/JgyDz9GVL0LJHpjhZCGPemqf4WwbSskO4/kWoaNW4iFBNITVUzI6NV4Nwda/eyImhg7hYmsIUQyBYU
IDLBidXm6apIGZ0zShm908okZ84LNCiTmHsq2PdUQbUKpOYkYg1sIk7FqgGQUJGGwBJIbMVWhlTMWjMk1NBAqlWlWhFpmndNA3eL
L0iwOc4UCg0stgwGQ0NgVU3SueVURXJ1ZTGqSuGxQiioJEeYLWzBkuZ548hqAhSRubcUECKWihEZUDVxKjJDCRq5WMDh/2/v3pYa
x6EogG4pmf//34FI82ArMW7fYOierum1qiCJpMh24AF26Vh1GjOFcplWVGXavGEKqnravOPsKDZtt/srcLkfhzDrvsV9/k6/sno8
a9sLhNZjzgKjo/F7/Udz5OR5LrT/Sl85tyvXlkQYB/x5BHMA/OAkxPxOZ8f56nlcDS2Pgsqrwd9W31bwt7Uqc/26bry35mNAuDVm
Pf4sKN0LPcvqOOvnm22PETZmKr9OcmuPlEdJbWm39si86+sUtuUVTJbFRidT3wgWp5WR0/P31J55B9h5U5LWWmmpZYSSaW2UR9e5
bPq1g25P6anl0fuYO4/FKr6xGUrL9O21PcViqdU8YCQGY5PS5JVPzSXovS3aMldijveMtp7Sex0lZlNZ3yjrLElJat5KSitJqyl/
l9RHTXl7/uR66q3Mq5ryfm9pc0lbL+9Je6S2KXAr7T0pb6O0vZXbe+b9bOfEsE03xV/+oj7LUMvrQuvz9Oexc93rfdm5eFsd2ySM
7tqew+bdR1MyldKVlNxGNWxJnxeT9WQqK0ySXnq/t5peW7/P40YoN3ZUrVNbG7uDjs9knqP3OcCqSWqdboQ/3zi/Tee42Ik19Xnz
/JpHT279Vh+t5tZym0sUR6lippVVt+dHtLliaB087QVE6zBnGVStX2/NvW4/W6m0dR5X2rIx5ih4Ogqitvr2xh45G3M18PlPgiGB
FMCfSTAHAD/BN4ebW2Hi3vxHweNe3/r5leBx/fosnDyaY+u4W2Hh0fmdfSU/hpFb17/1+jO2/rE+ausb/VvXV6d87cO5PUOX+8fw
pfyV5C3J8jHb17x37UfnfPXzubKq5iikWbftrUZKzsOmK3PtHfPq6qe9ua4ca+vYZ2Ouvv8z832aMAkA/h3BHADw7b4xmPzsPFfH
/05/A+0Fc98132cs1sj9Vr5yTj/lOgRRAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAA/x//AE3GmGUKRU/CAAAAAElFTkSuQmCC
B64EOF_LOGO
echo "OK: app/src/main/res/drawable/logo.png"

echo ""
echo "=== Update 48 zastosowany pomyslnie ==="
echo "UWAGA: zmieniona zostala wersja bazy danych Room (8 -> 9, MIGRATION_8_9)."
echo "Dodano kolumny invoices.vatRate (TEXT) i invoices.isReceipt (INTEGER) -"
echo "istniejace dane/faktury NIE zostana utracone."
echo "Dalej jak zwykle: zbuduj APK przez GitHub Actions."
