#!/data/data/com.termux/files/usr/bin/bash
# Update 64: zapisani kontrahenci (nabywcy) na fakturze — sprzedawca nie musi
# wpisywac danych kupujacego recznie za kazdym razem.
#
# Zmiany:
#  1) Nowa tabela `contractors` (Contractor.kt / ContractorDao.kt) — baza
#     przechodzi z v12 na v13 (zwykla migracja, bez utraty danych).
#  2) Nowy ekran SelectContractorActivity — lista zapisanych kontrahentow w
#     stylu aplikacji (karty na ciemnym tle), stuknij aby wybrac, "x" aby
#     usunac (z potwierdzeniem AppDialog).
#  3) AddInvoiceActivity, sekcja "Nabywca":
#       - przycisk "Wybierz kontrahenta" nad przelacznikiem osoby fizycznej —
#         otwiera liste i wypelnia pola Nabywcy danymi wybranego kontrahenta.
#       - przycisk "Zapisz nabywce" pod polami adresu — pyta o potwierdzenie
#         i zapisuje aktualnie wpisane dane. Jesli kontrahent o tej samej
#         nazwie juz istnieje, jego dane sa aktualizowane (bez duplikatow).
#
# Uruchamiac z korzenia repo (tam gdzie folder app/ i .git/), np.:
#   cd ~/FA_ksiegowy
#   bash update_project-64-saved-contractors.sh

set -e

TS=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=".update64_backup_${TS}"

echo "=== Update 64: zapisani kontrahenci (nabywcy) ==="
echo ""

if [ ! -f "settings.gradle" ] || [ ! -d "app/src/main/java/com/example/fa_ksiegowy" ]; then
  echo "BLAD: nie widze settings.gradle lub app/src/main/java/com/example/fa_ksiegowy - uruchom skrypt z korzenia repo."
  exit 1
fi

if [ -f "app/src/main/java/com/example/fa_ksiegowy/Contractor.kt" ]; then
  echo "!!! Wyglada na to, ze update_project-64 zostal juz zastosowany (Contractor.kt juz istnieje)."
  exit 1
fi

mkdir -p "$BACKUP_DIR"
for f in \
    "app/src/main/java/com/example/fa_ksiegowy/AppDatabase.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt" \
    "app/src/main/AndroidManifest.xml" \
    "app/src/main/res/layout/activity_add_invoice.xml" \
    "app/src/main/res/values/strings.xml" \
    "app/src/main/res/values-pl/strings.xml" \
    "app/src/main/res/values-ru/strings.xml"
