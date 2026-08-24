package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Склад: список товаров, добавление вручную или сканированием штрихкода, удаление. */
class MagazinActivity : BaseActivity() {
    private lateinit var adapter: ProductAdapter

    private val scanLauncher = registerForActivityResult(ScanContract()) { result ->
        val barcode = result.contents
        if (barcode != null) handleScannedBarcode(barcode)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_magazin)
        BottomNavBar.attach(this, BottomNavBar.Tab.MAGAZIN)

        adapter = ProductAdapter(
            onClick = { p ->
                startActivity(Intent(this, AddEditProductActivity::class.java).putExtra("productId", p.id))
            },
            onLongClick = { p -> confirmDelete(p); true }
        )
        findViewById<RecyclerView>(R.id.rv_products).apply {
            layoutManager = LinearLayoutManager(this@MagazinActivity)
            adapter = this@MagazinActivity.adapter
        }

        findViewById<Button>(R.id.btn_add_product_manual).setOnClickListener {
            startActivity(Intent(this, AddEditProductActivity::class.java))
        }
        findViewById<Button>(R.id.btn_scan_barcode).setOnClickListener {
            scanLauncher.launch(
                ScanOptions()
                    .setDesiredBarcodeFormats(ScanOptions.ALL_CODE_TYPES)
                    .setPrompt(getString(R.string.scan_barcode_prompt))
                    .setBeepEnabled(true)
                    .setOrientationLocked(true)
            )
        }
        findViewById<Button>(R.id.btn_inventory).setOnClickListener {
            startActivity(Intent(this, InventoryActivity::class.java))
        }
    }

    override fun onResume() {
        super.onResume()
        loadProducts()
    }

    private fun loadProducts() {
        CoroutineScope(Dispatchers.IO).launch {
            val all = AppDatabase.getInstance(applicationContext).productDao().getAll()
            withContext(Dispatchers.Main) {
                adapter.submitList(all)
                val low = all.filter { it.isLowStock }
                val banner = findViewById<TextView>(R.id.tv_low_stock_banner)
                if (low.isNotEmpty()) {
                    banner.text = getString(R.string.low_stock_banner, low.size)
                    banner.visibility = View.VISIBLE
                } else {
                    banner.visibility = View.GONE
                }
            }
        }
    }

    /** Штрихкод отсканирован: если товар уже есть — открываем на редактирование (пополнение),
     *  иначе пробуем найти название в Open Food Facts, а если не нашли — открываем ручной ввод
     *  с уже подставленным штрихкодом. */
    private fun handleScannedBarcode(barcode: String) {
        CoroutineScope(Dispatchers.IO).launch {
            val existing = AppDatabase.getInstance(applicationContext).productDao().getByBarcode(barcode)
            if (existing != null) {
                withContext(Dispatchers.Main) {
                    startActivity(Intent(this@MagazinActivity, AddEditProductActivity::class.java).putExtra("productId", existing.id))
                }
                return@launch
            }
            withContext(Dispatchers.Main) {
                Toast.makeText(this@MagazinActivity, getString(R.string.looking_up_product), Toast.LENGTH_SHORT).show()
            }
            val name = ProductLookupService.lookupName(barcode)
            withContext(Dispatchers.Main) {
                val i = Intent(this@MagazinActivity, AddEditProductActivity::class.java)
                i.putExtra("barcode", barcode)
                if (name != null) i.putExtra("prefillName", name)
                startActivity(i)
            }
        }
    }

    private fun confirmDelete(p: Product) {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.delete_confirm_title))
            .setMessage(getString(R.string.delete_confirm_message))
            .setPositiveButton(getString(R.string.delete_confirm_yes)) { _, _ ->
                CoroutineScope(Dispatchers.IO).launch {
                    AppDatabase.getInstance(applicationContext).productDao().delete(p)
                    withContext(Dispatchers.Main) { loadProducts() }
                }
            }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
    }
}
