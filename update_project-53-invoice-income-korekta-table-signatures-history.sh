#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=== Obновление 53: dochod z faktury dla dzialalnosci nierejestrowanej + tabele w korekcie + podpisy + korekty w Historii ==="
echo "Co sie zmienia:"
echo " 1) NAPRAWIONE: dochod z wystawionej faktury nie byl w ogole zapisywany"
echo "    do transakcji (Entry) dla dzialalnosci NIEZAREJESTROWANEJ - dlatego"
echo "    nie liczyl sie automatycznie w podatku/limitach ani nie pokazywal"
echo "    sie na glownym ekranie. Wlasnie dlatego korekta (ktora zawsze"
echo "    zapisywala tylko roznice, np. -100 zl) w rezultacie pokazywala minus"
echo "    - oryginalna kwota nigdy nie zostala policzona jako przychod."
echo "    Teraz wystawienie faktury ZAWSZE tworzy wpis przychodu (Entry),"
echo "    niezaleznie od typu dzialalnosci - tak jak dla zarejestrowanej JDG."
echo " 2) Faktura korygujaca (korekta) miala tylko trzy linijki tekstu z"
echo "    kwotami, bez zadnej tabeli. Teraz PDF korekty ma DWIE tabele"
echo "    pozycji: \"Przed korekta\" (oryginalne pozycje faktury) i \"Po korekcie\""
echo "    (te same pozycje przeskalowane do nowej sumy), z kolumnami"
echo "    netto/VAT/brutto gdy sprzedawca jest podatnikiem VAT."
echo " 3) Na OBU dokumentach (faktura i faktura korygujaca) dodano pola"
echo "    podpisu \"Wystawil(a):\" / \"Odebral(a):\" z podpisem pod ramka."
echo " 4) Korekty byly widoczne tylko z poziomu oryginalnej faktury i wcale"
echo "    nie trafialy do Historii faktur. Teraz Historia faktur pokazuje"
echo "    JEDNA chronologiczna liste: zwykle faktury + korekty (oznaczone"
echo "    znakiem ↺, z kwota = sama roznica, kolorowana zielono/czerwono)."
echo "    Dziala w niej wyszukiwanie i filtr dat tak samo jak dla faktur."
echo "    Usuniecie korekty (przycisk X) usuwa jej rekord i plik PDF,"
echo "    dokladnie tak samo jak usuniecie zwyklej faktury."
echo " 5) Baza danych: dodano kolumne originalInvoiceNumber w tabeli"
echo "    invoice_corrections (migracja 10->11), zeby wiersz korekty w"
echo "    Historii pozostal czytelny nawet gdyby oryginalna faktura zostala"
echo "    pozniej usunieta."
echo ""

if [ ! -f "settings.gradle" ] || [ ! -d "app/src/main/java/com/example/fa_ksiegowy" ]; then
    echo "!!! Uruchom skrypt z korzenia projektu (tam, gdzie jest settings.gradle)"
    exit 1
fi

if grep -q "originalInvoiceNumber" "app/src/main/java/com/example/fa_ksiegowy/InvoiceCorrection.kt" 2>/dev/null; then
    echo "!!! Wyglada na to, ze update_project-53 zostal juz zastosowany (InvoiceCorrection.kt ma juz originalInvoiceNumber)"
    exit 1
fi

BACKUP_DIR=".update53_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
for f in \
    "app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/InvoiceCorrection.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/AppDatabase.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/AddInvoiceCorrectionActivity.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/InvoicePdfGenerator.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/InvoiceHistoryItem.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/InvoiceAdapter.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/InvoiceHistoryActivity.kt" \
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
echo "-> app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt"
mkdir -p "$(dirname 'app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt')"
cat > 'app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt' << 'FAEOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_ADDINVOICEACTIVITY_KT'
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

                // Update: доход из выставленной фактуры ЗАПИСЫВАЕТСЯ АВТОМАТИЧЕСКИ как
                // приход (Entry) — для ЛЮБОГО типа деятельности, включая
                // NIEZAREJESTROWANA. Раньше это делалось только для зарегистрированной
                // JDG, а для działalności nierejestrowanej фактура вообще не попадала
                // ни в транзакции, ни на главный экран, ни в расчёт лимитов/налога —
                // пользователю приходилось дублировать доход вручную (зголошение
                // użytkownika: "выставил фактуру а доход не засчитали"). Именно из-за
                // этого пропуска korekta потом выставляла в Historii только "голую"
                // дельту (например -100 zł) без учёта исходной суммы — итог уходил в
                // минус. Теперь запись дохода при выставлении фактуры одинакова для
                // всех типов деятельности; для niezarejestrowanej лимит/налог считаются
                // ровно так же, как для JDG_SKALA (см. LimitsHelper/TaxHelper).
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
FAEOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_ADDINVOICEACTIVITY_KT

echo "-> app/src/main/java/com/example/fa_ksiegowy/InvoiceCorrection.kt"
mkdir -p "$(dirname 'app/src/main/java/com/example/fa_ksiegowy/InvoiceCorrection.kt')"
cat > 'app/src/main/java/com/example/fa_ksiegowy/InvoiceCorrection.kt' << 'FAEOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICECORRECTION_KT'
package com.example.fa_ksiegowy

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Update: Faktura korygująca — dokument korygujący wcześniej wystawioną fakturę/
 * rachunek (błędna kwota, zwrot części zapłaty, dopłata). Przechowuje deltę
 * (dodatnią lub ujemną różnicę kwoty sprzedaży: correctedAmount - originalAmount)
 * potrzebną do przeliczenia Przychodu — patrz AddInvoiceCorrectionActivity, gdzie
 * ta delta może zostać dodatkowo zapisana jako Entry (korekta przychodu).
 *
 * originalAmount jest kopiowana z oryginalnej faktury w chwili wystawienia korekty
 * (nie odczytywana na bieżąco z Invoice) — żeby historia korekt pozostała spójna
 * nawet gdyby oryginalna faktura została później usunięta.
 */
@Entity(tableName = "invoice_corrections")
data class InvoiceCorrection(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val originalInvoiceId: Long,
    /** Update: numer oryginalnej faktury skopiowany w chwili wystawienia korekty —
     *  z tego samego powodu co originalAmount powyżej: żeby korekta pozostała
     *  czytelna w Historii faktur nawet gdyby oryginalna faktura (Invoice) została
     *  później usunięta. Dla korekt zapisanych PRZED tą aktualizacją (migracja
     *  10->11) wartość domyślna to 0 — InvoiceHistoryActivity w takim wypadku
     *  dogląda numeru z wciąż istniejącej oryginalnej faktury po originalInvoiceId. */
    val originalInvoiceNumber: Int = 0,
    val correctionNumber: Int,
    val issueDateMillis: Long,
    val reason: String,
    val originalAmount: Double,
    val correctedAmount: Double,
    /** correctedAmount - originalAmount — dodatnia (dopłata) lub ujemna (zwrot). */
    val deltaAmount: Double,
    val pdfFilePath: String,
    val pdfFileName: String,
    /** true, jeśli delta została też zapisana jako Entry (korekta przychodu). */
    val appliedToIncome: Boolean = false
)

FAEOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICECORRECTION_KT

echo "-> app/src/main/java/com/example/fa_ksiegowy/AppDatabase.kt"
mkdir -p "$(dirname 'app/src/main/java/com/example/fa_ksiegowy/AppDatabase.kt')"
cat > 'app/src/main/java/com/example/fa_ksiegowy/AppDatabase.kt' << 'FAEOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_APPDATABASE_KT'
package com.example.fa_ksiegowy

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [Entry::class, Invoice::class, RecurringEntry::class, Product::class, InvoiceItem::class, InventoryRecord::class, InventorySession::class, InvoiceCorrection::class],
    version = 11,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun entryDao(): EntryDao

    abstract fun invoiceDao(): InvoiceDao

    abstract fun invoiceCorrectionDao(): InvoiceCorrectionDao

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

        /** v9 -> v10: moduł Korekta (Faktura korygująca) — nowa tabela przechowująca
         *  wystawione korekty wcześniejszych faktur/rachunków wraz z deltą kwoty
         *  sprzedaży (patrz InvoiceCorrection). Obyczajna migracja, bez utraty
         *  już zapisanych danych. */
        private val MIGRATION_9_10 = object : Migration(9, 10) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    "CREATE TABLE IF NOT EXISTS `invoice_corrections` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `originalInvoiceId` INTEGER NOT NULL, `correctionNumber` INTEGER NOT NULL, `issueDateMillis` INTEGER NOT NULL, `reason` TEXT NOT NULL, `originalAmount` REAL NOT NULL, `correctedAmount` REAL NOT NULL, `deltaAmount` REAL NOT NULL, `pdfFilePath` TEXT NOT NULL, `pdfFileName` TEXT NOT NULL, `appliedToIncome` INTEGER NOT NULL DEFAULT 0)"
                )
            }
        }

        /** v10 -> v11: Historia faktur теперь показывает и обычные фактуры, и
         *  korekty (faktury korygujące) в ЕДИНОМ списке (см. InvoiceHistoryItem,
         *  InvoiceHistoryActivity) — раньше korekty были видны только через
         *  экран original фактуры и вообще не сохранялись в Historii. Чтобы строка
         *  korekty в истории оставалась читаемой даже если оригинальная Invoice
         *  будет позже удалена, копируем номер оригинальной фактуры прямо в
         *  InvoiceCorrection (тот же приём, что уже применён к originalAmount). */
        private val MIGRATION_10_11 = object : Migration(10, 11) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL("ALTER TABLE invoice_corrections ADD COLUMN originalInvoiceNumber INTEGER NOT NULL DEFAULT 0")
                database.execSQL(
                    "UPDATE invoice_corrections SET originalInvoiceNumber = (" +
                        "SELECT invoiceNumber FROM invoices WHERE invoices.id = invoice_corrections.originalInvoiceId" +
                        ") WHERE EXISTS (SELECT 1 FROM invoices WHERE invoices.id = invoice_corrections.originalInvoiceId)"
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
                ).addMigrations(MIGRATION_3_4, MIGRATION_4_5, MIGRATION_5_6, MIGRATION_6_7, MIGRATION_7_8, MIGRATION_8_9, MIGRATION_9_10, MIGRATION_10_11).fallbackToDestructiveMigration().build().also { INSTANCE = it }
            }
        }
    }
}

FAEOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_APPDATABASE_KT

echo "-> app/src/main/java/com/example/fa_ksiegowy/AddInvoiceCorrectionActivity.kt"
mkdir -p "$(dirname 'app/src/main/java/com/example/fa_ksiegowy/AddInvoiceCorrectionActivity.kt')"
cat > 'app/src/main/java/com/example/fa_ksiegowy/AddInvoiceCorrectionActivity.kt' << 'FAEOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_ADDINVOICECORRECTIONACTIVITY_KT'
package com.example.fa_ksiegowy

import android.os.Bundle
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Update: экран выставления Faktura korygująca (корректировочной фактуры) к уже
 * выставленному документу. Открывается из InvoiceHistoryActivity по кнопке "↺"
 * на строке фактуры (см. InvoiceAdapter/item_invoice.xml), обязательный extra —
 * EXTRA_INVOICE_ID.
 *
 * Дельта (correctedAmount - originalAmount) может быть, по желанию пользователя
 * (галочка cb_apply_to_income, отмечена по умолчанию), сразу же записана как Entry
 * (isIncome=true, amount=delta) — это тот же самый механизм, которым обычные
 * приходы уже участвуют в расчёте Dochód/Podatek/лимитов (см. TaxHelper/LimitsHelper),
 * поэтому отдельно трогать их не нужно: отрицательная delta корректно уменьшит
 * Przychód, положительная — увеличит.
 */
class AddInvoiceCorrectionActivity : BaseActivity() {

    companion object {
        const val EXTRA_INVOICE_ID = "invoiceId"
    }