do
    if [ -f "$f" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$f")"
        cp "$f" "$BACKUP_DIR/$f"
    fi
done
echo "Kopia zapasowa zapisana w: $BACKUP_DIR"
echo ""

echo "-> krok 1/6: nowe pliki (Contractor.kt, ContractorDao.kt, SelectContractorActivity.kt + layouty)"

cat > "app/src/main/java/com/example/fa_ksiegowy/Contractor.kt" << 'FILEEOF'
package com.example.fa_ksiegowy

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Zapisany kontrahent (nabywca) — dane wypełniane wcześniej w sekcji "Nabywca"
 * na ekranie AddInvoiceActivity, zapisane na żądanie sprzedawcy (przycisk
 * "Zapisz nabywcę"), żeby przy kolejnej fakturze można je było wybrać z listy
 * (SelectContractorActivity) zamiast wpisywać ręcznie od nowa.
 */
@Entity(tableName = "contractors")
data class Contractor(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val isPhysicalPerson: Boolean,
    val name: String,
    val nip: String?,
    val street: String,
    val postalCode: String,
    val city: String,
    val updatedAtMillis: Long = System.currentTimeMillis()
)
FILEEOF

cat > "app/src/main/java/com/example/fa_ksiegowy/ContractorDao.kt" << 'FILEEOF'
package com.example.fa_ksiegowy

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update

@Dao
interface ContractorDao {
    @Insert
    suspend fun insert(contractor: Contractor): Long

    @Update
    suspend fun update(contractor: Contractor)

    @Delete
    suspend fun delete(contractor: Contractor)

    @Query("SELECT * FROM contractors WHERE id = :id LIMIT 1")
    suspend fun getById(id: Long): Contractor?

    /** Używane przy "Zapisz nabywcę" — jeśli kontrahent o tej samej nazwie już
     *  istnieje, aktualizujemy jego dane zamiast tworzyć duplikat. */
    @Query("SELECT * FROM contractors WHERE name = :name LIMIT 1")
    suspend fun getByName(name: String): Contractor?

    @Query("SELECT * FROM contractors ORDER BY name ASC")
    suspend fun getAll(): List<Contractor>
}
FILEEOF

cat > "app/src/main/java/com/example/fa_ksiegowy/SelectContractorActivity.kt" << 'FILEEOF'
package com.example.fa_ksiegowy

import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Lista zapisanych kontrahentów (nabywców) — wybór jednego z nich zwraca jego
 * id do AddInvoiceActivity (extra "picked_contractor_id"), gdzie dane są
 * wczytywane i wypełniają sekcję "Nabywca". Kontrahentów można też stąd
 * usuwać (przycisk ✕ z potwierdzeniem, tak jak w innych listach aplikacji).
 */
class SelectContractorActivity : BaseActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_select_contractor)
        findViewById<android.view.View>(R.id.iv_back).setOnClickListener { finish() }
        loadContractors()
    }

    private fun loadContractors() {
        CoroutineScope(Dispatchers.IO).launch {
            val all = AppDatabase.getInstance(applicationContext).contractorDao().getAll()
            withContext(Dispatchers.Main) { renderList(all) }
        }
    }

    private fun renderList(contractors: List<Contractor>) {
        val container = findViewById<LinearLayout>(R.id.ll_contractors_container)
        val empty = findViewById<TextView>(R.id.tv_contractors_empty)
        container.removeAllViews()

        if (contractors.isEmpty()) {
            empty.visibility = android.view.View.VISIBLE
            return
        }
        empty.visibility = android.view.View.GONE

        val inflater = LayoutInflater.from(this)
        for (c in contractors) {
            val row = inflater.inflate(R.layout.item_contractor_select, container, false)
            row.findViewById<TextView>(R.id.tv_contractor_name).text = c.name

            val metaParts = mutableListOf<String>()
            if (!c.nip.isNullOrBlank()) metaParts.add("NIP: ${c.nip}")
            if (c.city.isNotBlank()) metaParts.add(c.city)
            row.findViewById<TextView>(R.id.tv_contractor_meta).text = metaParts.joinToString(" • ")

            row.setOnClickListener { pickContractor(c) }
            row.findViewById<TextView>(R.id.btn_delete_contractor).setOnClickListener { confirmDelete(c) }

            container.addView(row)
        }
    }

    private fun pickContractor(contractor: Contractor) {
        val i = Intent()
        i.putExtra("picked_contractor_id", contractor.id)
        setResult(RESULT_OK, i)
        finish()
    }

    private fun confirmDelete(contractor: Contractor) {
        AppDialog.show(
            context = this,
            title = getString(R.string.delete_contractor_confirm_title),
            message = getString(R.string.delete_contractor_confirm_message, contractor.name),
            positiveText = getString(R.string.delete_confirm_yes),
            onPositive = {
                CoroutineScope(Dispatchers.IO).launch {
                    AppDatabase.getInstance(applicationContext).contractorDao().delete(contractor)
                    withContext(Dispatchers.Main) {
                        Toast.makeText(this@SelectContractorActivity, getString(R.string.contractor_deleted), Toast.LENGTH_SHORT).show()
                        loadContractors()
                    }
                }
            },
            negativeText = getString(R.string.confirm_cancel)
        )
    }
}
FILEEOF

cat > "app/src/main/res/layout/activity_select_contractor.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:fillViewport="true">

