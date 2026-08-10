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
 * или сканируя штрихкод каждого товара (каждое сканирование прибавляет 1 к
 * посчитанному количеству найденного по штрихкоду товара, чтобы не листать
 * список и не набирать цифры при большом ассортименте). При сохранении:
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
                    .setOrientationLocked(true)
            )
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
     *  есть на складе — прибавляем 1 к его посчитанному количеству (самый частый
     *  случай — штучный товар, сканируем каждую единицу по одной); если товар
     *  не найден — сообщаем об этом, ничего не меняя. */
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
                val newQty = (counted[product.id] ?: product.quantity) + 1.0
                et.setText(formatQty(newQty))
                Toast.makeText(this@InventoryActivity, getString(R.string.inventory_scan_found, product.name, formatQty(newQty)), Toast.LENGTH_SHORT).show()
            }
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
