package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
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

    // Флаг подавляет рекурсивные срабатывания TextWatcher-ов при программном
    // проставлении текста во время синхронизации цена_закупки/цена_продажи/наценка.
    private var isSyncingPrice = false

    private val scanLauncher = registerForActivityResult(ScanContract()) { result ->
        result.contents?.let { findViewById<EditText>(R.id.et_barcode).setText(it) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_add_edit_product)
        findViewById<android.view.View>(R.id.iv_back).setOnClickListener { finish() }

        val productId = intent.getLongExtra("productId", -1L)
        intent.getStringExtra("barcode")?.let { findViewById<EditText>(R.id.et_barcode).setText(it) }
        intent.getStringExtra("prefillName")?.let { findViewById<EditText>(R.id.et_name).setText(it) }

        findViewById<Button>(R.id.btn_scan_barcode_form).setOnClickListener {
            scanLauncher.launch(ScanOptions().setBeepEnabled(true).setOrientationLocked(true))
        }
        findViewById<Button>(R.id.btn_save_product).setOnClickListener { save() }
        findViewById<Button>(R.id.btn_delete_product).setOnClickListener { confirmDelete() }
        setupPriceSync()

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
                    isSyncingPrice = true
                    findViewById<EditText>(R.id.et_price).setText(formatNum(p.priceNet))
                    findViewById<EditText>(R.id.et_price_sell).setText(formatNum(p.priceSell))
                    findViewById<EditText>(R.id.et_margin).setText(formatNum(p.marginPercent))
                    isSyncingPrice = false
                }
            }
        }
    }

    /**
     * Двусторонняя синхронизация трёх полей цены: закупка, продажа, наценка %.
     *  - Меняется закупка при заполненной наценке → пересчитывается продажа.
     *  - Меняется закупка без наценки → пересчитывается наценка от текущей продажи.
     *  - Меняется наценка → продажа = закупка * (1 + наценка/100).
     *  - Меняется продажа напрямую (конкретной суммой) → наценка пересчитывается
     *    как фактический % относительно закупки, просто для информации.
     */
    private fun setupPriceSync() {
        val etPurchase = findViewById<EditText>(R.id.et_price)
        val etSell = findViewById<EditText>(R.id.et_price_sell)
        val etMargin = findViewById<EditText>(R.id.et_margin)

        fun watcher(action: () -> Unit) = object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                if (isSyncingPrice) return
                action()
            }
        }

        etPurchase.addTextChangedListener(watcher {
            val purchase = etPurchase.text.toString().toDoubleOrNull() ?: return@watcher
            val margin = etMargin.text.toString().toDoubleOrNull()
            isSyncingPrice = true
            if (margin != null) {
                etSell.setText(formatNum(purchase * (1.0 + margin / 100.0)))
            } else {
                val sell = etSell.text.toString().toDoubleOrNull() ?: 0.0
                if (purchase > 0.0) etMargin.setText(formatNum((sell - purchase) / purchase * 100.0))
            }
            isSyncingPrice = false
        })

        etMargin.addTextChangedListener(watcher {
            val purchase = etPurchase.text.toString().toDoubleOrNull() ?: 0.0
            val margin = etMargin.text.toString().toDoubleOrNull() ?: return@watcher
            isSyncingPrice = true
            etSell.setText(formatNum(purchase * (1.0 + margin / 100.0)))
            isSyncingPrice = false
        })

        etSell.addTextChangedListener(watcher {
            val purchase = etPurchase.text.toString().toDoubleOrNull() ?: 0.0
            val sell = etSell.text.toString().toDoubleOrNull() ?: return@watcher
            if (purchase > 0.0) {
                isSyncingPrice = true
                etMargin.setText(formatNum((sell - purchase) / purchase * 100.0))
                isSyncingPrice = false
            }
        })
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
        // Если цену продажи не ввели вообще — не оставляем товар с нулевой ценой продажи
        // (иначе при добавлении в фактуру со склада позиция уйдёт бесплатно); по умолчанию
        // она равна цене закупки, наценка 0%.
        val priceSell = findViewById<EditText>(R.id.et_price_sell).text.toString().toDoubleOrNull() ?: price
        val margin = if (price > 0.0) (priceSell - price) / price * 100.0 else 0.0

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
                        lowStockThreshold = low, priceNet = price, priceSell = priceSell, marginPercent = margin,
                        updatedAtMillis = System.currentTimeMillis()
                    )
                )
            } else {
                dao.insert(
                    Product(
                        barcode = barcode, name = name, quantity = qty, unit = unit,
                        lowStockThreshold = low, priceNet = price, priceSell = priceSell, marginPercent = margin
                    )
                )
            }
            withContext(Dispatchers.Main) {
                Toast.makeText(this@AddEditProductActivity, getString(R.string.product_saved), Toast.LENGTH_SHORT).show()
                finish()
            }
        }
    }

    private fun formatNum(v: Double): String = if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()
}