<LinearLayout
    android:orientation="vertical"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:paddingStart="20dp"
    android:paddingEnd="20dp"
    android:paddingTop="28dp"
    android:paddingBottom="24dp">

    <FrameLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="18dp">
        <ImageView android:id="@+id/iv_back" android:layout_width="24dp" android:layout_height="24dp"
            android:layout_gravity="center_vertical|start" android:src="@drawable/ic_back"
            android:clickable="true" android:focusable="true"
            android:background="?attr/selectableItemBackgroundBorderless"/>
        <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
            android:layout_gravity="center" android:text="@string/select_contractor_title"
            android:textColor="@color/text_primary" android:textSize="18sp" android:textStyle="bold"/>
    </FrameLayout>

    <TextView
        android:id="@+id/tv_contractors_empty"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="@string/contractors_empty"
        android:textColor="@color/text_secondary"
        android:textSize="14sp"
        android:visibility="gone"/>

    <LinearLayout
        android:id="@+id/ll_contractors_container"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"/>

</LinearLayout>
    </ScrollView>
</FrameLayout>
FILEEOF

cat > "app/src/main/res/layout/item_contractor_select.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="horizontal"
    android:background="@drawable/card_bg"
    android:padding="12dp"
    android:layout_marginBottom="8dp"
    android:gravity="center_vertical"
    android:clickable="true"
    android:focusable="true">

    <LinearLayout
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:orientation="vertical">

        <TextView
            android:id="@+id/tv_contractor_name"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:textColor="@color/text_primary"
            android:textSize="14sp"
            android:maxLines="1"
            android:ellipsize="end"/>

        <TextView
            android:id="@+id/tv_contractor_meta"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="2dp"
            android:textColor="@color/text_secondary"
            android:textSize="12sp"
            android:maxLines="1"
            android:ellipsize="end"/>
    </LinearLayout>

    <TextView
        android:id="@+id/iv_chevron"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginStart="8dp"
        android:text="›"
        android:textColor="@color/text_secondary"
        android:textSize="20sp"/>

    <TextView
        android:id="@+id/btn_delete_contractor"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginStart="6dp"
        android:padding="6dp"
        android:text="✕"
        android:textColor="#FF6B6B"
        android:textSize="16sp"
        android:textStyle="bold"
        android:clickable="true"
        android:focusable="true"
        android:background="?android:attr/selectableItemBackgroundBorderless"/>

</LinearLayout>
FILEEOF

echo "OK: nowe pliki utworzone"
echo ""

echo "-> krok 2/6: AppDatabase.kt (tabela contractors, migracja v12 -> v13)"
python3 << 'PYEOF_DB'
import sys

def str_replace_any(path, candidates, new, label):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    for old in candidates:
        count = content.count(old)
        if count == 1:
            content = content.replace(old, new, 1)
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"OK: {label} -> {path}")
            return
    if new in content:
        print(f"Pominieto (juz zastosowano wczesniej): {label} w {path}")
        return
    print(f"BLAD (zaden ze znanych wariantow nie pasuje): {label} w {path}")
    sys.exit(1)

path = "app/src/main/java/com/example/fa_ksiegowy/AppDatabase.kt"

str_replace_any(
    path,
    ['    entities = [Entry::class, Invoice::class, RecurringEntry::class, Product::class, InvoiceItem::class, InventoryRecord::class, InventorySession::class, InvoiceCorrection::class],\n    version = 12,'],
    '    entities = [Entry::class, Invoice::class, RecurringEntry::class, Product::class, InvoiceItem::class, InventoryRecord::class, InventorySession::class, InvoiceCorrection::class, Contractor::class],\n    version = 13,',
    "entities list + version bump"
)

str_replace_any(
    path,
    ['    abstract fun inventorySessionDao(): InventorySessionDao\n\n    companion object {'],
    '    abstract fun inventorySessionDao(): InventorySessionDao\n\n    abstract fun contractorDao(): ContractorDao\n\n    companion object {',
    "contractorDao() abstract fun"
)

migration_block = '''        /** v12 -> v13: nowa tabela `contractors` — zapisani kontrahenci (nabywcy),
         *  patrz Contractor/ContractorDao. Sprzedawca może zapisać dane nabywcy
         *  wpisane w AddInvoiceActivity przyciskiem "Zapisz nabywcę", a potem
         *  wybrać je z listy (SelectContractorActivity) przy kolejnej fakturze
         *  zamiast wpisywać je ręcznie od nowa. Zwykła migracja, bez utraty
         *  już zapisanych danych. */
        private val MIGRATION_12_13 = object : Migration(12, 13) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    "CREATE TABLE IF NOT EXISTS `contractors` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `isPhysicalPerson` INTEGER NOT NULL, `name` TEXT NOT NULL, `nip` TEXT, `street` TEXT NOT NULL, `postalCode` TEXT NOT NULL, `city` TEXT NOT NULL, `updatedAtMillis` INTEGER NOT NULL)"
                )
            }
        }

        @Volatile private var INSTANCE: AppDatabase? = null'''

