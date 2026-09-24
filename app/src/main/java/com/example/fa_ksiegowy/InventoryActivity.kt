package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.os.Bundle
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.LayoutInflater
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Инвентаризация склада: пользователь может в любой момент открыть этот экран,
 * пройтись по товарам и вписать фактически посчитанное количество — вручную
 * или сканируя штрихкод каждого товара. При сканировании открывается небольшой
 * стилизованный диалог в стиле приложения (см. AppDialog), в котором сразу можно
 * вписать фактическое количество найденного по штрихкоду товара (поле
 * предзаполнено следующим значением, чтобы штучный товар можно было просто
 * подтверждать сканами подряд, а при необходимости — стереть и вписать точное
 * число). При сохранении:
 *  - остаток на складе обновляется до введённого значения;
 *  - по каждой позиции с расхождением создаётся запись в истории
 *    (InventoryRecord), привязанная к сессии инвентаризации (InventorySession);
 *  - формируется красиво оформленный PDF-отчёт (было/стало/разница/разница в
 *    деньгах) и сохраняется в Documents/FinArs/Inventory — открыть его позже
 *    можно через "Historia inwentaryzacji".
 */
class InventoryActivity : BaseActivity() {
    private var products: List<Product> = emptyList()
    // productId -> введённое пользователем фактическое количество. Заполняется
    // текущим остатком при отрисовке строки, дальше обновляется по мере ввода.
    private val counted = mutableMapOf<Long, Double>()
    // productId -> поле ввода этой строки, чтобы сканирование штрихкода могло
    // обновить нужное поле программно (а не только через ручной ввод).
    private val etByProductId = mutableMapOf<Long, EditText>()

    private val scanLauncher = registerForActivityResult(ScanContract()) { result ->
        val barcode = result.contents
        if (barcode != null) handleScannedBarcode(barcode)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_inventory)
        findViewById<android.view.View>(R.id.iv_back).setOnClickListener { finish() }
        findViewById<Button>(R.id.btn_save_inventory).setOnClickListener { saveInventory() }
        findViewById<Button>(R.id.btn_inventory_history).setOnClickListener {
            startActivity(android.content.Intent(this, InventoryHistoryActivity::class.java))
        }
        findViewById<Button>(R.id.btn_scan_inventory).setOnClickListener {
            scanLauncher.launch(
                ScanOptions()
                    .setDesiredBarcodeFormats(ScanOptions.ALL_CODE_TYPES)
                    .setPrompt(getString(R.string.scan_barcode_prompt))
                    .setBeepEnabled(true)
                    .setOrientationLocked(false)
            )
        }
        findViewById<Button>(R.id.btn_manual_inventory).setOnClickListener {
            showManualFindDialog()
        }
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
        etByProductId.clear()
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
            etByProductId[p.id] = etCounted
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

    /** Штрихкод отсканирован во время инвентаризации: если товар с таким кодом
     *  есть на складе — открываем диалог ввода фактического количества именно
     *  этого товара; если товар не найден — сообщаем об этом, ничего не меняя. */
    private fun handleScannedBarcode(barcode: String) {
        CoroutineScope(Dispatchers.IO).launch {
            val product = AppDatabase.getInstance(applicationContext).productDao().getByBarcode(barcode)
            withContext(Dispatchers.Main) {
                if (product == null) {
                    Toast.makeText(this@InventoryActivity, getString(R.string.inventory_scan_not_found, barcode), Toast.LENGTH_LONG).show()
                    return@withContext
                }
                val et = etByProductId[product.id]
                if (et == null) {
                    Toast.makeText(this@InventoryActivity, getString(R.string.inventory_scan_not_found, barcode), Toast.LENGTH_LONG).show()
                    return@withContext
                }
                showScanQuantityDialog(product, et)
            }
        }
    }

    /** Ручной поиск товара для инвентаризации — на случай, если штрихкод сменился
     *  у производителя (или его просто нет/он не читается) и сканирование не находит
     *  нужную позицию. Открывает диалог с полем поиска: список товаров склада живо
     *  фильтруется по названию, штрихкоду или единице измерения по мере ввода.
     *  Выбор строки открывает тот же диалог ввода количества, что и при сканировании
     *  (см. showScanQuantityDialog), но БЕЗ авто-инкремента +1 — при ручном поиске
     *  пользователь обычно сразу вписывает точное посчитанное число. */
    private fun showManualFindDialog() {
        val density = resources.displayMetrics.density

        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }

