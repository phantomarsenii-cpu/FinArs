package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Склад: список товаров, добавление вручную или сканированием штрихкода, удаление. */
class MagazinFragment : Fragment() {
    private lateinit var adapter: ProductAdapter

    private val scanLauncher = registerForActivityResult(ScanContract()) { result ->
        val barcode = result.contents
        if (barcode != null) handleScannedBarcode(barcode)
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        return inflater.inflate(R.layout.fragment_magazin, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        adapter = ProductAdapter(
            onClick = { p ->
                startActivity(Intent(requireContext(), AddEditProductActivity::class.java).putExtra("productId", p.id))
            },
            onLongClick = { p -> confirmDelete(p); true }
        )
        requireView().findViewById<RecyclerView>(R.id.rv_products).apply {
            layoutManager = LinearLayoutManager(requireContext())
            adapter = this@MagazinFragment.adapter
        }

        requireView().findViewById<Button>(R.id.btn_add_product_manual).setOnClickListener {
            startActivity(Intent(requireContext(), AddEditProductActivity::class.java))
        }
        requireView().findViewById<Button>(R.id.btn_scan_barcode).setOnClickListener {
            scanLauncher.launch(
                ScanOptions()
                    .setDesiredBarcodeFormats(ScanOptions.ALL_CODE_TYPES)
                    .setPrompt(getString(R.string.scan_barcode_prompt))
                    .setBeepEnabled(true)
                    .setOrientationLocked(true)
            )
        }
        requireView().findViewById<Button>(R.id.btn_inventory).setOnClickListener {
            startActivity(Intent(requireContext(), InventoryActivity::class.java))
        }
    }

    override fun onResume() {
        super.onResume()
        loadProducts()
    }

    private fun loadProducts() {
        viewLifecycleOwner.lifecycleScope.launch(Dispatchers.IO) {
            val all = AppDatabase.getInstance(requireContext().applicationContext).productDao().getAll()
            withContext(Dispatchers.Main) {
                adapter.submitList(all)
                val low = all.filter { it.isLowStock }
                val banner = requireView().findViewById<TextView>(R.id.tv_low_stock_banner)
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
        viewLifecycleOwner.lifecycleScope.launch(Dispatchers.IO) {
            val existing = AppDatabase.getInstance(requireContext().applicationContext).productDao().getByBarcode(barcode)
            if (existing != null) {
                withContext(Dispatchers.Main) {
                    startActivity(Intent(requireContext(), AddEditProductActivity::class.java).putExtra("productId", existing.id))
                }
                return@launch
            }
            withContext(Dispatchers.Main) {
                Toast.makeText(requireContext(), getString(R.string.looking_up_product), Toast.LENGTH_SHORT).show()
            }
            val name = ProductLookupService.lookupName(barcode)
            withContext(Dispatchers.Main) {
                val i = Intent(requireContext(), AddEditProductActivity::class.java)
                i.putExtra("barcode", barcode)
                if (name != null) i.putExtra("prefillName", name)
                startActivity(i)
            }
        }
    }

    private fun confirmDelete(p: Product) {
        AlertDialog.Builder(requireContext())
            .setTitle(getString(R.string.delete_confirm_title))
            .setMessage(getString(R.string.delete_confirm_message))
            .setPositiveButton(getString(R.string.delete_confirm_yes)) { _, _ ->
                viewLifecycleOwner.lifecycleScope.launch(Dispatchers.IO) {
                    AppDatabase.getInstance(requireContext().applicationContext).productDao().delete(p)
                    withContext(Dispatchers.Main) { loadProducts() }
                }
            }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
    }
}