str_replace_any(
    path,
    ['        @Volatile private var INSTANCE: AppDatabase? = null'],
    migration_block,
    "MIGRATION_12_13 block"
)

str_replace_any(
    path,
    ['                ).addMigrations(MIGRATION_3_4, MIGRATION_4_5, MIGRATION_5_6, MIGRATION_6_7, MIGRATION_7_8, MIGRATION_8_9, MIGRATION_9_10, MIGRATION_10_11, MIGRATION_11_12).fallbackToDestructiveMigration().build().also { INSTANCE = it }'],
    '                ).addMigrations(MIGRATION_3_4, MIGRATION_4_5, MIGRATION_5_6, MIGRATION_6_7, MIGRATION_7_8, MIGRATION_8_9, MIGRATION_9_10, MIGRATION_10_11, MIGRATION_11_12, MIGRATION_12_13).fallbackToDestructiveMigration().build().also { INSTANCE = it }',
    "addMigrations(...) list"
)
PYEOF_DB

echo ""
echo "-> krok 3/6: AddInvoiceActivity.kt (launcher, przyciski, wypelnianie/zapis kontrahenta)"
python3 << 'PYEOF_ADDINVOICE'
import sys

def str_replace_any(path, candidates, new, label):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    for old in candidates:
        count = content.count(old)
        if count == 1:
            content = content.replace(old, new, 1)
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"OK: {label} -> {path}")
            return
    if new in content:
        print(f"Pominieto (juz zastosowano wczesniej): {label} w {path}")
        return
    print(f"BLAD (zaden ze znanych wariantow nie pasuje): {label} w {path}")
    sys.exit(1)

path = "app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt"

old_launcher = '''    private val selectProductsLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (result.resultCode == RESULT_OK) {
            val data = result.data?.getStringExtra("picked_items")
            if (!data.isNullOrBlank()) applyPickedItems(data)
        }
    }

    // Wgrywanie logo firmy'''

new_launcher = '''    private val selectProductsLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (result.resultCode == RESULT_OK) {
            val data = result.data?.getStringExtra("picked_items")
            if (!data.isNullOrBlank()) applyPickedItems(data)
        }
    }

    // Update: wybór zapisanego kontrahenta (nabywcy) z listy — patrz sekcja "Nabywca"
    // (btn_select_contractor/btn_save_contractor) i SelectContractorActivity.
    private val selectContractorLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (result.resultCode == RESULT_OK) {
            val id = result.data?.getLongExtra("picked_contractor_id", -1L) ?: -1L
            if (id != -1L) applyPickedContractor(id)
        }
    }

    // Wgrywanie logo firmy'''

str_replace_any(path, [old_launcher], new_launcher, "selectContractorLauncher")

old_buttons = '''        findViewById<Button>(R.id.btn_add_warehouse_items).setOnClickListener {
            selectProductsLauncher.launch(Intent(this, SelectProductsActivity::class.java))
        }'''

new_buttons = '''        findViewById<Button>(R.id.btn_select_contractor).setOnClickListener {
            selectContractorLauncher.launch(Intent(this, SelectContractorActivity::class.java))
        }
        findViewById<Button>(R.id.btn_save_contractor).setOnClickListener { confirmSaveContractor() }

        findViewById<Button>(R.id.btn_add_warehouse_items).setOnClickListener {
            selectProductsLauncher.launch(Intent(this, SelectProductsActivity::class.java))
        }'''

str_replace_any(path, [old_buttons], new_buttons, "przyciski Wybierz/Zapisz kontrahenta")