        val searchInput = EditText(this).apply {
            hint = getString(R.string.inventory_manual_search_hint)
            setHintTextColor(resources.getColor(R.color.text_hint, theme))
            setTextColor(resources.getColor(R.color.text_primary, theme))
            setBackgroundResource(R.drawable.input_field_bg)
            val pad = (14 * density).toInt()
            setPadding(pad, pad, pad, pad)
            inputType = InputType.TYPE_CLASS_TEXT
            maxLines = 1
        }
        root.addView(
            searchInput,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        )

        val resultsContainer = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val scroll = android.widget.ScrollView(this).apply { addView(resultsContainer) }
        val scrollLp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, (280 * density).toInt())
        scrollLp.topMargin = (12 * density).toInt()
        root.addView(scroll, scrollLp)

        val dialogRef = arrayOfNulls<android.app.Dialog>(1)

        fun renderResults(query: String) {
            resultsContainer.removeAllViews()
            val q = query.trim()
            val matches = if (q.isEmpty()) {
                products
            } else {
                products.filter { p ->
                    p.name.contains(q, ignoreCase = true) ||
                        (p.barcode?.contains(q, ignoreCase = true) == true) ||
                        p.unit.contains(q, ignoreCase = true)
                }
            }
            if (matches.isEmpty()) {
                val empty = TextView(this).apply {
                    text = getString(R.string.inventory_manual_no_results)
                    setTextColor(resources.getColor(R.color.text_secondary, theme))
                    textSize = 13f
                    val p = (10 * density).toInt()
                    setPadding(p, p, p, p)
                }
                resultsContainer.addView(empty)
                return
            }
            for (p in matches.take(50)) {
                val row = Button(this).apply {
                    text = "${p.name}\n${formatQty(counted[p.id] ?: p.quantity)} ${p.unit}"
                    isAllCaps = false
                    textSize = 13f
                    minHeight = (52 * density).toInt()
                    gravity = android.view.Gravity.START or android.view.Gravity.CENTER_VERTICAL
                    setTextColor(resources.getColor(R.color.text_primary, theme))
                    setBackgroundResource(R.drawable.input_field_bg)
                    val pad = (12 * density).toInt()
                    setPadding(pad, pad, pad, pad)
                }
                val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                lp.topMargin = (8 * density).toInt()
                row.setOnClickListener {
                    dialogRef[0]?.dismiss()
                    val et = etByProductId[p.id]
                    if (et != null) {
                        showScanQuantityDialog(p, et, suggestIncrement = false)
                    }
                }
                resultsContainer.addView(row, lp)
            }
        }

        searchInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                renderResults(s?.toString() ?: "")
            }
            override fun afterTextChanged(s: Editable?) {}
        })

        renderResults("")

        val dialog = AppDialog.show(
            context = this,
            title = getString(R.string.inventory_manual_dialog_title),
            contentView = root,
            positiveText = getString(R.string.dialog_close),
            onPositive = {},
            cancelable = true
        )
        dialogRef[0] = dialog
        dialog.setOnShowListener {
            searchInput.requestFocus()
            val imm = getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
            imm.showSoftInput(searchInput, android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT)
        }
    }

    /** Небольшой диалог в стиле приложения (см. AppDialog), который появляется сразу
     *  после успешного скана штрихкода: позволяет вписать фактическое количество
     *  найденного товара, не листая список вручную. Поле предзаполнено следующим
     *  по счёту значением (+1 к уже введённому) — при сканировании штучного товара
     *  по одной единице достаточно просто подтвердить кнопкой "Zapisz"; если нужно
     *  вписать точное число (например, после взвешивания или пересчёта упаковки),
     *  цифру легко стереть и ввести заново.
     *
     *  [suggestIncrement] управляет предзаполнением: true (скан) — current + 1,
     *  false (найден через ручной поиск, см. showManualFindDialog) — просто
     *  текущее введённое значение, так как при ручном поиске пользователь обычно
     *  сразу вписывает точное посчитанное число, а не сканирует поштучно. */
    private fun showScanQuantityDialog(product: Product, et: EditText, suggestIncrement: Boolean = true) {
        val current = counted[product.id] ?: product.quantity
        val suggested = if (suggestIncrement) current + 1.0 else current

        val input = EditText(this)
        input.inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL
        input.setText(formatQty(suggested))
        input.setTextColor(resources.getColor(R.color.text_primary, theme))
        input.setHintTextColor(resources.getColor(R.color.text_hint, theme))
        input.setBackgroundResource(R.drawable.card_bg)
        val pad = (14 * resources.displayMetrics.density).toInt()
        input.setPadding(pad, pad, pad, pad)

        val dialog = AppDialog.show(
            context = this,
            title = product.name,
            message = getString(R.string.inventory_current_stock, formatQty(product.quantity), product.unit),
            contentView = input,
            positiveText = getString(R.string.save),
            onPositive = {
                val value = input.text.toString().replace(',', '.').toDoubleOrNull() ?: suggested
                counted[product.id] = value
                et.setText(formatQty(value))
                Toast.makeText(this, getString(R.string.inventory_scan_found, product.name, formatQty(value)), Toast.LENGTH_SHORT).show()
            },
            negativeText = getString(R.string.dialog_close),
            onNegative = null
        )
        dialog.setOnShowListener {
            input.requestFocus()
            input.setSelection(input.text.length)
            val imm = getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
            imm.showSoftInput(input, android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT)
        }
    }

    /** Применяет посчитанные количества: обновляет остатки, пишет историю
     *  расхождений, формирует и сохраняет PDF-отчёт по сессии инвентаризации. */
    private fun saveInventory() {
        findViewById<Button>(R.id.btn_save_inventory).isEnabled = false
        val snapshot = products.map { it to (counted[it.id] ?: it.quantity) }
        CoroutineScope(Dispatchers.IO).launch {
            val db = AppDatabase.getInstance(applicationContext)
            val now = System.currentTimeMillis()

            val changedRecords = mutableListOf<InventoryRecord>()
            for ((product, newQty) in snapshot) {
                if (newQty == product.quantity) continue
                db.productDao().update(product.copy(quantity = newQty, updatedAtMillis = now))
                changedRecords.add(
                    InventoryRecord(
                        productId = product.id,
                        productName = product.name,
                        unit = product.unit,
                        quantityBefore = product.quantity,
                        quantityCounted = newQty,
                        priceNetAtInventory = product.priceNet,
                        priceSellAtInventory = product.priceSell,
                        dateMillis = now
                    )
                )
            }

            val pdfRows = snapshot.map { (product, newQty) ->
                InventoryPdfGenerator.Row(
                    name = product.name,
                    unit = product.unit,
                    before = product.quantity,
                    after = newQty,
                    priceNet = product.priceNet,
                    priceSell = product.priceSell
                )
            }
            val diffValueNet = pdfRows.sumOf { it.diffValue }
            val diffValueSell = pdfRows.sumOf { it.diffValueSell }
            val number = db.inventorySessionDao().count() + 1
            val fileFmt = SimpleDateFormat("yyyy-MM-dd_HHmm", Locale.US)
            val fileName = "Inwentaryzacja_${String.format(Locale.US, "%03d", number)}_${fileFmt.format(Date(now))}.pdf"
            val saved = InventoryFileStorage.savePdf(applicationContext, fileName) { out ->
                InventoryPdfGenerator.generate(this@InventoryActivity, number, now, pdfRows, out)
            }

            val session = InventorySession(
                number = number,
                dateMillis = now,
                pdfFilePath = saved.uri.toString(),
                totalProducts = snapshot.size,
                changedProducts = changedRecords.size,
                diffValueNet = diffValueNet,
                diffValueSell = diffValueSell
            )
            val sessionId = db.inventorySessionDao().insert(session)
            for (record in changedRecords) {
                db.inventoryRecordDao().insert(record.copy(sessionId = sessionId))
            }

            withContext(Dispatchers.Main) {
                findViewById<Button>(R.id.btn_save_inventory).isEnabled = true
                showSummary(changedRecords)
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