    private lateinit var originalInvoice: Invoice
    private val moneyFmt = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_add_invoice_correction)

        val invoiceId = intent.getLongExtra(EXTRA_INVOICE_ID, -1L)
        if (invoiceId < 0) {
            finish()
            return
        }

        CoroutineScope(Dispatchers.IO).launch {
            val invoice = AppDatabase.getInstance(applicationContext).invoiceDao().getById(invoiceId)
            withContext(Dispatchers.Main) {
                if (invoice == null) {
                    finish()
                    return@withContext
                }
                originalInvoice = invoice
                bindOriginalInvoiceInfo()
            }
        }

        findViewById<Button>(R.id.btn_save_correction).setOnClickListener { saveCorrection() }
    }

    private fun bindOriginalInvoiceInfo() {
        findViewById<TextView>(R.id.tv_original_invoice_info).text =
            getString(R.string.correction_original_invoice_label, originalInvoice.invoiceNumber, originalInvoice.buyerName)
        val amountStr = String.format(Locale.getDefault(), "%.2f", originalInvoice.amount)
        findViewById<TextView>(R.id.tv_original_amount).text =
            "${getString(R.string.correction_original_amount_label)}: $amountStr zł · ${moneyFmt.format(Date(originalInvoice.issueDateMillis))}"
        findViewById<EditText>(R.id.et_corrected_amount).setText(
            String.format(Locale.US, "%.2f", originalInvoice.amount)
        )
    }

    private fun saveCorrection() {
        val correctedText = findViewById<EditText>(R.id.et_corrected_amount).text.toString().replace(",", ".").trim()
        val corrected = correctedText.toDoubleOrNull()
        if (corrected == null) {
            Toast.makeText(this, getString(R.string.enter_amount), Toast.LENGTH_SHORT).show()
            return
        }
        val reason = findViewById<EditText>(R.id.et_reason).text.toString().trim()
        if (reason.isBlank()) {
            Toast.makeText(this, getString(R.string.correction_reason_required_error), Toast.LENGTH_SHORT).show()
            return
        }
        val delta = corrected - originalInvoice.amount
        if (delta == 0.0) {
            Toast.makeText(this, getString(R.string.correction_zero_delta_error), Toast.LENGTH_SHORT).show()
            return
        }
        val applyToIncome = findViewById<CheckBox>(R.id.cb_apply_to_income).isChecked
        val btn = findViewById<Button>(R.id.btn_save_correction)
        btn.isEnabled = false

        CoroutineScope(Dispatchers.IO).launch {
            val db = AppDatabase.getInstance(applicationContext)
            val correctionNumber = (db.invoiceCorrectionDao().getMaxCorrectionNumber() ?: 0) + 1
            val issueDateMillis = System.currentTimeMillis()
            val fileName = FileNaming.invoiceCorrectionFileName(correctionNumber, issueDateMillis)

            // Update: pozycje oryginalnej faktury i jej stawka VAT — potrzebne, żeby
            // faktura korygująca miała tabelę pozycji ("Przed korektą" / "Po korekcie"),
            // a nie tylko trzy linijki tekstu z kwotami (zgłoszenie użytkownika).
            val originalItems = db.invoiceItemDao().getForInvoice(originalInvoice.id)
            val originalVatRate = VatRate.fromStorageKeyOrNull(originalInvoice.vatRate)

            val saved = InvoiceFileStorage.savePdf(applicationContext, fileName) { out ->
                InvoicePdfGenerator.generateCorrection(
                    context = this@AddInvoiceCorrectionActivity,
                    seller = InvoiceSellerDataStore.load(applicationContext),
                    correctionNumber = correctionNumber,
                    issueDateMillis = issueDateMillis,
                    originalInvoiceNumber = originalInvoice.invoiceNumber,
                    originalIssueDateMillis = originalInvoice.issueDateMillis,
                    buyerName = originalInvoice.buyerName,
                    buyerNip = originalInvoice.buyerNip,
                    buyerStreet = originalInvoice.buyerStreet,
                    buyerPostalCode = originalInvoice.buyerPostalCode,
                    buyerCity = originalInvoice.buyerCity,
                    originalAmount = originalInvoice.amount,
                    correctedAmount = corrected,
                    reason = reason,
                    items = originalItems,
                    vatRate = originalVatRate,
                    out = out
                )
            }

            db.invoiceCorrectionDao().insert(
                InvoiceCorrection(
                    originalInvoiceId = originalInvoice.id,
                    originalInvoiceNumber = originalInvoice.invoiceNumber,
                    correctionNumber = correctionNumber,
                    issueDateMillis = issueDateMillis,
                    reason = reason,
                    originalAmount = originalInvoice.amount,
                    correctedAmount = corrected,
                    deltaAmount = delta,
                    pdfFilePath = saved.uri.toString(),
                    pdfFileName = fileName,
                    appliedToIncome = applyToIncome
                )
            )

            if (applyToIncome) {
                db.entryDao().insert(
                    Entry(
                        amount = delta,
                        isIncome = true,
                        comment = getString(R.string.correction_pdf_title) + " ${correctionNumber} — " +
                            getString(R.string.correction_pdf_to_invoice) + " ${originalInvoice.invoiceNumber}",
                        dateMillis = issueDateMillis,
                        receiptPath = null,
                        ryczaltCategory = null
                    )
                )
            }

            withContext(Dispatchers.Main) {
                Toast.makeText(this@AddInvoiceCorrectionActivity, getString(R.string.correction_saved_toast), Toast.LENGTH_SHORT).show()
                InvoiceFileStorage.openPdfSafely(this@AddInvoiceCorrectionActivity, saved.uri.toString())
                finish()
            }
        }
    }
}

FAEOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_ADDINVOICECORRECTIONACTIVITY_KT

echo "-> app/src/main/java/com/example/fa_ksiegowy/InvoicePdfGenerator.kt"
mkdir -p "$(dirname 'app/src/main/java/com/example/fa_ksiegowy/InvoicePdfGenerator.kt')"
cat > 'app/src/main/java/com/example/fa_ksiegowy/InvoicePdfGenerator.kt' << 'FAEOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEPDFGENERATOR_KT'
package com.example.fa_ksiegowy

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Paint
import android.graphics.RectF
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
 *
 * Update 49: wygląd dopasowany do kolorystyki aplikacji (accent_blue_dark /
 * accent_cyan z colors.xml), logo rysowane z pełnej rozdzielczości źródła
 * (bez ręcznego pomniejszania bitmapy — ostrzejszy druk), naprawiona tabela
 * VAT (kolumny nie nachodzą już na siebie, osobne etykiety "Cena netto" i
 * "Wartość netto"), numer dokumentu w formacie Numer/MM/RRRR, oraz poprawiony
 * opis przełącznika paragonu ("faktura do paragonu", nie "faktura jako paragon").
 *
 * Update 47 (nałożone NA WIERZCH powyższego redesignu): tytuł dokumentu zawsze
 * "FAKTURA" (nigdy "RACHUNEK"), plakietka sprzedawcy "Osoba fizyczna prowadząca
 * działalność nierejestrowaną (bez NIP)", poprawiony styl/pozycja plakietki
 * nabywcy, nowy blok "Podstawa prawna zwolnienia z VAT", oraz [generateCorrection]
 * dla modułu Korekta (Faktura korygująca).
 */
object InvoicePdfGenerator {

    private const val PAGE_WIDTH = 595
    private const val PAGE_HEIGHT = 842
    private const val MARGIN = 48f