functions_block = '''    /** Wypełnia sekcję "Nabywca" danymi kontrahenta wybranego z listy
     *  (SelectContractorActivity) — patrz selectContractorLauncher. */
    private fun applyPickedContractor(contractorId: Long) {
        CoroutineScope(Dispatchers.IO).launch {
            val c = AppDatabase.getInstance(applicationContext).contractorDao().getById(contractorId)
            withContext(Dispatchers.Main) {
                if (c == null) return@withContext
                isPhysicalPerson = c.isPhysicalPerson
                findViewById<Switch>(R.id.sw_physical_person).isChecked = c.isPhysicalPerson
                findViewById<EditText>(R.id.et_buyer_nip).visibility = if (c.isPhysicalPerson) View.GONE else View.VISIBLE
                findViewById<EditText>(R.id.et_buyer_name).setText(c.name)
                findViewById<EditText>(R.id.et_buyer_nip).setText(c.nip ?: "")
                findViewById<EditText>(R.id.et_buyer_street).setText(c.street)
                findViewById<EditText>(R.id.et_buyer_postal).setText(c.postalCode)
                findViewById<EditText>(R.id.et_buyer_city).setText(c.city)
            }
        }
    }

    /** Przycisk "Zapisz nabywcę" — pyta o potwierdzenie (styl AppDialog, jak
     *  reszta aplikacji) i zapisuje aktualnie wpisane dane sekcji "Nabywca"
     *  jako kontrahenta. Jeśli kontrahent o tej samej nazwie już istnieje,
     *  jego dane są aktualizowane zamiast tworzenia duplikatu. */
    private fun confirmSaveContractor() {
        val buyerName = findViewById<EditText>(R.id.et_buyer_name).text.toString().trim()
        val buyerNip = findViewById<EditText>(R.id.et_buyer_nip).text.toString().trim()
        val buyerStreet = findViewById<EditText>(R.id.et_buyer_street).text.toString().trim()
        val buyerPostal = findViewById<EditText>(R.id.et_buyer_postal).text.toString().trim()
        val buyerCity = findViewById<EditText>(R.id.et_buyer_city).text.toString().trim()

        if (buyerName.isBlank()) {
            Toast.makeText(this, getString(R.string.invoice_fill_required_fields), Toast.LENGTH_SHORT).show()
            return
        }

        AppDialog.show(
            context = this,
            title = getString(R.string.save_contractor_confirm_title),
            message = getString(R.string.save_contractor_confirm_message, buyerName),
            positiveText = getString(R.string.confirm_yes),
            onPositive = {
                CoroutineScope(Dispatchers.IO).launch {
                    val dao = AppDatabase.getInstance(applicationContext).contractorDao()
                    val existing = dao.getByName(buyerName)
                    if (existing != null) {
                        dao.update(
                            existing.copy(
                                isPhysicalPerson = isPhysicalPerson,
                                nip = if (isPhysicalPerson) null else buyerNip,
                                street = buyerStreet,
                                postalCode = buyerPostal,
                                city = buyerCity,
                                updatedAtMillis = System.currentTimeMillis()
                            )
                        )
                    } else {
                        dao.insert(
                            Contractor(
                                isPhysicalPerson = isPhysicalPerson,
                                name = buyerName,
                                nip = if (isPhysicalPerson) null else buyerNip,
                                street = buyerStreet,
                                postalCode = buyerPostal,
                                city = buyerCity
                            )
                        )
                    }
                    withContext(Dispatchers.Main) {
                        Toast.makeText(this@AddInvoiceActivity, getString(R.string.contractor_saved), Toast.LENGTH_SHORT).show()
                    }
                }
            },
            negativeText = getString(R.string.confirm_cancel)
        )
    }

    private fun refreshCashLimit() {'''

str_replace_any(path, ['    private fun refreshCashLimit() {'], functions_block, "applyPickedContractor/confirmSaveContractor")
PYEOF_ADDINVOICE

echo ""
echo "-> krok 4/6: activity_add_invoice.xml (przyciski Wybierz/Zapisz kontrahenta)"
python3 << 'PYEOF_LAYOUT'
import sys

def str_replace_any(path, candidates, new, label):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    for old in candidates:
        count = content.count(old)
        if count == 1:
            content = content.replace(old, new, 1)
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"OK: {label} -> {path}")
            return
    if new in content:
        print(f"Pominieto (juz zastosowano wczesniej): {label} w {path}")
        return
    print(f"BLAD (zaden ze znanych wariantow nie pasuje): {label} w {path}")
    sys.exit(1)

