package com.example.fa_ksiegowy

import android.content.ActivityNotFoundException
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.TextView
import android.widget.Toast
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Экран истории всех выставленных счетов/фактур (Faktura imienna / Rachunek).
 * Тап по строке открывает сохранённый PDF в системном просмотрщике; если
 * подходящее приложение не найдено — показываем путь к папке текстом.
 */
class InvoiceHistoryActivity : BaseActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_invoice_history)

        findViewById<RecyclerView>(R.id.rv_invoices).layoutManager = LinearLayoutManager(this)
        loadData()
    }

    override fun onResume() {
        super.onResume()
        // Список могут пополнить новой записью, вернувшись с экрана выставления счёта.
        loadData()
    }

    private fun loadData() {
        CoroutineScope(Dispatchers.IO).launch {
            val allInvoices = AppDatabase.getInstance(applicationContext).invoiceDao().getAll()
            withContext(Dispatchers.Main) {
                findViewById<RecyclerView>(R.id.rv_invoices).adapter = InvoiceAdapter(allInvoices) { invoice ->
                    openInvoicePdf(invoice)
                }
                findViewById<TextView>(R.id.tv_no_invoices).visibility =
                    if (allInvoices.isEmpty()) View.VISIBLE else View.GONE
            }
        }
    }

    private fun openInvoicePdf(invoice: Invoice) {
        try {
            startActivity(InvoiceFileStorage.viewIntent(Uri.parse(invoice.pdfFilePath)))
        } catch (e: ActivityNotFoundException) {
            Toast.makeText(this, getString(R.string.open_folder_error, InvoiceFileStorage.displayFolderPath), Toast.LENGTH_LONG).show()
        }
    }
}
