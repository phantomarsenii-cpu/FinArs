package com.example.fa_ksiegowy

import android.os.Bundle
import android.text.InputType
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
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Update: экран выставления Faktura korygująca (корректировочной фактуры) к уже
 * выставленному документу. Открывается из InvoiceHistoryActivity по кнопке "↺"
 * на строке фактуры (см. InvoiceAdapter/item_invoice.xml), обязательный extra —
 * EXTRA_INVOICE_ID.
 *
 * Update 62: если у оригинальной фактуры больше 1 позиции — теперь можно выбрать
 * НЕСКОЛЬКО позиций сразу (btn_pick_items открывает AppDialog.showMultiCheckboxPicker —
 * то же самое оформление диалогов, что и во всём приложении, вместо стандартного
 * системного Spinner-попапа). Для каждой выбранной позиции показывается отдельное
 * поле "Kwota po korekcie" (см. rebuildSelectedItemsRows) — остальные, невыбранные
 * позиции остаются без изменений. Итоговая скорректированная сумма считается как
 * originalInvoice.amount минус сумма старых значений выбранных позиций плюс сумма
 * новых значений. Раньше можно было скорректировать только ОДНУ позицию за раз —
 * для нескольких позиций пользователю приходилось выставлять отдельную корректу на
 * каждую, что было неверно (одна корректировка должна покрывать все изменения сразу).
 * Для фактур с 0-1 позицией поведение не изменилось (корректировка всей суммы одним
 * полем et_corrected_amount).
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
    private var originalItems: List<InvoiceItem> = emptyList()

    // Update 62: индексы (в originalItems) выбранных для корректировки позиций,
    // в порядке выбора; для каждой — уже введённое/предзаполненное значение "Kwota
    // po korekcie", сохраняется при переоткрытии диалога выбора, чтобы не сбрасывать
    // то, что пользователь уже ввёл.
    private val selectedItemIndices = LinkedHashSet<Int>()
    private val itemPendingValues = LinkedHashMap<Int, Double>()
    private val itemAmountFields = LinkedHashMap<Int, EditText>()

    private val moneyFmt = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_add_invoice_correction)
        findViewById<android.view.View>(R.id.iv_back).setOnClickListener { finish() }

        val invoiceId = intent.getLongExtra(EXTRA_INVOICE_ID, -1L)
        if (invoiceId < 0) {
            finish()
            return
        }

        CoroutineScope(Dispatchers.IO).launch {
            val db = AppDatabase.getInstance(applicationContext)
            val invoice = db.invoiceDao().getById(invoiceId)
            val items = if (invoice != null) db.invoiceItemDao().getForInvoice(invoice.id) else emptyList()
            withContext(Dispatchers.Main) {
                if (invoice == null) {
                    finish()
                    return@withContext
                }
                originalInvoice = invoice
                originalItems = items
                bindOriginalInvoiceInfo()
                setupItemPicker()
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

    /** Update 62: pokazuje wybór WIELU pozycji do korekty tylko gdy oryginalna faktura
     *  ma >1 pozycję — dla 0-1 pozycji zachowanie zostaje dokładnie takie jak wcześniej
     *  (pojedyncze pole et_corrected_amount dla całej faktury). */
    private fun setupItemPicker() {
        if (originalItems.size <= 1) return

        findViewById<LinearLayout>(R.id.ll_item_picker).visibility = android.view.View.VISIBLE
        // W trybie wielu pozycji kwota "całej faktury" nie ma zastosowania — liczy się
        // z sumy pól per-pozycja (patrz rebuildSelectedItemsRows/saveCorrection).
        findViewById<TextView>(R.id.tv_corrected_amount_label).visibility = android.view.View.GONE
        findViewById<EditText>(R.id.et_corrected_amount).visibility = android.view.View.GONE

        findViewById<Button>(R.id.btn_pick_items).setOnClickListener { openItemPickerDialog() }
        rebuildSelectedItemsRows()
    }

    /** Update 62: własny dialog w stylu aplikacji (AppDialog — ciemna karta, przyciski-
     *  pigułki), zamiast systemowego Spinnera, który otwierał standardowe, "czarne"
     *  okienko niepasujące do reszty interfejsu. Pozwala zaznaczyć checkboxami DOWOLNĄ
     *  liczbę pozycji naraz. */
    private fun openItemPickerDialog() {
        val options = originalItems.mapIndexed { index, item ->
            val value = item.quantity * item.unitPrice
            index to "${item.name} — ${String.format(Locale.getDefault(), "%.2f", value)} zł"
        }
        AppDialog.showMultiCheckboxPicker(
            context = this,
            title = getString(R.string.correction_pick_items_dialog_title),
            options = options,
            preselected = selectedItemIndices,
            confirmText = getString(R.string.correction_pick_items_confirm),
            cancelText = getString(R.string.confirm_cancel)
        ) { chosen ->
            // Zachowujemy już wpisane kwoty dla pozycji, które nadal są zaznaczone;
            // dla nowo zaznaczonych pozycji podpowiadamy oryginalną wartość.
            selectedItemIndices.clear()
            for (idx in originalItems.indices) {
                if (chosen.contains(idx)) selectedItemIndices.add(idx)
            }
            itemPendingValues.keys.retainAll(selectedItemIndices)
            rebuildSelectedItemsRows()
        }
    }

    /** Update 62: buduje dynamicznie po jednym polu "Kwota po korekcie" dla każdej
     *  zaznaczonej pozycji wewnątrz ll_selected_items_amounts. */
    private fun rebuildSelectedItemsRows() {
        val container = findViewById<LinearLayout>(R.id.ll_selected_items_amounts)
        container.removeAllViews()
        itemAmountFields.clear()

        val emptyHint = findViewById<TextView>(R.id.tv_no_items_selected)
        emptyHint.visibility = if (selectedItemIndices.isEmpty()) android.view.View.VISIBLE else android.view.View.GONE

        val density = resources.displayMetrics.density
        for (idx in selectedItemIndices) {
            val item = originalItems.getOrNull(idx) ?: continue
            val oldValue = item.quantity * item.unitPrice

            val row = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                lp.topMargin = (14 * density).toInt()
                layoutParams = lp
            }

            val label = TextView(this).apply {
                text = "${item.name} · ${getString(R.string.correction_original_amount_label)}: " +
                    "${String.format(Locale.getDefault(), "%.2f", oldValue)} zł"
                textSize = 13f
                setTextColor(resources.getColor(R.color.text_secondary, theme))
            }
            row.addView(label)

            val amountField = EditText(this).apply {
                setText(String.format(Locale.US, "%.2f", itemPendingValues[idx] ?: oldValue))
                inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL
                setTextColor(resources.getColor(R.color.text_primary, theme))
                setBackgroundResource(R.drawable.input_field_bg)
                val padH = (18 * density).toInt()
                setPadding(padH, 0, padH, 0)
                val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, (52 * density).toInt())
                lp.topMargin = (6 * density).toInt()
                layoutParams = lp
            }
            row.addView(amountField)

            container.addView(row)
            itemAmountFields[idx] = amountField
        }
    }

    private fun saveCorrection() {
        val reason = findViewById<EditText>(R.id.et_reason).text.toString().trim()
        if (reason.isBlank()) {
            Toast.makeText(this, getString(R.string.correction_reason_required_error), Toast.LENGTH_SHORT).show()
            return
        }

        // Update 62: w trybie "wiele pozycji" (>1 pozycji na oryginalnej fakturze) każda
        // zaznaczona pozycja ma własną wpisaną kwotę — całkowita skorygowana kwota
        // faktury to originalInvoice.amount pomniejszone o sumę starych wartości
        // zaznaczonych pozycji i powiększone o sumę nowo wpisanych. Pozostałe pozycje
        // (niezaznaczone) zostają bez zmian.
        val correctedItems = LinkedHashMap<Int, Double>()
        val corrected: Double

        if (originalItems.size > 1) {
            if (selectedItemIndices.isEmpty()) {
                Toast.makeText(this, getString(R.string.correction_no_items_selected_error), Toast.LENGTH_SHORT).show()
                return
            }
            var sumOld = 0.0
            var sumNew = 0.0
            for (idx in selectedItemIndices) {
                val field = itemAmountFields[idx] ?: continue
                val text = field.text.toString().replace(",", ".").trim()
                val value = text.toDoubleOrNull()
                if (value == null) {
                    Toast.makeText(this, getString(R.string.enter_amount), Toast.LENGTH_SHORT).show()
                    return
                }
                itemPendingValues[idx] = value
                val oldValue = originalItems[idx].quantity * originalItems[idx].unitPrice
                sumOld += oldValue
                sumNew += value
                correctedItems[idx] = value
            }
            corrected = originalInvoice.amount - sumOld + sumNew
        } else {
            val correctedText = findViewById<EditText>(R.id.et_corrected_amount).text.toString().replace(",", ".").trim()
            val enteredValue = correctedText.toDoubleOrNull()
            if (enteredValue == null) {
                Toast.makeText(this, getString(R.string.enter_amount), Toast.LENGTH_SHORT).show()
                return
            }
            corrected = enteredValue
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
            val originalVatRate = VatRate.fromStorageKeyOrNull(originalInvoice.vatRate)

            val pdfBytes = withContext(Dispatchers.Main) {
                InvoiceHtmlPdfGenerator.generateCorrection(
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
                    correctedItems = correctedItems
                )
            }
            val saved = InvoiceFileStorage.savePdf(applicationContext, fileName) { out ->
                out.write(pdfBytes)
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