path = "app/src/main/res/layout/activity_add_invoice.xml"

old_before_switch = '''            android:letterSpacing="0.08"
            android:layout_marginBottom="12dp"/>

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical"
            android:layout_marginBottom="14dp">
            <Switch
                android:id="@+id/sw_physical_person"'''

new_before_switch = '''            android:letterSpacing="0.08"
            android:layout_marginBottom="12dp"/>

        <Button
            android:id="@+id/btn_select_contractor"
            android:layout_width="match_parent"
            android:layout_height="40dp"
            android:layout_marginBottom="12dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/select_contractor_button"
            android:textAllCaps="false"
            android:textSize="13sp"
            android:textColor="@color/text_primary"/>

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical"
            android:layout_marginBottom="14dp">
            <Switch
                android:id="@+id/sw_physical_person"'''

str_replace_any(path, [old_before_switch], new_before_switch, "btn_select_contractor")

old_after_city = '''            <EditText android:id="@+id/et_buyer_postal" style="@style/InvoiceInputHalfStart" android:hint="@string/buyer_address_postal" android:inputType="text"/>
            <EditText android:id="@+id/et_buyer_city" style="@style/InvoiceInputHalfEnd" android:hint="@string/buyer_address_city" android:inputType="text"/>
        </LinearLayout>

    </LinearLayout>

    <!-- Usługa / towar -->'''

new_after_city = '''            <EditText android:id="@+id/et_buyer_postal" style="@style/InvoiceInputHalfStart" android:hint="@string/buyer_address_postal" android:inputType="text"/>
            <EditText android:id="@+id/et_buyer_city" style="@style/InvoiceInputHalfEnd" android:hint="@string/buyer_address_city" android:inputType="text"/>
        </LinearLayout>

        <Button
            android:id="@+id/btn_save_contractor"
            android:layout_width="match_parent"
            android:layout_height="40dp"
            android:layout_marginTop="12dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/save_contractor_button"
            android:textAllCaps="false"
            android:textSize="13sp"
            android:textColor="@color/text_primary"/>

    </LinearLayout>

    <!-- Usługa / towar -->'''

str_replace_any(path, [old_after_city], new_after_city, "btn_save_contractor")
PYEOF_LAYOUT

echo ""
echo "-> krok 5/6: AndroidManifest.xml (rejestracja SelectContractorActivity)"
python3 << 'PYEOF_MANIFEST'
import sys

def str_replace_any(path, candidates, new, label):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    for old in candidates:
        count = content.count(old)
        if count == 1:
            content = content.replace(old, new, 1)
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"OK: {label} -> {path}")
            return
    if new in content:
        print(f"Pominieto (juz zastosowano wczesniej): {label} w {path}")
        return
    print(f"BLAD (zaden ze znanych wariantow nie pasuje): {label} w {path}")
    sys.exit(1)

str_replace_any(
    "app/src/main/AndroidManifest.xml",
    ['        <activity android:name=".SelectProductsActivity" android:exported="false" />'],
    '        <activity android:name=".SelectProductsActivity" android:exported="false" />\n        <activity android:name=".SelectContractorActivity" android:exported="false" />',
    "SelectContractorActivity"
)
PYEOF_MANIFEST

echo ""
echo "-> krok 6/6: stringi (en/pl/ru)"
python3 << 'PYEOF_STRINGS'
import sys

def str_replace_any(path, candidates, new, label):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    for old in candidates:
        count = content.count(old)
        if count == 1:
            content = content.replace(old, new, 1)
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"OK: {label} -> {path}")
            return
    if new in content:
        print(f"Pominieto (juz zastosowano wczesniej): {label} w {path}")
        return
    print(f"BLAD (zaden ze znanych wariantow nie pasuje): {label} w {path}")
    sys.exit(1)