    // Paleta zgodna z app/src/main/res/values/colors.xml (accent_blue_dark,
    // accent_cyan, card_bg) — dokument ma być wizualnie spójny z aplikacją.
    private const val COLOR_TEXT = 0xFF12162E.toInt()
    private const val COLOR_ACCENT = 0xFF1230A8.toInt()
    private const val COLOR_ACCENT_LIGHT = 0xFF29B6F6.toInt()
    private const val COLOR_HEADER_FILL = 0xFFE9F2FE.toInt()
    private const val COLOR_ROW_ALT = 0xFFF6F9FE.toInt()
    private const val COLOR_HINT = 0xFF6B7094.toInt()
    private const val COLOR_GRID = 0xFFC7D3E8.toInt()

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
        val tablePriceNetto: String,
        val tableVatRate: String,
        val tableVatAmount: String,
        val tableBrutto: String,
        val receiptLabel: String,
        val signIssuedBy: String,
        val signReceivedBy: String,
        val signIssuedByCaption: String,
        val signReceivedByCaption: String
    )

    private fun buildLabels(context: Context, isVatPayer: Boolean, paymentMethod: PaymentMethod): Labels = Labels(
        // Update 47: dokument zawsze nazywa się "FAKTURA" (nigdy "RACHUNEK"), niezależnie
        // od statusu VAT sprzedawcy — zgłoszenie użytkownika (zrzuty ekranu), tytuł
        // dokumentu ma być jednolity dla wszystkich wystawianych dokumentów sprzedaży.
        docKind = context.getString(R.string.invoice_pdf_faktura),
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
        tablePriceNetto = context.getString(R.string.invoice_pdf_table_price_netto),
        tableVatRate = context.getString(R.string.invoice_pdf_table_vat_rate),
        tableVatAmount = context.getString(R.string.invoice_pdf_table_vat_amount),
        tableBrutto = context.getString(R.string.invoice_pdf_table_brutto),
        receiptLabel = context.getString(R.string.invoice_pdf_receipt_label),
        signIssuedBy = context.getString(R.string.invoice_pdf_signature_issued_by),
        signReceivedBy = context.getString(R.string.invoice_pdf_signature_received_by),
        signIssuedByCaption = context.getString(R.string.invoice_pdf_signature_issued_by_caption),
        signReceivedByCaption = context.getString(R.string.invoice_pdf_signature_received_by_caption)
    )

    /** Dzieli tekst na linie tak, by żadna nie przekraczała `maxWidth` przy danym `paint`
     *  (proste zawijanie po spacjach — używane w podpisach pod ramkami podpisu, gdzie
     *  nie ma z góry znanej liczby znaków na linię jak w [wrappedLines] w treści dokumentu). */
    private fun wrapToWidth(text: String, paint: Paint, maxWidth: Float): List<String> {
        val words = text.split(" ")
        val lines = mutableListOf<String>()
        var current = StringBuilder()
        for (w in words) {
            val candidate = if (current.isEmpty()) w else "${current} $w"
            if (paint.measureText(candidate) > maxWidth && current.isNotEmpty()) {
                lines.add(current.toString())
                current = StringBuilder(w)
            } else {
                current = StringBuilder(candidate)
            }
        }
        if (current.isNotEmpty()) lines.add(current.toString())
        return lines
    }

    /**
     * Update: blok podpisów ("Wystawił(a)" / "Odebrał(a)") — dwie ramki obok siebie z
     * podpisem pod spodem, rysowane na KAŻDYM wystawianym dokumencie sprzedaży (zwykła
     * faktura i faktura korygująca), zgodnie ze zgłoszeniem użytkownika (zrzuty ekranu z
     * przykładowym wzorem). Zwraca nową pozycję `y` po narysowaniu bloku.
     */
    private fun drawSignatureBlock(
        canvas: android.graphics.Canvas,
        startY: Float,
        marginLeft: Float,
        pageWidth: Int,
        l: Labels
    ): Float {
        val labelPaint = Paint().apply { color = COLOR_TEXT; textSize = 9f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val captionPaint = Paint().apply { color = COLOR_HINT; textSize = 7.5f; isAntiAlias = true }
        val borderPaint = Paint().apply { color = COLOR_GRID; style = Paint.Style.STROKE; strokeWidth = 0.75f; isAntiAlias = true }

        val gap = 20f
        val boxWidth = (pageWidth - 2 * marginLeft - gap) / 2f
        val boxHeight = 40f
        val leftX = marginLeft
        val rightX = marginLeft + boxWidth + gap

        fun box(x: Float, label: String, caption: String): Float {
            canvas.drawRect(x, startY, x + boxWidth, startY + boxHeight, borderPaint)
            canvas.drawText(label, x + 5f, startY + 13f, labelPaint)
            val captionLines = wrapToWidth(caption, captionPaint, boxWidth)
            var cy = startY + boxHeight + 10f
            for (cl in captionLines) {
                canvas.drawText(cl, x, cy, captionPaint)
                cy += 9f
            }
            return cy
        }

        val leftBottom = box(leftX, l.signIssuedBy, l.signIssuedByCaption)
        val rightBottom = box(rightX, l.signReceivedBy, l.signReceivedByCaption)
        return maxOf(leftBottom, rightBottom)
    }

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
        // niezależnie od rodzaju działalności. Dekodujemy bez przeskalowania
        // przez system (inScaled = false) i rysujemy bezpośrednio w docelowy
        // prostokąt przez drawBitmap(src, dst) — bez ręcznego tworzenia małej
        // kopii bitmapy (createScaledBitmap dawało rozmyty, "pikselowy" wydruk).
        val logoBitmap: Bitmap? = try {
            val opts = BitmapFactory.Options().apply { inScaled = false }
            BitmapFactory.decodeResource(context.resources, R.drawable.logo, opts)
        } catch (e: Exception) {
            null
        }
        val logoPaint = Paint().apply { isAntiAlias = true; isFilterBitmap = true }
        val topBarPaint = Paint().apply { color = COLOR_ACCENT }
        fun drawTopBar() {
            canvas.drawRect(0f, 0f, PAGE_WIDTH.toFloat(), 5f, topBarPaint)
        }
        fun drawLogo() {
            drawTopBar()
            if (logoBitmap == null) return
            val logoSize = 52f
            val left = PAGE_WIDTH - MARGIN - logoSize
            val top = MARGIN - 24f
            val dst = RectF(left, top, left + logoSize, top + logoSize)
            canvas.drawBitmap(logoBitmap, null, dst, logoPaint)
        }
        drawLogo()

        val titlePaint = Paint().apply { color = COLOR_ACCENT; textSize = 20f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val sectionPaint = Paint().apply { color = COLOR_ACCENT; textSize = 11.5f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val textPaint = Paint().apply { color = COLOR_TEXT; textSize = 10.5f; isAntiAlias = true }
        val hintPaint = Paint().apply { color = COLOR_HINT; textSize = 9f; isAntiAlias = true }
        val tableHeaderPaint = Paint().apply { color = COLOR_ACCENT; textSize = 9.5f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val tableCellPaint = Paint().apply { color = COLOR_TEXT; textSize = 10f; isAntiAlias = true }
        val stampPaint = Paint().apply { color = 0xFF1B7F3C.toInt(); textSize = 13f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val pendingStampPaint = Paint().apply { color = 0xFFCC6A00.toInt(); textSize = 13f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val linePaint = Paint().apply { color = COLOR_GRID; strokeWidth = 0.75f; isAntiAlias = true }
        val headerFillPaint = Paint().apply { color = COLOR_HEADER_FILL }
        val rowAltPaint = Paint().apply { color = COLOR_ROW_ALT }
        val accentLinePaint = Paint().apply { color = COLOR_ACCENT_LIGHT; strokeWidth = 1.3f; isAntiAlias = true }
        val receiptBadgePaint = Paint().apply { color = COLOR_ACCENT; textSize = 9.5f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        // Update 47: dedykowany paint dla plakietek prawnych pod danymi sprzedawcy/
        // nabywcy (8pt, szary #555555) — zgodnie ze zgłoszeniem użytkownika (zrzuty
        // ekranu), zamiast hintPaint (9pt, inny odcień szarości).
        val legalNotePaint = Paint().apply { color = 0xFF555555.toInt(); textSize = 8f; isAntiAlias = true }
        val legalBasisTitlePaint = Paint().apply { color = COLOR_TEXT; textSize = 9f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val legalBasisTextPaint = Paint().apply { color = COLOR_TEXT; textSize = 9f; isAntiAlias = true }

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
        val numberFmt = SimpleDateFormat("MM/yyyy", Locale.US)

        // --- Nagłówek: "FAKTURA VAT 3/08/2026" / "RACHUNEK 3/08/2026" —
        // numer dokumentu w formacie Numer/Miesiąc/Rok, tak jak w oficjalnych
        // wzorach faktur (zob. treść zgłoszenia funkcji, przykładowe zdjęcie). ---
        val formattedNumber = "$invoiceNumber/${numberFmt.format(Date(issueDateMillis))}"
        val vatSuffix = if (isVatPayer) " VAT" else ""
        val titleText = "${l.docKind}$vatSuffix $formattedNumber"
        line(titleText, titlePaint, 24f)
        val titleUnderlineY = y - 24f + 6f
        canvas.drawLine(MARGIN, titleUnderlineY, MARGIN + titlePaint.measureText(titleText), titleUnderlineY, accentLinePaint)
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
        // Update 47: plakietka "Osoba fizyczna prowadząca działalność
        // nierejestrowaną (bez NIP)." — TYLKO gdy sprzedawca faktycznie nie jest
        // podatnikiem VAT (brak NIP); po ewentualnej rejestracji VAT sprzedawca ma
        // już NIP i ta plakietka by kłamała. Rysowana zawsze STRICTLY pod ostatnią
        // linią bloku sprzedawcy.
        if (!isVatPayer) {
            wrappedLines(context.getString(R.string.invoice_pdf_seller_nierejestrowana_note), 46, legalNotePaint, 11f, colLeftX)
        }
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
            // Update 47: dedykowany legalNotePaint (8pt, #555555) zamiast hintPaint —
            // wcześniej różny rozmiar/kolor tekstu wizualnie "zlewał się" z adresem
            // powyżej (zgłoszenie użytkownika, zrzuty ekranu); pozycja bez zmian
            // (kolejna linia po adresie, kontynuacja tego samego `y`).
            wrappedLines(l.buyerPrivate, 46, legalNotePaint, 11f, colRightX)
        }
        val rightBottomY = y

        y = maxOf(leftBottomY, rightBottomY) + 18f

        // --- Tabela pozycji ---
        val tableLeft = MARGIN
        val tableRight = PAGE_WIDTH - MARGIN
        val qtyStr: (Double) -> String = { q -> if (q == q.toLong().toDouble()) q.toLong().toString() else q.toString() }

        // Список строк таблицы: если переданы позиции склада — по строке на каждую
        // (с реальным количеством), иначе — одна строка на всю сумму (как раньше,
        // для счетов без привязки к складу).
        data class Row(val name: String, val qty: Double, val unitPrice: Double)
        val rows: List<Row> = if (items.isNotEmpty()) items.map { Row(it.name, it.quantity, it.unitPrice) }
            else listOf(Row(serviceName, 1.0, amount))
        val totalAmount = rows.sumOf { it.qty * it.unitPrice }

        val headerRowHeight = if (vatRate != null) 24f else 20f
        val dataRowHeight = 22f
        val totalRowHeight = 22f

        newPageIfNeeded(70f)
        var segmentTop = y - 10f

        /** Rysuje treść nagłówka kolumny — jeśli tekst nie mieści się w szerokości
         *  kolumny, a zawiera spację, dzieli go na dwie linie (np. "Stawka VAT"
         *  -> "Stawka" / "VAT"). Zapobiega nachodzeniu nagłówków wąskich kolumn
         *  na sąsiednie kolumny (błąd zgłoszony w update 49). */
        fun drawHeaderCell(text: String, x: Float, colWidth: Float, paint: Paint, top: Float, rowHeight: Float) {
            val available = colWidth - 6f
            if (paint.measureText(text) <= available || !text.contains(" ")) {
                canvas.drawText(text, x + 3f, top + rowHeight - 6f, paint)
            } else {
                val words = text.split(" ")
                val line1 = words.first()
                val line2 = words.drop(1).joinToString(" ")
                canvas.drawText(line1, x + 3f, top + rowHeight / 2f - 1f, paint)
                canvas.drawText(line2, x + 3f, top + rowHeight - 4f, paint)
            }
        }

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
                val borderPaint = Paint(linePaint).apply { style = Paint.Style.STROKE; color = COLOR_ACCENT; strokeWidth = 1f }
                canvas.drawRect(tableLeft, segmentTop, tableRight, y, borderPaint)
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
                if (idx % 2 == 1) canvas.drawRect(tableLeft, y, tableRight, y + dataRowHeight, rowAltPaint)
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
            canvas.drawRect(tableLeft, totalRowTop, tableRight, totalRowTop + totalRowHeight, headerFillPaint)
            val totalBaselineY = totalRowTop + totalRowHeight - 7f
            canvas.drawText(l.sumLabel + ":", colPrice - 60f, totalBaselineY, sectionPaint)
            canvas.drawText(money(totalAmount), colTotal + 4f, totalBaselineY, sectionPaint)
            y = totalRowTop + totalRowHeight
            closeSegment(gridBottom)
        } else {
            // --- Tabela VAT (sprzedawca zarejestrowany jako podatnik VAT) —
            // Lp / Nazwa / Jm. / Ilość / Cena netto / Wartość netto / Stawka VAT /
            // Kwota VAT / Wartość brutto, zgodnie z oficjalnym wzorem faktury VAT.
            // Szerokości kolumn dobrane proporcjonalnie do typowego wzoru (mm),
            // żeby żaden nagłówek/wartość nie nachodził na sąsiednią kolumnę —
            // wcześniej kolumna "Stawka VAT" miała zaledwie 34pt szerokości, co
            // powodowało nakładanie się tekstu (błąd zgłoszony w update 49).
            val vatCellPaint = Paint(tableCellPaint).apply { textSize = 8.3f }
            val vatHeaderPaint = Paint(tableHeaderPaint).apply { textSize = 7.6f }
            val vatMoney: (Double) -> String = { String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") }

            val colLp = tableLeft
            val colName = colLp + 23f
            val colUnit = colName + 142f
            val colQty = colUnit + 28f
            val colNetPrice = colQty + 34f
            val colNetValue = colNetPrice + 57f
            val colVatRateCol = colNetValue + 57f
            val colVatAmount = colVatRateCol + 40f
            val colBrutto = colVatAmount + 57f
            val colStops = floatArrayOf(colLp, colName, colUnit, colQty, colNetPrice, colNetValue, colVatRateCol, colVatAmount, colBrutto, tableRight)
            val colWidths = FloatArray(colStops.size - 1) { i -> colStops[i + 1] - colStops[i] }

            fun drawHeaderRow() {
                canvas.drawRect(tableLeft, segmentTop, tableRight, segmentTop + headerRowHeight, headerFillPaint)
                drawHeaderCell(l.tableLp, colLp, colWidths[0], vatHeaderPaint, segmentTop, headerRowHeight)
                drawHeaderCell(l.tableName, colName, colWidths[1], vatHeaderPaint, segmentTop, headerRowHeight)
                drawHeaderCell(l.tableUnit, colUnit, colWidths[2], vatHeaderPaint, segmentTop, headerRowHeight)
                drawHeaderCell(l.tableQty, colQty, colWidths[3], vatHeaderPaint, segmentTop, headerRowHeight)
                drawHeaderCell(l.tablePriceNetto, colNetPrice, colWidths[4], vatHeaderPaint, segmentTop, headerRowHeight)
                drawHeaderCell(l.tableNetto, colNetValue, colWidths[5], vatHeaderPaint, segmentTop, headerRowHeight)
                drawHeaderCell(l.tableVatRate, colVatRateCol, colWidths[6], vatHeaderPaint, segmentTop, headerRowHeight)
                drawHeaderCell(l.tableVatAmount, colVatAmount, colWidths[7], vatHeaderPaint, segmentTop, headerRowHeight)
                drawHeaderCell(l.tableBrutto, colBrutto, colWidths[8], vatHeaderPaint, segmentTop, headerRowHeight)
                y = segmentTop + headerRowHeight
                canvas.drawLine(tableLeft, y, tableRight, y, linePaint)
            }

            fun closeSegment(colLinesBottom: Float) {
                val borderPaint = Paint(linePaint).apply { style = Paint.Style.STROKE; color = COLOR_ACCENT; strokeWidth = 1f }
                canvas.drawRect(tableLeft, segmentTop, tableRight, y, borderPaint)
                for (i in 1 until colStops.size - 1) {
                    canvas.drawLine(colStops[i], segmentTop, colStops[i], colLinesBottom, linePaint)
                }
            }

            // Krótki zapis stawki w komórce danych — pełny opisowy label (np.
            // "23% (podstawowa)") jest za długi na wąską kolumnę, w komórce
            // pokazujemy tylko wartość liczbową ("23%"), a pełny opis jest już
            // czytelny w wyborze stawki w aplikacji.
            val vatRateShort: String = vatRate.percent?.let { p ->
                val asInt = p.toInt()
                if (asInt.toDouble() == p) "$asInt%" else "$p%"
            } ?: vatRate.storageKey

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

                if (idx % 2 == 1) canvas.drawRect(tableLeft, y, tableRight, y + dataRowHeight, rowAltPaint)
                val baselineY = y + dataRowHeight - 7f
                canvas.drawText((idx + 1).toString(), colLp + 3f, baselineY, vatCellPaint)
                canvas.drawText(row.name.take(22), colName + 3f, baselineY, vatCellPaint)
                canvas.drawText(l.unitPiece, colUnit + 3f, baselineY, vatCellPaint)
                canvas.drawText(qtyStr(row.qty), colQty + 3f, baselineY, vatCellPaint)
                canvas.drawText(vatMoney(row.unitPrice), colNetPrice + 3f, baselineY, vatCellPaint)
                canvas.drawText(vatMoney(netValue), colNetValue + 3f, baselineY, vatCellPaint)
                canvas.drawText(vatRateShort, colVatRateCol + 3f, baselineY, vatCellPaint)
                canvas.drawText(vatMoney(vatAmount), colVatAmount + 3f, baselineY, vatCellPaint)
                canvas.drawText(vatMoney(bruttoValue), colBrutto + 3f, baselineY, vatCellPaint)
                y += dataRowHeight
                canvas.drawLine(tableLeft, y, tableRight, y, linePaint)
            }

            val gridBottom = y
            val totalRowTop = y
            canvas.drawRect(tableLeft, totalRowTop, tableRight, totalRowTop + totalRowHeight, headerFillPaint)
            val totalBaselineY = totalRowTop + totalRowHeight - 7f
            canvas.drawText(l.sumLabel + ":", colNetPrice, totalBaselineY, Paint(sectionPaint).apply { textSize = 9f })
            canvas.drawText(vatMoney(totalAmount), colNetValue + 3f, totalBaselineY, Paint(tableCellPaint).apply { textSize = 9f })
            canvas.drawText(vatMoney(vatSum), colVatAmount + 3f, totalBaselineY, Paint(tableCellPaint).apply { textSize = 9f })
            canvas.drawText(vatMoney(bruttoSum), colBrutto + 3f, totalBaselineY, Paint(tableCellPaint).apply { textSize = 9f })
            y = totalRowTop + totalRowHeight
            closeSegment(gridBottom)
        }

        y += 26f

        if (isReceipt) {
            newPageIfNeeded(18f)
            canvas.drawText("● ${l.receiptLabel}", MARGIN, y, receiptBadgePaint)
            y += 18f
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

        // --- Podstawa prawna zwolnienia z VAT ---
        // Update 47: nowy blok, zgłoszenie użytkownika (zrzuty ekranu) — dokument
        // wcześniej w ogóle nie zawierał podstawy prawnej zwolnienia z VAT. Rysowany
        // zawsze w lewej części, POD blokiem terminu/sposobu płatności, TYLKO gdy
        // sprzedawca faktycznie nie jest podatnikiem VAT.
        //
        // Treść jest zawsze po polsku, niezależnie od języka interfejsu aplikacji —
        // to formalna podstawa prawna z polskiej ustawy (stringi istnieją TYLKO w
        // domyślnym values/strings.xml, bez odpowiedników w values-pl/values-ru).
        if (!isVatPayer) {
            newPageIfNeeded(40f)
            line(context.getString(R.string.invoice_pdf_legal_basis_title), legalBasisTitlePaint, 13f)
            wrappedLines(context.getString(R.string.invoice_pdf_legal_basis_text), 78, legalBasisTextPaint, 12f)
        }

        // --- Podpisy: "Wystawił(a)" / "Odebrał(a)" ---
        y += 16f
        newPageIfNeeded(70f)
        y = drawSignatureBlock(canvas, y, MARGIN, PAGE_WIDTH, l)

        document.finishPage(page)
        document.writeTo(out)
        document.close()
    }

    /**
     * Update 47: FAKTURA KORYGUJĄCA — dokument korygujący wcześniej wystawioną
     * fakturę (błędna kwota / zwrot / dopłata). Pokazuje kwotę PRZED korektą,
     * PO korekcie i deltę, plus przyczynę korekty podaną przez użytkownika.
     *
     * Update: dokument ma teraz DWIE TABELE pozycji ("Przed korektą" / "Po
     * korekcie"), tak jak w oficjalnym wzorze faktury korygującej — zgłoszenie
     * użytkownika (wcześniej korekta w ogóle nie miała tabeli, tylko trzy
     * linijki tekstu z kwotami). Tabela "Przed korektą" to dokładnie pozycje
     * ORYGINALNEJ faktury (parametr [items]); tabela "Po korekcie" to te same
     * pozycje przeskalowane tak, by suma odpowiadała [correctedAmount] — jeśli
     * oryginalna faktura nie miała zapisanych pozycji (bardzo stare rekordy),
     * obie tabele pokazują jedną zbiorczą pozycję. Gdy sprzedawca jest już
     * podatnikiem VAT ([vatRate] niepusty), obie tabele pokazują też kolumny
     * netto/VAT/brutto — tak samo jak w [generate].
     */
    fun generateCorrection(
        context: Context,
        seller: InvoiceSellerData,
        correctionNumber: Int,
        issueDateMillis: Long,
        originalInvoiceNumber: Int,
        originalIssueDateMillis: Long,
        buyerName: String,
        buyerNip: String?,
        buyerStreet: String,
        buyerPostalCode: String,
        buyerCity: String,
        originalAmount: Double,
        correctedAmount: Double,
        reason: String,
        /** Pozycje oryginalnej faktury — patrz opis funkcji powyżej. */
        items: List<InvoiceItem> = emptyList(),
        /** Stawka VAT oryginalnej faktury (jeśli sprzedawca jest podatnikiem VAT). */
        vatRate: VatRate? = null,
        out: OutputStream
    ) {
        val isVatPayer = seller.nip.isNotBlank()
        val l = buildLabels(context, isVatPayer, PaymentMethod.TRANSFER)

        val document = PdfDocument()
        var pageNumber = 1
        var page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
        var canvas = page.canvas

        val logoBitmap: Bitmap? = try {
            val opts = BitmapFactory.Options().apply { inScaled = false }
            BitmapFactory.decodeResource(context.resources, R.drawable.logo, opts)
        } catch (e: Exception) { null }
        val logoPaint = Paint().apply { isAntiAlias = true; isFilterBitmap = true }
        val topBarPaint = Paint().apply { color = COLOR_ACCENT }
        fun drawLogo() {
            canvas.drawRect(0f, 0f, PAGE_WIDTH.toFloat(), 5f, topBarPaint)
            if (logoBitmap == null) return
            val logoSize = 52f
            val left = PAGE_WIDTH - MARGIN - logoSize
            val top = MARGIN - 24f
            canvas.drawBitmap(logoBitmap, null, RectF(left, top, left + logoSize, top + logoSize), logoPaint)
        }
        drawLogo()

        val titlePaint = Paint().apply { color = COLOR_ACCENT; textSize = 18f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val sectionPaint = Paint().apply { color = COLOR_ACCENT; textSize = 11.5f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val textPaint = Paint().apply { color = COLOR_TEXT; textSize = 10.5f; isAntiAlias = true }
        val hintPaint = Paint().apply { color = COLOR_HINT; textSize = 9f; isAntiAlias = true }
        val legalNotePaint = Paint().apply { color = 0xFF555555.toInt(); textSize = 8f; isAntiAlias = true }
        val accentLinePaint = Paint().apply { color = COLOR_ACCENT_LIGHT; strokeWidth = 1.3f; isAntiAlias = true }
        val deltaPositivePaint = Paint().apply { color = 0xFF1B7F3C.toInt(); textSize = 13f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val deltaNegativePaint = Paint().apply { color = 0xFFCC3B30.toInt(); textSize = 13f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val tableTitlePaint = Paint().apply { color = COLOR_TEXT; textSize = 10.5f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val tableHeaderPaint = Paint().apply { color = COLOR_ACCENT; textSize = 9.5f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val tableCellPaint = Paint().apply { color = COLOR_TEXT; textSize = 10f; isAntiAlias = true }
        val vatCellPaint = Paint(tableCellPaint).apply { textSize = 8.3f }
        val vatHeaderPaint = Paint(tableHeaderPaint).apply { textSize = 7.6f }
        val linePaint = Paint().apply { color = COLOR_GRID; strokeWidth = 0.75f; isAntiAlias = true }
        val headerFillPaint = Paint().apply { color = COLOR_HEADER_FILL }
        val rowAltPaint = Paint().apply { color = COLOR_ROW_ALT }

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
        fun wrappedLines(text: String, maxCharsPerLine: Int, paint: Paint, gap: Float, x: Float = MARGIN) {
            val words = text.split(" ")
            var current = StringBuilder()
            for (w in words) {
                if (current.length + w.length + 1 > maxCharsPerLine) {
                    newPageIfNeeded(gap)
                    canvas.drawText(current.toString(), x, y, paint); y += gap; current = StringBuilder()
                }
                if (current.isNotEmpty()) current.append(" ")
                current.append(w)
            }
            if (current.isNotEmpty()) { newPageIfNeeded(gap); canvas.drawText(current.toString(), x, y, paint); y += gap }
        }
        val money: (Double) -> String = { String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") + " zł" }
        val dateFmt = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())
        val numberFmt = SimpleDateFormat("MM/yyyy", Locale.US)
        val qtyStr: (Double) -> String = { q -> if (q == q.toLong().toDouble()) q.toLong().toString() else q.toString() }

        val formattedNumber = "$correctionNumber/${numberFmt.format(Date(issueDateMillis))}"
        val originalFormattedNumber = "$originalInvoiceNumber/${numberFmt.format(Date(originalIssueDateMillis))}"
        val titleText = "${context.getString(R.string.correction_pdf_title)} $formattedNumber"
        line(titleText, titlePaint, 22f)
        canvas.drawLine(MARGIN, y - 22f + 6f, MARGIN + titlePaint.measureText(titleText), y - 22f + 6f, accentLinePaint)
        line("${context.getString(R.string.correction_pdf_to_invoice)} $originalFormattedNumber", hintPaint, 18f)
        line("${context.getString(R.string.invoice_pdf_issue_date)}: ${dateFmt.format(Date(issueDateMillis))}", hintPaint, 22f)

        val colLeftX = MARGIN
        val colRightX = MARGIN + (PAGE_WIDTH - 2 * MARGIN) / 2 + 8f
        val blockTopY = y

        y = blockTopY
        line(context.getString(R.string.invoice_pdf_seller), sectionPaint, 17f, colLeftX)
        if (seller.name.isNotBlank()) line(seller.name, textPaint, 14f, colLeftX)
        val sellerAddress = listOfNotNull(
            seller.street.ifBlank { null },
            listOf(seller.postalCode, seller.city).filter { it.isNotBlank() }.joinToString(" ").ifBlank { null }
        ).joinToString(", ")
        if (sellerAddress.isNotBlank()) line(sellerAddress, textPaint, 14f, colLeftX)
        if (seller.nip.isNotBlank()) line("${context.getString(R.string.invoice_pdf_nip)}: ${seller.nip}", textPaint, 14f, colLeftX)
        if (!isVatPayer) wrappedLines(context.getString(R.string.invoice_pdf_seller_nierejestrowana_note), 46, legalNotePaint, 11f, colLeftX)
        val leftBottomY = y

        y = blockTopY
        line(context.getString(R.string.invoice_pdf_buyer), sectionPaint, 17f, colRightX)
        line(buyerName, textPaint, 14f, colRightX)
        val buyerAddress = listOfNotNull(
            buyerStreet.ifBlank { null },
            listOf(buyerPostalCode, buyerCity).filter { it.isNotBlank() }.joinToString(" ").ifBlank { null }
        ).joinToString(", ")
        if (buyerAddress.isNotBlank()) line(buyerAddress, textPaint, 14f, colRightX)
        if (!buyerNip.isNullOrBlank()) {
            line("${context.getString(R.string.invoice_pdf_nip)}: $buyerNip", textPaint, 14f, colRightX)
        } else {
            wrappedLines(context.getString(R.string.invoice_pdf_buyer_private), 46, legalNotePaint, 11f, colRightX)
        }
        val rightBottomY = y

        y = maxOf(leftBottomY, rightBottomY) + 18f

        line(context.getString(R.string.correction_pdf_reason_label), sectionPaint, 17f)
        wrappedLines(reason.ifBlank { "—" }, 78, textPaint, 15f)
        y += 8f

        // --- Dwie tabele pozycji: "Przed korektą" / "Po korekcie" ---
        data class Row(val name: String, val qty: Double, val unitPrice: Double)

        val fallbackLabel = "${context.getString(R.string.correction_pdf_to_invoice)} $originalFormattedNumber"
        val beforeRows: List<Row> = if (items.isNotEmpty()) items.map { Row(it.name, it.quantity, it.unitPrice) }
            else listOf(Row(fallbackLabel, 1.0, originalAmount))
        // Skala przenosząca sumę pozycji z originalAmount na correctedAmount — proporcjonalnie
        // do każdej pozycji (najprostsze i najbardziej przewidywalne rozłożenie różnicy,
        // gdy korekta nie edytuje pozycji jedna po drugiej, tylko podaje nową sumę końcową).
        val scale = if (originalAmount != 0.0) correctedAmount / originalAmount else 1.0
        val afterRows: List<Row> = if (items.isNotEmpty()) items.map { Row(it.name, it.quantity, it.unitPrice * scale) }
            else listOf(Row(fallbackLabel, 1.0, correctedAmount))

        val tableLeft = MARGIN
        val tableRight = PAGE_WIDTH - MARGIN
        val headerRowHeight = if (vatRate != null) 24f else 20f
        val dataRowHeight = 22f
        val totalRowHeight = 22f

        fun drawHeaderCell(text: String, x: Float, colWidth: Float, paint: Paint, top: Float, rowHeight: Float) {
            val available = colWidth - 6f
            if (paint.measureText(text) <= available || !text.contains(" ")) {
                canvas.drawText(text, x + 3f, top + rowHeight - 6f, paint)
            } else {
                val words = text.split(" ")
                canvas.drawText(words.first(), x + 3f, top + rowHeight / 2f - 1f, paint)
                canvas.drawText(words.drop(1).joinToString(" "), x + 3f, top + rowHeight - 4f, paint)
            }
        }

        fun drawTable(title: String, rows: List<Row>) {
            newPageIfNeeded(headerRowHeight + dataRowHeight + totalRowHeight + 16f)
            line(title, tableTitlePaint, 15f)
            var segmentTop = y

            if (vatRate == null) {
                val colLp = tableLeft
                val colName = colLp + 28f
                val colUnit = colName + 232f
                val colQty = colUnit + 46f
                val colPrice = colQty + 46f
                val colTotal = colPrice + 72f
                val colStops = floatArrayOf(colLp, colName, colUnit, colQty, colPrice, colTotal, tableRight)

                fun drawHeaderRow() {
                    canvas.drawRect(tableLeft, segmentTop, tableRight, segmentTop + headerRowHeight, headerFillPaint)
                    val baselineY = segmentTop + headerRowHeight - 6f
                    canvas.drawText(l.tableLp, colLp + 4f, baselineY, tableHeaderPaint)
                    canvas.drawText(l.tableName, colName + 4f, baselineY, tableHeaderPaint)
                    canvas.drawText(l.tableUnit, colUnit + 4f, baselineY, tableHeaderPaint)
                    canvas.drawText(l.tableQty, colQty + 4f, baselineY, tableHeaderPaint)
                    canvas.drawText(l.tablePrice, colPrice + 4f, baselineY, tableHeaderPaint)
                    canvas.drawText(l.tableTotal, colTotal + 4f, baselineY, tableHeaderPaint)
                    y = segmentTop + headerRowHeight
                    canvas.drawLine(tableLeft, y, tableRight, y, linePaint)
                }
                fun closeSegment(bottom: Float) {
                    val borderPaint = Paint(linePaint).apply { style = Paint.Style.STROKE; color = COLOR_ACCENT; strokeWidth = 1f }
                    canvas.drawRect(tableLeft, segmentTop, tableRight, y, borderPaint)
                    for (i in 1 until colStops.size - 1) canvas.drawLine(colStops[i], segmentTop, colStops[i], bottom, linePaint)
                }

                drawHeaderRow()
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
                    if (idx % 2 == 1) canvas.drawRect(tableLeft, y, tableRight, y + dataRowHeight, rowAltPaint)
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
                canvas.drawRect(tableLeft, y, tableRight, y + totalRowHeight, headerFillPaint)
                val totalBaselineY = y + totalRowHeight - 7f
                canvas.drawText(l.sumLabel + ":", colPrice - 60f, totalBaselineY, sectionPaint)
                canvas.drawText(money(rows.sumOf { it.qty * it.unitPrice }), colTotal + 4f, totalBaselineY, sectionPaint)
                y += totalRowHeight
                closeSegment(gridBottom)
            } else {
                val vatMoney: (Double) -> String = { String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") }
                val colLp = tableLeft
                val colName = colLp + 23f
                val colUnit = colName + 142f
                val colQty = colUnit + 28f
                val colNetPrice = colQty + 34f
                val colNetValue = colNetPrice + 57f
                val colVatRateCol = colNetValue + 57f
                val colVatAmount = colVatRateCol + 40f
                val colBrutto = colVatAmount + 57f
                val colStops = floatArrayOf(colLp, colName, colUnit, colQty, colNetPrice, colNetValue, colVatRateCol, colVatAmount, colBrutto, tableRight)
                val colWidths = FloatArray(colStops.size - 1) { i -> colStops[i + 1] - colStops[i] }
                val vatRateShort: String = vatRate.percent?.let { p -> val i = p.toInt(); if (i.toDouble() == p) "$i%" else "$p%" } ?: vatRate.storageKey

                fun drawHeaderRow() {
                    canvas.drawRect(tableLeft, segmentTop, tableRight, segmentTop + headerRowHeight, headerFillPaint)
                    drawHeaderCell(l.tableLp, colLp, colWidths[0], vatHeaderPaint, segmentTop, headerRowHeight)
                    drawHeaderCell(l.tableName, colName, colWidths[1], vatHeaderPaint, segmentTop, headerRowHeight)
                    drawHeaderCell(l.tableUnit, colUnit, colWidths[2], vatHeaderPaint, segmentTop, headerRowHeight)
                    drawHeaderCell(l.tableQty, colQty, colWidths[3], vatHeaderPaint, segmentTop, headerRowHeight)
                    drawHeaderCell(l.tablePriceNetto, colNetPrice, colWidths[4], vatHeaderPaint, segmentTop, headerRowHeight)
                    drawHeaderCell(l.tableNetto, colNetValue, colWidths[5], vatHeaderPaint, segmentTop, headerRowHeight)
                    drawHeaderCell(l.tableVatRate, colVatRateCol, colWidths[6], vatHeaderPaint, segmentTop, headerRowHeight)
                    drawHeaderCell(l.tableVatAmount, colVatAmount, colWidths[7], vatHeaderPaint, segmentTop, headerRowHeight)
                    drawHeaderCell(l.tableBrutto, colBrutto, colWidths[8], vatHeaderPaint, segmentTop, headerRowHeight)
                    y = segmentTop + headerRowHeight
                    canvas.drawLine(tableLeft, y, tableRight, y, linePaint)
                }
                fun closeSegment(bottom: Float) {
                    val borderPaint = Paint(linePaint).apply { style = Paint.Style.STROKE; color = COLOR_ACCENT; strokeWidth = 1f }
                    canvas.drawRect(tableLeft, segmentTop, tableRight, y, borderPaint)
                    for (i in 1 until colStops.size - 1) canvas.drawLine(colStops[i], segmentTop, colStops[i], bottom, linePaint)
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

                    if (idx % 2 == 1) canvas.drawRect(tableLeft, y, tableRight, y + dataRowHeight, rowAltPaint)
                    val baselineY = y + dataRowHeight - 7f
                    canvas.drawText((idx + 1).toString(), colLp + 3f, baselineY, vatCellPaint)
                    canvas.drawText(row.name.take(22), colName + 3f, baselineY, vatCellPaint)
                    canvas.drawText(l.unitPiece, colUnit + 3f, baselineY, vatCellPaint)
                    canvas.drawText(qtyStr(row.qty), colQty + 3f, baselineY, vatCellPaint)
                    canvas.drawText(vatMoney(row.unitPrice), colNetPrice + 3f, baselineY, vatCellPaint)
                    canvas.drawText(vatMoney(netValue), colNetValue + 3f, baselineY, vatCellPaint)
                    canvas.drawText(vatRateShort, colVatRateCol + 3f, baselineY, vatCellPaint)
                    canvas.drawText(vatMoney(vatAmount), colVatAmount + 3f, baselineY, vatCellPaint)
                    canvas.drawText(vatMoney(bruttoValue), colBrutto + 3f, baselineY, vatCellPaint)
                    y += dataRowHeight
                    canvas.drawLine(tableLeft, y, tableRight, y, linePaint)
                }
                val gridBottom = y
                canvas.drawRect(tableLeft, y, tableRight, y + totalRowHeight, headerFillPaint)
                val totalBaselineY = y + totalRowHeight - 7f
                canvas.drawText(l.sumLabel + ":", colNetPrice, totalBaselineY, Paint(sectionPaint).apply { textSize = 9f })
                canvas.drawText(vatMoney(rows.sumOf { it.qty * it.unitPrice }), colNetValue + 3f, totalBaselineY, Paint(tableCellPaint).apply { textSize = 9f })
                canvas.drawText(vatMoney(vatSum), colVatAmount + 3f, totalBaselineY, Paint(tableCellPaint).apply { textSize = 9f })
                canvas.drawText(vatMoney(bruttoSum), colBrutto + 3f, totalBaselineY, Paint(tableCellPaint).apply { textSize = 9f })
                y += totalRowHeight
                closeSegment(gridBottom)
            }
            y += 18f
        }

        drawTable(context.getString(R.string.correction_pdf_before_table_title), beforeRows)
        drawTable(context.getString(R.string.correction_pdf_after_table_title), afterRows)

        // --- Podsumowanie: przyczyna już wypisana wyżej, tu tylko kwoty i delta ---
        newPageIfNeeded(70f)
        val delta = correctedAmount - originalAmount
        line("${context.getString(R.string.correction_pdf_before_label)}: ${money(originalAmount)}", textPaint, 18f)
        line("${context.getString(R.string.correction_pdf_after_label)}: ${money(correctedAmount)}", textPaint, 18f)
        val deltaSign = if (delta >= 0) "+" else ""
        val deltaPaint = if (delta >= 0) deltaPositivePaint else deltaNegativePaint
        line("${context.getString(R.string.correction_pdf_delta_label)}: $deltaSign${money(delta)}", deltaPaint, 24f)

        if (!isVatPayer) {
            newPageIfNeeded(40f)
            line(context.getString(R.string.invoice_pdf_legal_basis_title), Paint(sectionPaint).apply { textSize = 9f; color = COLOR_TEXT }, 13f)
            wrappedLines(context.getString(R.string.invoice_pdf_legal_basis_text), 78, Paint(textPaint).apply { textSize = 9f }, 12f)
        }

        // --- Podpisy: "Wystawił(a)" / "Odebrał(a)" ---
        y += 12f
        newPageIfNeeded(70f)
        y = drawSignatureBlock(canvas, y, MARGIN, PAGE_WIDTH, l)

        document.finishPage(page)
        document.writeTo(out)
        document.close()
    }
}

FAEOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEPDFGENERATOR_KT

echo "-> app/src/main/java/com/example/fa_ksiegowy/InvoiceHistoryItem.kt"
mkdir -p "$(dirname 'app/src/main/java/com/example/fa_ksiegowy/InvoiceHistoryItem.kt')"
cat > 'app/src/main/java/com/example/fa_ksiegowy/InvoiceHistoryItem.kt' << 'FAEOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEHISTORYITEM_KT'
package com.example.fa_ksiegowy

/**
 * Update: jeden wiersz na ekranie InvoiceHistoryActivity — albo zwykła wystawiona
 * faktura/rachunek, albo faktura korygująca (korekta) do wcześniej wystawionego
 * dokumentu. Korekta jest formalnie też fakturą, więc musi być widoczna w Historii
 * faktur na równi ze zwykłymi fakturami — wcześniej korekty nie trafiały do tej
 * listy wcale i były osiągalne tylko z poziomu oryginalnej faktury.
 *
 * Stabilny klucz (patrz [stableKey]) rozróżnia oba typy nawet gdy invoice.id i
 * correction.id przypadkiem się pokrywają (osobne tabele, osobne sekwencje ID).
 */
sealed class InvoiceHistoryItem {
    abstract val issueDateMillis: Long
    abstract val stableKey: String

    data class InvoiceRow(val invoice: Invoice) : InvoiceHistoryItem() {
        override val issueDateMillis get() = invoice.issueDateMillis
        override val stableKey get() = "inv_${invoice.id}"
    }

    /**
     * @param originalInvoiceNumber numer oryginalnej faktury — brany z
     *   [InvoiceCorrection.originalInvoiceNumber], gdy zapisany (>0), a dla starszych
     *   rekordów sprzed migracji 10->11 (0) — z aktualnego numeru wciąż istniejącej
     *   oryginalnej faktury (patrz [InvoiceHistoryActivity.loadData]); jeśli oryginał
     *   też został usunięty, wynikiem jest null i UI pokazuje samą korektę bez numeru.
     */
    data class CorrectionRow(val correction: InvoiceCorrection, val originalInvoiceNumber: Int?) : InvoiceHistoryItem() {
        override val issueDateMillis get() = correction.issueDateMillis
        override val stableKey get() = "cor_${correction.id}"
    }
}
FAEOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEHISTORYITEM_KT

echo "-> app/src/main/java/com/example/fa_ksiegowy/InvoiceAdapter.kt"
mkdir -p "$(dirname 'app/src/main/java/com/example/fa_ksiegowy/InvoiceAdapter.kt')"
cat > 'app/src/main/java/com/example/fa_ksiegowy/InvoiceAdapter.kt' << 'FAEOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEADAPTER_KT'
package com.example.fa_ksiegowy

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.RecyclerView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Список выставленных счетов/фактур — используется на экране InvoiceHistoryActivity.
 *
 * Update: список теперь смешанный (см. [InvoiceHistoryItem]) — обычные фактуры
 * И korekty (faktury korygujące) в одной хронологической ленте, так как korekta
 * это тоже официально выставленный документ и должна быть видна в истории, а не
 * только с экрана оригинальной фактуры.
 */
class InvoiceAdapter(
    private val onItemClick: (Invoice) -> Unit = {},
    private val onCorrectionClick: (InvoiceCorrection) -> Unit = {},
    private val onDeleteClick: (Invoice) -> Unit = {},
    private val onDeleteCorrectionClick: (InvoiceCorrection) -> Unit = {},
    private val onMarkPaidClick: (Invoice) -> Unit = {},
    private val onKorektaClick: (Invoice) -> Unit = {}
) : RecyclerView.Adapter<InvoiceAdapter.VH>() {
    private var items: List<InvoiceHistoryItem> = emptyList()
    private val dateFmt = SimpleDateFormat("dd.MM.yy", Locale.getDefault())

    class VH(view: View) : RecyclerView.ViewHolder(view) {
        val tvDate = view.findViewById<TextView>(R.id.tv_invoice_date)
        val tvBuyer = view.findViewById<TextView>(R.id.tv_invoice_buyer)
        val tvMeta = view.findViewById<TextView>(R.id.tv_invoice_meta)
        val tvAmount = view.findViewById<TextView>(R.id.tv_invoice_amount)
        val btnDelete = view.findViewById<TextView>(R.id.btn_delete_invoice)
        val btnMarkPaid = view.findViewById<TextView>(R.id.btn_mark_paid)
        val btnKorekta = view.findViewById<TextView>(R.id.btn_korekta)
    }

    /**
     * Заменяет список счетов/корректировок с расчётом разницы через DiffUtil —
     * избегаем полной перерисовки при вводе в поиске или смене фильтра дат, что
     * важно для больших списков фактур. Сравнение по [InvoiceHistoryItem.stableKey],
     * который различает фактуры и корректировки даже при совпадающих числовых id.
     */
    fun submitList(newItems: List<InvoiceHistoryItem>) {
        val old = items
        val diff = DiffUtil.calculateDiff(object : DiffUtil.Callback() {
            override fun getOldListSize() = old.size
            override fun getNewListSize() = newItems.size
            override fun areItemsTheSame(oldItemPosition: Int, newItemPosition: Int) =
                old[oldItemPosition].stableKey == newItems[newItemPosition].stableKey
            override fun areContentsTheSame(oldItemPosition: Int, newItemPosition: Int) =
                old[oldItemPosition] == newItems[newItemPosition]
        })
        items = newItems
        diff.dispatchUpdatesTo(this)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val v = LayoutInflater.from(parent.context).inflate(R.layout.item_invoice, parent, false)
        return VH(v)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        when (val item = items[position]) {
            is InvoiceHistoryItem.InvoiceRow -> bindInvoice(holder, item.invoice)
            is InvoiceHistoryItem.CorrectionRow -> bindCorrection(holder, item)
        }
    }

    private fun bindInvoice(holder: VH, inv: Invoice) {
        val context = holder.itemView.context
        holder.tvDate.text = dateFmt.format(Date(inv.issueDateMillis))
        holder.tvBuyer.text = inv.buyerName
        val statusLabel = if (inv.isOverdue) context.getString(R.string.invoice_status_overdue)
            else context.getString(inv.status.labelResId)
        holder.tvMeta.text = "№${inv.invoiceNumber} · " + context.getString(inv.paymentMethod.labelResId) +
            " · " + statusLabel
        holder.tvAmount.text = String.format(Locale.getDefault(), "%.2f", inv.amount)
        val amountColor = when {
            inv.isOverdue -> "#FF6B6B"
            inv.status == InvoiceStatus.PENDING -> "#FFB74D"
            else -> null
        }
        holder.tvAmount.setTextColor(
            if (amountColor != null) android.graphics.Color.parseColor(amountColor)
            else context.getColor(R.color.text_primary)
        )
        holder.btnMarkPaid.visibility = if (inv.status == InvoiceStatus.PENDING) View.VISIBLE else View.GONE
        holder.btnKorekta.visibility = View.VISIBLE
        holder.itemView.setOnClickListener { onItemClick(inv) }
        holder.btnDelete.setOnClickListener { onDeleteClick(inv) }
        holder.btnMarkPaid.setOnClickListener { onMarkPaidClick(inv) }
        holder.btnKorekta.setOnClickListener { onKorektaClick(inv) }
    }

    /**
     * Строка korekty: явно помечена значком "↺" перед номером, сумма показывает
     * ТОЛЬКО дельту (разницу) со знаком и цветом (зелёный — доплата, красный —
     * возврат/уменьшение) — так же, как в самом PDF корректировки. Кнопка "Wystaw
     * korektę" скрыта (korekta к korekcie в текущей модели данных не поддерживается —
     * выставляйте новую корректировку от оригинальной фактуры), кнопка "✓ paid"
     * скрыта (у корректировки нет статуса оплаты), кнопка удаления работает как
     * обычно (удаляет запись и PDF-файл этой корректировки).
     */
    private fun bindCorrection(holder: VH, item: InvoiceHistoryItem.CorrectionRow) {
        val context = holder.itemView.context
        val correction = item.correction
        holder.tvDate.text = dateFmt.format(Date(correction.issueDateMillis))
        holder.tvBuyer.text = "↺ " + if (item.originalInvoiceNumber != null) {
            context.getString(R.string.correction_history_row_title, correction.correctionNumber, item.originalInvoiceNumber)
        } else {
            context.getString(R.string.correction_history_row_title_solo, correction.correctionNumber)
        }
        holder.tvMeta.text = correction.reason
        val delta = correction.deltaAmount
        val sign = if (delta >= 0) "+" else ""
        holder.tvAmount.text = sign + String.format(Locale.getDefault(), "%.2f", delta)
        holder.tvAmount.setTextColor(
            android.graphics.Color.parseColor(if (delta >= 0) "#4CD964" else "#FF6B6B")
        )
        holder.btnMarkPaid.visibility = View.GONE
        holder.btnKorekta.visibility = View.GONE
        holder.itemView.setOnClickListener { onCorrectionClick(correction) }
        holder.btnDelete.setOnClickListener { onDeleteCorrectionClick(correction) }
    }

    override fun getItemCount(): Int = items.size
}
FAEOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEADAPTER_KT

echo "-> app/src/main/java/com/example/fa_ksiegowy/InvoiceHistoryActivity.kt"
mkdir -p "$(dirname 'app/src/main/java/com/example/fa_ksiegowy/InvoiceHistoryActivity.kt')"
cat > 'app/src/main/java/com/example/fa_ksiegowy/InvoiceHistoryActivity.kt' << 'FAEOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEHISTORYACTIVITY_KT'
package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.app.DatePickerDialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Экран истории всех выставленных счетов/фактур (Faktura imienna / Rachunek) И
 * korekt (faktur korygujących) к ним — Update: обе сущности показываются в
 * ОДНОЙ хронологической ленте (см. [InvoiceHistoryItem]), так как korekta это
 * тоже официально выставленный документ и должна быть видна в Historii, а не
 * только доступна с экрана оригинальной фактуры (зголошение użytkownika).
 * Тап по строке открывает сохранённый PDF в системном просмотрщике; если
 * подходящее приложение не найдено — показываем путь к папке текстом.
 * Кнопка "✕" на строке удаляет ошибочно выставленный счёт/корректировку
 * (запись из БД и сохранённый PDF-файл) после подтверждения.
 *
 * Поддерживает поиск (номер документа, имя клиента, NIP, сумма) и фильтр
 * по диапазону дат выдачи — оба работают динамически поверх уже
 * загруженного списка, без повторных запросов к БД. Фильтр по статусу
 * (Zapłacona/Oczekuje) применяется только к фактурам — у korekt нет статуса
 * оплаты, поэтому они видны только на вкладке "Wszystkie".
 */
class InvoiceHistoryActivity : BaseActivity() {

    private lateinit var adapter: InvoiceAdapter
    private val filterDateFmt = SimpleDateFormat("dd.MM.yy", Locale.getDefault())

    private var allInvoices: List<Invoice> = emptyList()
    private var allCorrections: List<InvoiceCorrection> = emptyList()
    private var searchQuery: String = ""
    private var filterFrom: Long? = null
    private var filterTo: Long? = null
    private var statusFilter: InvoiceStatus? = null

    private val searchHandler = Handler(Looper.getMainLooper())
    private var pendingFilter: Runnable? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_invoice_history)

        adapter = InvoiceAdapter(
            onItemClick = { invoice -> openInvoicePdf(invoice) },
            onCorrectionClick = { correction -> openCorrectionPdf(correction) },
            onDeleteClick = { invoice -> confirmDelete(invoice) },
            onDeleteCorrectionClick = { correction -> confirmDeleteCorrection(correction) },
            onMarkPaidClick = { invoice -> confirmMarkPaid(invoice) },
            onKorektaClick = { invoice ->
                startActivity(
                    Intent(this, AddInvoiceCorrectionActivity::class.java)
                        .putExtra(AddInvoiceCorrectionActivity.EXTRA_INVOICE_ID, invoice.id)
                )
            }
        )
        findViewById<RecyclerView>(R.id.rv_invoices).apply {
            layoutManager = LinearLayoutManager(this@InvoiceHistoryActivity)
            adapter = this@InvoiceHistoryActivity.adapter
        }

        setupSearchAndFilters()
        loadData()
    }

    override fun onResume() {
        super.onResume()
        // Список могут пополнить новой записью, вернувшись с экрана выставления счёта.
        // Текущий поиск/фильтр сохраняется.
        loadData()
    }

    private fun setupSearchAndFilters() {
        val etSearch = findViewById<EditText>(R.id.et_search)
        val btnClearSearch = findViewById<TextView>(R.id.btn_clear_search)
        val btnFilterDate = findViewById<Button>(R.id.btn_filter_date)
        val btnFilterClear = findViewById<Button>(R.id.btn_filter_clear)

        etSearch.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                searchQuery = s?.toString()?.trim().orEmpty()
                btnClearSearch.visibility = if (searchQuery.isEmpty()) View.GONE else View.VISIBLE
                updateClearFiltersVisibility()
                scheduleFilter()
            }
        })

        btnClearSearch.setOnClickListener { etSearch.setText("") }

        btnFilterDate.setOnClickListener { showDateRangePicker() }

        btnFilterClear.setOnClickListener {
            filterFrom = null
            filterTo = null
            btnFilterDate.text = getString(R.string.filter_date_range)
            etSearch.setText("")
            updateClearFiltersVisibility()
            applyFilters()
        }

        findViewById<Button>(R.id.btn_status_all).setOnClickListener { setStatusFilter(null) }
        findViewById<Button>(R.id.btn_status_paid).setOnClickListener { setStatusFilter(InvoiceStatus.PAID) }
        findViewById<Button>(R.id.btn_status_pending).setOnClickListener { setStatusFilter(InvoiceStatus.PENDING) }
        applyStatusFilterUi()
    }

    private fun setStatusFilter(status: InvoiceStatus?) {
        statusFilter = status
        applyStatusFilterUi()
        applyFilters()
    }

    /** Явно выделяем активный фильтр статуса — тот же приём, что и для способа оплаты на экране выставления счёта. */
    private fun applyStatusFilterUi() {
        val all = findViewById<Button>(R.id.btn_status_all)
        val paid = findViewById<Button>(R.id.btn_status_paid)
        val pending = findViewById<Button>(R.id.btn_status_pending)
        for ((button, selected) in listOf(
            all to (statusFilter == null),
            paid to (statusFilter == InvoiceStatus.PAID),
            pending to (statusFilter == InvoiceStatus.PENDING)
        )) {
            button.setBackgroundResource(if (selected) R.drawable.btn_pill_payment_selected else R.drawable.btn_pill_payment_unselected)
            button.setTextColor(resources.getColor(if (selected) R.color.text_primary else R.color.text_secondary, theme))
        }
    }

    /** Небольшой дебаунс — фильтрация не запускается на каждый символ, а через 250 мс после паузы в наборе. */
    private fun scheduleFilter() {
        pendingFilter?.let { searchHandler.removeCallbacks(it) }
        val r = Runnable { applyFilters() }
        pendingFilter = r
        searchHandler.postDelayed(r, 250)
    }

    private fun showDateRangePicker() {
        val cal = Calendar.getInstance()
        DatePickerDialog(
            this,
            { _, fromYear, fromMonth, fromDay ->
                val fromCal = Calendar.getInstance()
                fromCal.set(fromYear, fromMonth, fromDay, 0, 0, 0)
                fromCal.set(Calendar.MILLISECOND, 0)
                val fromMillis = fromCal.timeInMillis

                DatePickerDialog(
                    this,
                    { _, toYear, toMonth, toDay ->
                        val toCal = Calendar.getInstance()
                        toCal.set(toYear, toMonth, toDay, 23, 59, 59)
                        toCal.set(Calendar.MILLISECOND, 999)
                        val toMillis = toCal.timeInMillis

                        if (toMillis < fromMillis) {
                            Toast.makeText(this, getString(R.string.custom_range_invalid), Toast.LENGTH_LONG).show()
                            return@DatePickerDialog
                        }

                        filterFrom = fromMillis
                        filterTo = toMillis
                        findViewById<Button>(R.id.btn_filter_date).text =
                            "${filterDateFmt.format(Date(fromMillis))}–${filterDateFmt.format(Date(toMillis))}"
                        updateClearFiltersVisibility()
                        applyFilters()
                    },
                    cal.get(Calendar.YEAR), cal.get(Calendar.MONTH), cal.get(Calendar.DAY_OF_MONTH)
                ).apply { setTitle(getString(R.string.to)) }.show()
            },
            cal.get(Calendar.YEAR), cal.get(Calendar.MONTH), cal.get(Calendar.DAY_OF_MONTH)
        ).apply { setTitle(getString(R.string.from)) }.show()
    }

    private fun updateClearFiltersVisibility() {
        findViewById<Button>(R.id.btn_filter_clear).visibility =
            if (filterFrom != null || searchQuery.isNotEmpty()) View.VISIBLE else View.GONE
    }

    private fun loadData() {
        CoroutineScope(Dispatchers.IO).launch {
            val db = AppDatabase.getInstance(applicationContext)
            allInvoices = db.invoiceDao().getAll()
            allCorrections = db.invoiceCorrectionDao().getAll()
            withContext(Dispatchers.Main) { applyFilters() }
        }
    }

    /**
     * Применяет текущий поисковый запрос (номер, клиент, NIP, сумма/дельта) и
     * фильтр по датам выдачи к ОБОИМ спискам — фактурам и корректировкам —
     * и сливает их в единую хронологическую ленту (сортировка по issueDateMillis
     * по убыванию, самые новые документы сверху). Фильтрация выполняется в
     * фоновом потоке (Dispatchers.Default), что остаётся быстрым даже при
     * большом числе выставленных документов.
     */
    private fun applyFilters() {
        val query = searchQuery
        val from = filterFrom
        val to = filterTo
        val status = statusFilter
        val invoiceSource = allInvoices
        val correctionSource = allCorrections

        CoroutineScope(Dispatchers.Default).launch {
            val filteredInvoices = invoiceSource.filter { inv ->
                val inRange = (from == null || inv.issueDateMillis >= from) &&
                        (to == null || inv.issueDateMillis <= to)
                if (!inRange) return@filter false
                if (status != null && inv.status != status) return@filter false
                if (query.isEmpty()) return@filter true

                val amountStr = String.format(Locale.getDefault(), "%.2f", inv.amount)
                inv.invoiceNumber.toString().contains(query, ignoreCase = true) ||
                        inv.buyerName.contains(query, ignoreCase = true) ||
                        (inv.buyerNip?.contains(query, ignoreCase = true) == true) ||
                        inv.serviceName.contains(query, ignoreCase = true) ||
                        amountStr.contains(query, ignoreCase = true)
            }

            // Korekty nie mają statusu płatności — pokazujemy je tylko, gdy nie jest
            // aktywny filtr Zapłacona/Oczekuje (czyli na zakładce "Wszystkie").
            val invoiceNumberById = invoiceSource.associate { it.id to it.invoiceNumber }
            val filteredCorrections = if (status != null) emptyList() else correctionSource.filter { cor ->
                val inRange = (from == null || cor.issueDateMillis >= from) &&
                        (to == null || cor.issueDateMillis <= to)
                if (!inRange) return@filter false
                if (query.isEmpty()) return@filter true

                val originalNumber = if (cor.originalInvoiceNumber > 0) cor.originalInvoiceNumber
                    else invoiceNumberById[cor.originalInvoiceId]
                val deltaStr = String.format(Locale.getDefault(), "%.2f", cor.deltaAmount)
                cor.correctionNumber.toString().contains(query, ignoreCase = true) ||
                        (originalNumber != null && originalNumber.toString().contains(query, ignoreCase = true)) ||
                        cor.reason.contains(query, ignoreCase = true) ||
                        deltaStr.contains(query, ignoreCase = true)
            }

            val merged: List<InvoiceHistoryItem> = filteredInvoices.map { InvoiceHistoryItem.InvoiceRow(it) } +
                filteredCorrections.map { cor ->
                    val originalNumber = if (cor.originalInvoiceNumber > 0) cor.originalInvoiceNumber
                        else invoiceNumberById[cor.originalInvoiceId]
                    InvoiceHistoryItem.CorrectionRow(cor, originalNumber)
                }
            val sorted = merged.sortedByDescending { it.issueDateMillis }

            withContext(Dispatchers.Main) {
                adapter.submitList(sorted)
                val tvNoInvoices = findViewById<TextView>(R.id.tv_no_invoices)
                if (sorted.isEmpty()) {
                    tvNoInvoices.visibility = View.VISIBLE
                    tvNoInvoices.text = if (allInvoices.isEmpty() && allCorrections.isEmpty())
                        getString(R.string.no_invoices) else getString(R.string.search_no_results)
                } else {
                    tvNoInvoices.visibility = View.GONE
                }
            }
        }
    }

    private fun openCorrectionPdf(correction: InvoiceCorrection) {
        val opened = InvoiceFileStorage.openPdfSafely(this, correction.pdfFilePath)
        if (!opened) {
            Toast.makeText(this, getString(R.string.open_folder_error, InvoiceFileStorage.displayFolderPath), Toast.LENGTH_LONG).show()
        }
    }

    /** Удаляет запись korekty и её PDF-файл. Обратите внимание: если korekta была
     *  применена к доходу (appliedToIncome), созданная Entry НЕ откатывается
     *  автоматически — так же, как удаление обычной фактуры не откатывает Entry,
     *  созданную при её выставлении (см. [confirmDelete]); при необходимости
     *  соответствующий приход нужно удалить вручную на экране Historii/главном. */
    private fun confirmDeleteCorrection(correction: InvoiceCorrection) {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.delete_correction_confirm_title))
            .setMessage(getString(R.string.delete_correction_confirm_message))
            .setPositiveButton(getString(R.string.delete_confirm_yes)) { _, _ ->
                CoroutineScope(Dispatchers.IO).launch {
                    InvoiceFileStorage.deleteFile(applicationContext, correction.pdfFilePath)
                    AppDatabase.getInstance(applicationContext).invoiceCorrectionDao().delete(correction)
                    withContext(Dispatchers.Main) {
                        Toast.makeText(this@InvoiceHistoryActivity, getString(R.string.correction_deleted), Toast.LENGTH_SHORT).show()
                        loadData()
                    }
                }
            }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
    }

    private fun openInvoicePdf(invoice: Invoice) {
        // openPdfSafely сам ловит и ActivityNotFoundException, и SecurityException
        // (известная проблема на части устройств с MediaStore-URI — раньше это
        // приводило к падению всего приложения при тапе по фактуре) и делает
        // одну попытку через локальную копию файла, прежде чем сдаться.
        val opened = InvoiceFileStorage.openPdfSafely(this, invoice.pdfFilePath)
        if (!opened) {
            Toast.makeText(this, getString(R.string.open_folder_error, InvoiceFileStorage.displayFolderPath), Toast.LENGTH_LONG).show()
        }
    }

    /** Меняет статус на "оплачено" (сегодняшней датой) прямо из истории и
     *  перезаписывает уже сохранённый PDF-файл, чтобы он отражал новый статус —
     *  иначе документ продолжал бы показывать старую пометку "ожидает оплаты". */
    private fun confirmMarkPaid(invoice: Invoice) {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.invoice_mark_paid_confirm_title))
            .setMessage(getString(R.string.invoice_mark_paid_confirm_message))
            .setPositiveButton(getString(R.string.delete_confirm_yes)) { _, _ ->
                CoroutineScope(Dispatchers.IO).launch {
                    val paidInvoice = invoice.copy(status = InvoiceStatus.PAID, paymentDateMillis = System.currentTimeMillis(), dueDateMillis = null)
                    AppDatabase.getInstance(applicationContext).invoiceDao().update(paidInvoice)
                    val items = AppDatabase.getInstance(applicationContext).invoiceItemDao().getForInvoice(invoice.id)
                    val regenerated = try {
                        InvoiceFileStorage.overwritePdf(applicationContext, invoice.pdfFilePath) { out ->
                            InvoicePdfGenerator.generate(
                                context = this@InvoiceHistoryActivity,
                                seller = InvoiceSellerDataStore.load(applicationContext),
                                invoiceNumber = paidInvoice.invoiceNumber,
                                issueDateMillis = paidInvoice.issueDateMillis,
                                paymentDateMillis = paidInvoice.paymentDateMillis,
                                serviceDateMillis = paidInvoice.serviceDateMillis,
                                isPhysicalPerson = paidInvoice.isPhysicalPerson,
                                buyerName = paidInvoice.buyerName,
                                buyerNip = paidInvoice.buyerNip,
                                buyerStreet = paidInvoice.buyerStreet,
                                buyerPostalCode = paidInvoice.buyerPostalCode,
                                buyerCity = paidInvoice.buyerCity,
                                serviceName = paidInvoice.serviceName,
                                amount = paidInvoice.amount,
                                paymentMethod = paidInvoice.paymentMethod,
                                invoiceStatus = InvoiceStatus.PAID,
                                dueDateMillis = null,
                                items = items,
                                out = out
                            )
                        }
                    } catch (e: Exception) {
                        false
                    }
                    withContext(Dispatchers.Main) {
                        Toast.makeText(
                            this@InvoiceHistoryActivity,
                            getString(if (regenerated) R.string.invoice_marked_paid_toast else R.string.invoice_marked_paid_pdf_warning),
                            Toast.LENGTH_SHORT
                        ).show()
                        loadData()
                    }
                }
            }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
    }

    private fun confirmDelete(invoice: Invoice) {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.delete_invoice_confirm_title))
            .setMessage(getString(R.string.delete_invoice_confirm_message))
            .setPositiveButton(getString(R.string.delete_confirm_yes)) { _, _ ->
                CoroutineScope(Dispatchers.IO).launch {
                    InvoiceFileStorage.deleteFile(applicationContext, invoice.pdfFilePath)
                    AppDatabase.getInstance(applicationContext).invoiceDao().delete(invoice)
                    withContext(Dispatchers.Main) {
                        Toast.makeText(this@InvoiceHistoryActivity, getString(R.string.invoice_deleted), Toast.LENGTH_SHORT).show()
                        loadData()
                    }
                }
            }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
    }
}


FAEOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEHISTORYACTIVITY_KT

echo "-> app/src/main/res/values/strings.xml"
mkdir -p "$(dirname 'app/src/main/res/values/strings.xml')"
cat > 'app/src/main/res/values/strings.xml' << 'FAEOF_APP_SRC_MAIN_RES_VALUES_STRINGS_XML'
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
    <string name="limit_bracket_label_tax_free">Tax-free amount (0–30,000 zł/year): %1$s / %2$s zł</string>
    <string name="limit_bracket_label_rate12">12%% bracket (30,000–120,000 zł/year): %1$s / %2$s zł</string>
    <string name="limit_bracket_label_rate32">120,000 zł threshold exceeded — surplus of %1$s zł taxed at 32%%</string>
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
    <string name="invoice_is_receipt_label">This invoice is issued for a receipt (paragon)</string>
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
    <string name="invoice_pdf_table_price_netto">Net price</string>
    <string name="invoice_pdf_table_netto">Net value</string>
    <string name="invoice_pdf_table_vat_rate">VAT rate</string>
    <string name="invoice_pdf_table_vat_amount">VAT amount</string>
    <string name="invoice_pdf_table_brutto">Gross value</string>
    <string name="invoice_pdf_receipt_label">Invoice issued for the fiscal receipt (paragon)</string>
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
    <string name="kasa_compliance_hint_registered">Your business is registered (JDG), so you may already have a fiscal cash register from the start. If you do, confirm it below — this unlocks the \"issued for a receipt\" option when filling out invoices.</string>
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

    <!-- Update: teksty prawne na dokumencie PDF (faktura/rachunek) — CELOWO tylko
         w tym pliku (bez odpowiedników w values-pl/values-ru), bo to formalna treść
         z polskiej ustawy o VAT i musi zostać po polsku na dokumencie niezależnie od
         języka interfejsu aplikacji (patrz InvoicePdfGenerator.kt). -->
    <string name="invoice_pdf_seller_nierejestrowana_note">Osoba fizyczna prowadząca działalność nierejestrowaną (bez NIP).</string>
    <string name="invoice_pdf_legal_basis_title">Podstawa prawna zwolnienia z VAT:</string>
    <string name="invoice_pdf_legal_basis_text">Sprzedawca zwolniony z podatku od towarów i usług na podstawie art. 113 ust. 1 (lub ust. 9) ustawy o VAT.</string>

    <!-- Update: moduł Korekta (Faktura korygująca) -->
    <string name="invoice_history_korekta_button">↺</string>
    <string name="correction_title">Correction invoice</string>
    <string name="correction_original_invoice_label">Original document: #%1$d, %2$s</string>
    <string name="correction_original_amount_label">Original amount</string>
    <string name="correction_corrected_amount_hint">Corrected amount (zł)</string>
    <string name="correction_reason_hint">Reason for the correction</string>
    <string name="correction_apply_to_income_label">Apply the difference to income (Przychód)</string>
    <string name="correction_save_button">Issue correction</string>
    <string name="correction_zero_delta_error">The corrected amount is the same as the original — nothing to correct</string>
    <string name="correction_reason_required_error">Please enter the reason for the correction</string>
    <string name="correction_saved_toast">Correction invoice issued</string>
    <string name="correction_pdf_title">CORRECTION INVOICE</string>
    <string name="correction_pdf_to_invoice">Correction to invoice</string>
    <string name="correction_pdf_reason_label">Reason for the correction</string>
    <string name="correction_pdf_before_label">Amount before correction</string>
    <string name="correction_pdf_after_label">Amount after correction</string>
    <string name="correction_pdf_delta_label">Difference</string>
    <!-- Update: items table on the correction PDF + signature fields on both PDFs -->
    <string name="correction_pdf_before_table_title">Before correction</string>
    <string name="correction_pdf_after_table_title">After correction</string>
    <string name="invoice_pdf_signature_issued_by">Issued by:</string>
    <string name="invoice_pdf_signature_received_by">Received by:</string>
    <string name="invoice_pdf_signature_issued_by_caption">Signature of the person authorized to issue</string>
    <string name="invoice_pdf_signature_received_by_caption">Signature of the person authorized to receive</string>
    <!-- Update: corrections now also appear in Historia faktur (Invoice history) -->
    <string name="correction_history_row_title">Correction #%1$d → invoice #%2$d</string>
    <string name="correction_history_row_title_solo">Correction #%1$d</string>
    <string name="delete_correction_confirm_title">Delete correction?</string>
    <string name="delete_correction_confirm_message">The correction record and its PDF file will be permanently deleted. This cannot be undone. The income entry created by this correction (if any) will not be reverted automatically.</string>
    <string name="correction_deleted">Correction deleted</string>
</resources>

FAEOF_APP_SRC_MAIN_RES_VALUES_STRINGS_XML

echo "-> app/src/main/res/values-pl/strings.xml"
mkdir -p "$(dirname 'app/src/main/res/values-pl/strings.xml')"
cat > 'app/src/main/res/values-pl/strings.xml' << 'FAEOF_APP_SRC_MAIN_RES_VALUES_PL_STRINGS_XML'
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
    <string name="limit_bracket_label_tax_free">Kwota wolna od podatku (0–30 000 zł/rok): %1$s / %2$s zł</string>
    <string name="limit_bracket_label_rate12">Próg 12%% (30 000–120 000 zł/rok): %1$s / %2$s zł</string>
    <string name="limit_bracket_label_rate32">Próg 120 000 zł przekroczony — nadwyżka %1$s zł opodatkowana stawką 32%%</string>
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
    <string name="invoice_is_receipt_label">Faktura jest wystawiana do paragonu</string>
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
    <string name="invoice_pdf_table_price_netto">Cena netto</string>
    <string name="invoice_pdf_table_netto">Wartość netto</string>
    <string name="invoice_pdf_table_vat_rate">Stawka VAT</string>
    <string name="invoice_pdf_table_vat_amount">Kwota VAT</string>
    <string name="invoice_pdf_table_brutto">Wartość brutto</string>
    <string name="invoice_pdf_receipt_label">Faktura wystawiona do paragonu fiskalnego</string>
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
    <string name="kasa_compliance_hint_registered">Twoja działalność jest zarejestrowana (JDG), więc mogłeś/aś posiadać kasę fiskalną już od początku. Jeśli tak, potwierdź to poniżej — odblokuje to opcję „wydana do paragonu\" przy wystawianiu faktur.</string>
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

    <!-- Update: moduł Korekta (Faktura korygująca) -->
    <string name="invoice_history_korekta_button">↺</string>
    <string name="correction_title">Faktura korygująca</string>
    <string name="correction_original_invoice_label">Dokument oryginalny: nr %1$d, %2$s</string>
    <string name="correction_original_amount_label">Kwota oryginalna</string>
    <string name="correction_corrected_amount_hint">Kwota po korekcie (zł)</string>
    <string name="correction_reason_hint">Przyczyna korekty</string>
    <string name="correction_apply_to_income_label">Zastosuj różnicę do przychodu</string>
    <string name="correction_save_button">Wystaw korektę</string>
    <string name="correction_zero_delta_error">Kwota po korekcie jest taka sama jak oryginalna — nie ma czego korygować</string>
    <string name="correction_reason_required_error">Podaj przyczynę korekty</string>
    <string name="correction_saved_toast">Faktura korygująca wystawiona</string>
    <string name="correction_pdf_title">FAKTURA KORYGUJĄCA</string>
    <string name="correction_pdf_to_invoice">Korekta do faktury</string>
    <string name="correction_pdf_reason_label">Przyczyna korekty</string>
    <string name="correction_pdf_before_label">Kwota przed korektą</string>
    <string name="correction_pdf_after_label">Kwota po korekcie</string>
    <string name="correction_pdf_delta_label">Różnica</string>
    <!-- Update: tabela pozycji na fakturze korygującej + pola podpisu na obu dokumentach -->
    <string name="correction_pdf_before_table_title">Przed korektą</string>
    <string name="correction_pdf_after_table_title">Po korekcie</string>
    <string name="invoice_pdf_signature_issued_by">Wystawił(a):</string>
    <string name="invoice_pdf_signature_received_by">Odebrał(a):</string>
    <string name="invoice_pdf_signature_issued_by_caption">Podpis osoby upoważnionej do wystawienia</string>
    <string name="invoice_pdf_signature_received_by_caption">Podpis osoby upoważnionej do odbioru</string>
    <!-- Update: korekty pojawiają się teraz też w Historii faktur -->
    <string name="correction_history_row_title">Korekta nr %1$d → faktura nr %2$d</string>
    <string name="correction_history_row_title_solo">Korekta nr %1$d</string>
    <string name="delete_correction_confirm_title">Usunąć korektę?</string>
    <string name="delete_correction_confirm_message">Rekord korekty i jej plik PDF zostaną trwale usunięte. Tej operacji nie można cofnąć. Wpis przychodu utworzony przez tę korektę (jeśli był) nie zostanie automatycznie cofnięty.</string>
    <string name="correction_deleted">Korekta usunięta</string>
</resources>

FAEOF_APP_SRC_MAIN_RES_VALUES_PL_STRINGS_XML

echo "-> app/src/main/res/values-ru/strings.xml"
mkdir -p "$(dirname 'app/src/main/res/values-ru/strings.xml')"
cat > 'app/src/main/res/values-ru/strings.xml' << 'FAEOF_APP_SRC_MAIN_RES_VALUES_RU_STRINGS_XML'
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
    <string name="limit_bracket_label_tax_free">Необлагаемый минимум (0–30 000 zł/год): %1$s / %2$s zł</string>
    <string name="limit_bracket_label_rate12">Порог 12%% (30 000–120 000 zł/год): %1$s / %2$s zł</string>
    <string name="limit_bracket_label_rate32">Порог 120 000 zł превышен — излишек %1$s zł облагается по ставке 32%%</string>
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
    <string name="invoice_is_receipt_label">Фактура выставляется к чеку (paragon)</string>
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
    <string name="invoice_pdf_table_price_netto">Цена нетто</string>
    <string name="invoice_pdf_table_netto">Стоимость нетто</string>
    <string name="invoice_pdf_table_vat_rate">Ставка VAT</string>
    <string name="invoice_pdf_table_vat_amount">Сумма VAT</string>
    <string name="invoice_pdf_table_brutto">Стоимость брутто</string>
    <string name="invoice_pdf_receipt_label">Фактура выставлена к фискальному чеку</string>
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
    <string name="kasa_compliance_hint_registered">Ваша деятельность зарегистрирована (JDG), поэтому кассовый аппарат у вас мог быть уже с самого начала. Если это так, подтвердите это ниже — это откроет опцию «выдана к чеку» при заполнении фактур.</string>
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

    <!-- Update: модуль корректировок (Faktura korygująca) -->
    <string name="invoice_history_korekta_button">↺</string>
    <string name="correction_title">Корректировочный счёт</string>
    <string name="correction_original_invoice_label">Исходный документ: №%1$d, %2$s</string>
    <string name="correction_original_amount_label">Исходная сумма</string>
    <string name="correction_corrected_amount_hint">Сумма после корректировки (zł)</string>
    <string name="correction_reason_hint">Причина корректировки</string>
    <string name="correction_apply_to_income_label">Применить разницу к доходу (Przychód)</string>
    <string name="correction_save_button">Выставить корректировку</string>
    <string name="correction_zero_delta_error">Сумма после корректировки совпадает с исходной — нечего корректировать</string>
    <string name="correction_reason_required_error">Укажите причину корректировки</string>
    <string name="correction_saved_toast">Корректировочный счёт выставлен</string>
    <string name="correction_pdf_title">КОРРЕКТИРОВОЧНЫЙ СЧЁТ</string>
    <string name="correction_pdf_to_invoice">Корректировка к счёту</string>
    <string name="correction_pdf_reason_label">Причина корректировки</string>
    <string name="correction_pdf_before_label">Сумма до корректировки</string>
    <string name="correction_pdf_after_label">Сумма после корректировки</string>
    <string name="correction_pdf_delta_label">Разница</string>
    <!-- Update: таблица позиций в корректировочном счёте + поля подписи на обоих документах -->
    <string name="correction_pdf_before_table_title">До корректировки</string>
    <string name="correction_pdf_after_table_title">После корректировки</string>
    <string name="invoice_pdf_signature_issued_by">Выставил(а):</string>
    <string name="invoice_pdf_signature_received_by">Получил(а):</string>
    <string name="invoice_pdf_signature_issued_by_caption">Подпись лица, уполномоченного на выставление</string>
    <string name="invoice_pdf_signature_received_by_caption">Подпись лица, уполномоченного на получение</string>
    <!-- Update: корректировки теперь тоже отображаются в Истории счетов -->
    <string name="correction_history_row_title">Корректировка №%1$d → счёт №%2$d</string>
    <string name="correction_history_row_title_solo">Корректировка №%1$d</string>
    <string name="delete_correction_confirm_title">Удалить корректировку?</string>
    <string name="delete_correction_confirm_message">Запись корректировки и её PDF-файл будут удалены безвозвратно. Действие нельзя отменить. Запись дохода, созданная этой корректировкой (если была), автоматически не отменяется.</string>
    <string name="correction_deleted">Корректировка удалена</string>
</resources>

FAEOF_APP_SRC_MAIN_RES_VALUES_RU_STRINGS_XML

echo ""
echo "=== Update 53 zastosowany ==="
echo "Co przetestowac przed budowa APK:"
echo " - Wystaw nowa fakture (dowolny typ dzialalnosci, takze"
echo "   'dzialalnosc nierejestrowana') i sprawdz, ze:"
echo "     * suma pojawia sie w Przychod / Bilans na glownym ekranie,"
echo "     * limit 'Dzialalnosc nierejestrowana, ten miesiac' rosnie,"
echo "     * wpis widac w liscie transakcji."
echo " - Wystaw korekte do tej faktury (zmien kwote) i sprawdz PDF:"
echo "     * dwie tabele 'Przed korekta' / 'Po korekcie' z pozycjami,"
echo "     * pola podpisu 'Wystawil(a)' / 'Odebral(a)' na dole,"
echo "     * Bilans po korekcie odzwierciedla NOWA (skorygowana) kwote,"
echo "       a nie tylko goly minus roznicy."
echo " - Otworz zwykla fakture (nie korekte) - powinna tez miec teraz"
echo "   pola podpisu na koncu PDF."
echo " - Wejdz w Historia faktur: korekta powinna byc widoczna w tej samej"
echo "   liscie co faktury (ikonka ↺, kwota = sama roznica, kolor"
echo "   zielony/czerwony), z dzialajacym szukaniem i usuwaniem (X)."
echo " - Jesli w bazie byly juz jakies korekty sprzed tej aktualizacji,"
echo "   po pierwszym uruchomieniu apki (migracja 10->11) powinny nadal"
echo "   byc widoczne w Historii z prawidlowym numerem oryginalnej faktury."
echo ""
echo "Dalej jak zwykle: git add -A && git commit -m 'update 53: invoice income fix + korekta table + signatures + history' && git push"
echo "Zbuduj APK przez GitHub Actions."
