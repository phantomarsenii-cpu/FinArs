package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.app.DatePickerDialog
import android.content.ActivityNotFoundException
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Экран истории всех выставленных счетов/фактур (Faktura imienna / Rachunek).
 * Тап по строке открывает сохранённый PDF в системном просмотрщике; если
 * подходящее приложение не найдено — показываем путь к папке текстом.
 * Кнопка "✕" на строке удаляет ошибочно выставленный счёт (запись из БД
 * и сохранённый PDF-файл) после подтверждения.
 *
 * Поддерживает поиск (номер документа, имя клиента, NIP, сумма) и фильтр
 * по диапазону дат выдачи — оба работают динамически поверх уже
 * загруженного списка, без повторных запросов к БД.
 */
class InvoiceHistoryActivity : BaseActivity() {

    private lateinit var adapter: InvoiceAdapter
    private val filterDateFmt = SimpleDateFormat("dd.MM.yy", Locale.getDefault())

    private var allInvoices: List<Invoice> = emptyList()
    private var searchQuery: String = ""
    private var filterFrom: Long? = null
    private var filterTo: Long? = null
    private var statusFilter: InvoiceStatus? = null

    private val searchHandler = Handler(Looper.getMainLooper())
    private var pendingFilter: Runnable? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_invoice_history)

        adapter = InvoiceAdapter(
            onItemClick = { invoice -> openInvoicePdf(invoice) },
            onDeleteClick = { invoice -> confirmDelete(invoice) }
        )
        findViewById<RecyclerView>(R.id.rv_invoices).apply {
            layoutManager = LinearLayoutManager(this@InvoiceHistoryActivity)
            adapter = this@InvoiceHistoryActivity.adapter
        }

        setupSearchAndFilters()
        loadData()
    }

    override fun onResume() {
        super.onResume()
        // Список могут пополнить новой записью, вернувшись с экрана выставления счёта.
        // Текущий поиск/фильтр сохраняется.
        loadData()
    }

    private fun setupSearchAndFilters() {
        val etSearch = findViewById<EditText>(R.id.et_search)
        val btnClearSearch = findViewById<TextView>(R.id.btn_clear_search)
        val btnFilterDate = findViewById<Button>(R.id.btn_filter_date)
        val btnFilterClear = findViewById<Button>(R.id.btn_filter_clear)

        etSearch.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                searchQuery = s?.toString()?.trim().orEmpty()
                btnClearSearch.visibility = if (searchQuery.isEmpty()) View.GONE else View.VISIBLE
                updateClearFiltersVisibility()
                scheduleFilter()
            }
        })

        btnClearSearch.setOnClickListener { etSearch.setText("") }

        btnFilterDate.setOnClickListener { showDateRangePicker() }

        btnFilterClear.setOnClickListener {
            filterFrom = null
            filterTo = null
            btnFilterDate.text = getString(R.string.filter_date_range)
            etSearch.setText("")
            updateClearFiltersVisibility()
            applyFilters()
        }

        findViewById<Button>(R.id.btn_status_all).setOnClickListener { setStatusFilter(null) }
        findViewById<Button>(R.id.btn_status_paid).setOnClickListener { setStatusFilter(InvoiceStatus.PAID) }
        findViewById<Button>(R.id.btn_status_pending).setOnClickListener { setStatusFilter(InvoiceStatus.PENDING) }
        applyStatusFilterUi()
    }

    private fun setStatusFilter(status: InvoiceStatus?) {
        statusFilter = status
        applyStatusFilterUi()
        applyFilters()
    }

    /** Явно выделяем активный фильтр статуса — тот же приём, что и для способа оплаты на экране выставления счёта. */
    private fun applyStatusFilterUi() {
        val all = findViewById<Button>(R.id.btn_status_all)
        val paid = findViewById<Button>(R.id.btn_status_paid)
        val pending = findViewById<Button>(R.id.btn_status_pending)
        for ((button, selected) in listOf(
            all to (statusFilter == null),
            paid to (statusFilter == InvoiceStatus.PAID),
            pending to (statusFilter == InvoiceStatus.PENDING)
        )) {
            button.setBackgroundResource(if (selected) R.drawable.btn_pill_payment_selected else R.drawable.btn_pill_payment_unselected)
            button.setTextColor(resources.getColor(if (selected) R.color.text_primary else R.color.text_secondary, theme))
        }

    /** Небольшой дебаунс — фильтрация не запускается на каждый символ, а через 250 мс после паузы в наборе. */
    private fun scheduleFilter() {
        pendingFilter?.let { searchHandler.removeCallbacks(it) }
        val r = Runnable { applyFilters() }
        pendingFilter = r
        searchHandler.postDelayed(r, 250)
    }

    private fun showDateRangePicker() {
        val cal = Calendar.getInstance()
        DatePickerDialog(
            this,
            { _, fromYear, fromMonth, fromDay ->
                val fromCal = Calendar.getInstance()
                fromCal.set(fromYear, fromMonth, fromDay, 0, 0, 0)
                fromCal.set(Calendar.MILLISECOND, 0)
                val fromMillis = fromCal.timeInMillis

                DatePickerDialog(
                    this,
                    { _, toYear, toMonth, toDay ->
                        val toCal = Calendar.getInstance()
                        toCal.set(toYear, toMonth, toDay, 23, 59, 59)
                        toCal.set(Calendar.MILLISECOND, 999)
                        val toMillis = toCal.timeInMillis

                        if (toMillis < fromMillis) {
                            Toast.makeText(this, getString(R.string.custom_range_invalid), Toast.LENGTH_LONG).show()
                            return@DatePickerDialog
                        }

                        filterFrom = fromMillis
                        filterTo = toMillis
                        findViewById<Button>(R.id.btn_filter_date).text =
                            "${filterDateFmt.format(Date(fromMillis))}–${filterDateFmt.format(Date(toMillis))}"
                        updateClearFiltersVisibility()
                        applyFilters()
                    },
                    cal.get(Calendar.YEAR), cal.get(Calendar.MONTH), cal.get(Calendar.DAY_OF_MONTH)
                ).apply { setTitle(getString(R.string.to)) }.show()
            },
            cal.get(Calendar.YEAR), cal.get(Calendar.MONTH), cal.get(Calendar.DAY_OF_MONTH)
        ).apply { setTitle(getString(R.string.from)) }.show()
    }

    private fun updateClearFiltersVisibility() {
        findViewById<Button>(R.id.btn_filter_clear).visibility =
            if (filterFrom != null || searchQuery.isNotEmpty()) View.VISIBLE else View.GONE
    }

    private fun loadData() {
        CoroutineScope(Dispatchers.IO).launch {
            allInvoices = AppDatabase.getInstance(applicationContext).invoiceDao().getAll()
            withContext(Dispatchers.Main) { applyFilters() }
        }
    }

    /**
     * Применяет текущий поисковый запрос (номер, клиент, NIP, сумма) и фильтр
     * по датам выдачи. Фильтрация выполняется в фоновом потоке (Dispatchers.Default),
     * что остаётся быстрым даже при большом числе выставленных счетов.
     */
    private fun applyFilters() {
        val query = searchQuery
        val from = filterFrom
        val to = filterTo
        val status = statusFilter
        val source = allInvoices

        CoroutineScope(Dispatchers.Default).launch {
            val filtered = source.filter { inv ->
                val inRange = (from == null || inv.issueDateMillis >= from) &&
                        (to == null || inv.issueDateMillis <= to)
                if (!inRange) return@filter false
                if (status != null && inv.status != status) return@filter false
                if (query.isEmpty()) return@filter true

                val amountStr = String.format(Locale.getDefault(), "%.2f", inv.amount)
                inv.invoiceNumber.toString().contains(query, ignoreCase = true) ||
                        inv.buyerName.contains(query, ignoreCase = true) ||
                        (inv.buyerNip?.contains(query, ignoreCase = true) == true) ||
                        inv.serviceName.contains(query, ignoreCase = true) ||
                        amountStr.contains(query, ignoreCase = true)
            }

            withContext(Dispatchers.Main) {
                adapter.submitList(filtered)
                val tvNoInvoices = findViewById<TextView>(R.id.tv_no_invoices)
                if (filtered.isEmpty()) {
                    tvNoInvoices.visibility = View.VISIBLE
                    tvNoInvoices.text = if (allInvoices.isEmpty())
                        getString(R.string.no_invoices) else getString(R.string.search_no_results)
                } else {
                    tvNoInvoices.visibility = View.GONE
                }
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

    private fun confirmDelete(invoice: Invoice) {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.delete_invoice_confirm_title))
            .setMessage(getString(R.string.delete_invoice_confirm_message))
            .setPositiveButton(getString(R.string.delete_confirm_yes)) { _, _ ->
                CoroutineScope(Dispatchers.IO).launch {
                    InvoiceFileStorage.deleteFile(applicationContext, invoice.pdfFilePath)
                    AppDatabase.getInstance(applicationContext).invoiceDao().delete(invoice)
                    withContext(Dispatchers.Main) {
                        Toast.makeText(this@InvoiceHistoryActivity, getString(R.string.invoice_deleted), Toast.LENGTH_SHORT).show()
                        loadData()
                    }
                }
            }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
    }
}