LOCALES = {
    "app/src/main/res/values/strings.xml": {
        "old": ('    <string name="buyer_address_city">City</string>\n'
                '    <string name="invoice_service_section">Item / service</string>'),
        "new": ('    <string name="buyer_address_city">City</string>\n'
                '    <string name="select_contractor_button">Select contractor</string>\n'
                '    <string name="save_contractor_button">Save buyer</string>\n'
                '    <string name="select_contractor_title">Select contractor</string>\n'
                '    <string name="contractors_empty">No saved contractors yet. Fill in the buyer details and tap "Save buyer".</string>\n'
                '    <string name="save_contractor_confirm_title">Save buyer</string>\n'
                '    <string name="save_contractor_confirm_message">Save "%1$s" as a contractor for future invoices?</string>\n'
                '    <string name="contractor_saved">Contractor saved</string>\n'
                '    <string name="delete_contractor_confirm_title">Delete contractor?</string>\n'
                '    <string name="delete_contractor_confirm_message">Delete "%1$s" from saved contractors?</string>\n'
                '    <string name="contractor_deleted">Contractor deleted</string>\n'
                '    <string name="invoice_service_section">Item / service</string>'),
    },
    "app/src/main/res/values-pl/strings.xml": {
        "old": ('    <string name="buyer_address_city">Miasto</string>\n'
                '    <string name="invoice_service_section">Usługa / towar</string>'),
        "new": ('    <string name="buyer_address_city">Miasto</string>\n'
                '    <string name="select_contractor_button">Wybierz kontrahenta</string>\n'
                '    <string name="save_contractor_button">Zapisz nabywcę</string>\n'
                '    <string name="select_contractor_title">Wybór kontrahenta</string>\n'
                '    <string name="contractors_empty">Brak zapisanych kontrahentów. Wypełnij dane nabywcy i naciśnij "Zapisz nabywcę".</string>\n'
                '    <string name="save_contractor_confirm_title">Zapisz nabywcę</string>\n'
                '    <string name="save_contractor_confirm_message">Zapisać "%1$s" jako kontrahenta do kolejnych faktur?</string>\n'
                '    <string name="contractor_saved">Kontrahent zapisany</string>\n'
                '    <string name="delete_contractor_confirm_title">Usunąć kontrahenta?</string>\n'
                '    <string name="delete_contractor_confirm_message">Usunąć "%1$s" z zapisanych kontrahentów?</string>\n'
                '    <string name="contractor_deleted">Kontrahent usunięty</string>\n'
                '    <string name="invoice_service_section">Usługa / towar</string>'),
    },
    "app/src/main/res/values-ru/strings.xml": {
        "old": ('    <string name="buyer_address_city">Город</string>\n'
                '    <string name="invoice_service_section">Услуга / товар</string>'),
        "new": ('    <string name="buyer_address_city">Город</string>\n'
                '    <string name="select_contractor_button">Выбрать контрагента</string>\n'
                '    <string name="save_contractor_button">Сохранить покупателя</string>\n'
                '    <string name="select_contractor_title">Выбор контрагента</string>\n'
                '    <string name="contractors_empty">Пока нет сохранённых контрагентов. Заполните данные покупателя и нажмите "Сохранить покупателя".</string>\n'
                '    <string name="save_contractor_confirm_title">Сохранить покупателя</string>\n'
                '    <string name="save_contractor_confirm_message">Сохранить "%1$s" как контрагента для следующих счетов?</string>\n'
                '    <string name="contractor_saved">Контрагент сохранён</string>\n'
                '    <string name="delete_contractor_confirm_title">Удалить контрагента?</string>\n'
                '    <string name="delete_contractor_confirm_message">Удалить "%1$s" из сохранённых контрагентов?</string>\n'
                '    <string name="contractor_deleted">Контрагент удалён</string>\n'
                '    <string name="invoice_service_section">Услуга / товар</string>'),
    },
}

for path, spec in LOCALES.items():
    str_replace_any(path, [spec["old"]], spec["new"], "stringi kontrahenta")
PYEOF_STRINGS

echo ""
echo "Gotowe."
echo ""
echo "Co zrobic dalej (Termux):"
echo "  git add -A"
echo "  git commit -m \"update 64: zapisani kontrahenci (nabywcy) - wybor z listy zamiast recznego wpisywania za kazdym razem\""
echo "  git push origin main"
