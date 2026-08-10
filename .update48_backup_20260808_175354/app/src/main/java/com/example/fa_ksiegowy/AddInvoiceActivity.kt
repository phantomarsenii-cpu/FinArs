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

        loadSellerData()
        refreshCashLimit()
        applyBusinessKindUi()
    }

    override fun onResume() {
        super.onResume()
        // Настройка "Тип продаж" в Ustawieniach могла измениться, пока пользователь
        // был на другом экране — перепроверяем при каждом возврате.
        applyBusinessKindUi()
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
