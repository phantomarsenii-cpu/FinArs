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
