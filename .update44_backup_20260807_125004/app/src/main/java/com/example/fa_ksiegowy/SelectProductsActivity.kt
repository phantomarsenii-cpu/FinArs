package com.example.fa_ksiegowy

import android.content.Intent
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
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

/** Позиция, выбранная со склада для фактуры. */
data class PickedProduct(val productId: Long, val name: String, val quantity: Double, val unitPrice: Double)

/** Выбор нескольких товаров со склада (с количеством) для многопозиционной фактуры. */
class SelectProductsActivity : BaseActivity() {
    private var products: List<Product> = emptyList()
    private val checkedQty = mutableMapOf<Long, Double>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_select_products)
        findViewById<Button>(R.id.btn_confirm_selection).setOnClickListener { confirmSelection() }
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
        val container = findViewById<LinearLayout>(R.id.ll_products_container)
        container.removeAllViews()
        if (products.isEmpty()) {
            val empty = TextView(this)
            empty.text = getString(R.string.magazin_empty)
            empty.setTextColor(resources.getColor(R.color.text_secondary, theme))
            container.addView(empty)
            return
        }
        val inflater = LayoutInflater.from(this)
        for (p in products) {
            val row = inflater.inflate(R.layout.item_product_select, container, false)
            val cb = row.findViewById<CheckBox>(R.id.cb_select)
            val tvName = row.findViewById<TextView>(R.id.tv_select_name)
            val etQty = row.findViewById<EditText>(R.id.et_select_qty)

            tvName.text = "${p.name} (${formatNum(p.quantity)} ${p.unit} ${getString(R.string.in_stock_suffix)})"
            etQty.setText("1")
            etQty.isEnabled = false

            val btnMinus = row.findViewById<TextView>(R.id.btn_qty_minus)
            val btnPlus = row.findViewById<TextView>(R.id.btn_qty_plus)
            // "+" на невыбранном товаре сначала просто отмечает его (количество остаётся 1),
            // повторные нажатия увеличивают на 1 — так поведение интуитивно совпадает с
            // "добавить ещё одну единицу этого товара". "−" на количестве 1 снимает отметку.
            btnPlus.setOnClickListener {
                if (!cb.isChecked) {
                    cb.isChecked = true
                } else {
                    val cur = etQty.text.toString().toDoubleOrNull() ?: 1.0
                    etQty.setText(formatNum(cur + 1))
                }
            }
            btnMinus.setOnClickListener {
                if (!cb.isChecked) return@setOnClickListener
                val cur = etQty.text.toString().toDoubleOrNull() ?: 1.0
                if (cur <= 1.0) {
                    cb.isChecked = false
                } else {
                    etQty.setText(formatNum(cur - 1))
                }
            }

            cb.setOnCheckedChangeListener { _, isChecked ->
                etQty.isEnabled = isChecked
                if (isChecked) {
                    checkedQty[p.id] = etQty.text.toString().toDoubleOrNull() ?: 1.0
                } else {
                    checkedQty.remove(p.id)
                }
            }
            etQty.addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
                override fun afterTextChanged(s: Editable?) {
                    if (cb.isChecked) checkedQty[p.id] = s.toString().toDoubleOrNull() ?: 1.0
                }
            })
            container.addView(row)
        }
    }

    private fun confirmSelection() {
        val picked = products.filter { checkedQty.containsKey(it.id) }
            .map { PickedProduct(it.id, it.name, checkedQty[it.id] ?: 1.0, it.priceNet) }
        if (picked.isEmpty()) {
            Toast.makeText(this, getString(R.string.select_at_least_one_product), Toast.LENGTH_SHORT).show()
            return
        }
        val serialized = picked.joinToString("\n") { "${it.productId}|${it.name}|${it.quantity}|${it.unitPrice}" }
        val i = Intent()
        i.putExtra("picked_items", serialized)
        setResult(RESULT_OK, i)
        finish()
    }

    private fun formatNum(v: Double): String = if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()
}

