package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.app.DatePickerDialog
import android.content.ActivityNotFoundException
import android.content.Intent
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
 * Экран истории всех выставленных счетов/фактур (Faktura imienna / Rachunek) И
 * korekt (faktur korygujących) к ним — Update: обе сущности показываются в
 * ОДНОЙ хронологической ленте (см. [InvoiceHistoryItem]), так как korekta это
 * тоже официально выставленный документ и должна быть видна в Historii, а не
 * только доступна с экрана оригинальной фактуры (зголошение użytkownika).
 * Тап по строке открывает сохранённый PDF в системном просмотрщике; если
 * подходящее приложение не найдено — показываем путь к папке текстом.
 * Кнопка "✕" на строке удаляет ошибочно выставленный счёт/корректировку
 * (запись из БД и сохранённый PDF-файл) после подтверждения.
 *
 * Поддерживает поиск (номер документа, имя клиента, NIP, сумма) и фильтр
 * по диапазону дат выдачи — оба работают динамически поверх уже
 * загруженного списка, без повторных запросов к БД. Фильтр по статусу
 * (Zapłacona/Oczekuje) применяется только к фактурам — у korekt нет статуса
 * оплаты, поэтому они видны только на вкладке "Wszystkie".
 */
class InvoiceHistoryActivity : BaseActivity() {

    private lateinit var adapter: InvoiceAdapter
    private val filterDateFmt = SimpleDateFormat("dd.MM.yy", Locale.getDefault())

    private var allInvoices: List<Invoice> = emptyList()
    private var allCorrections: List<InvoiceCorrection> = emptyList()
    private var searchQuery: String = ""
    private var filterFrom: Long? = null
    private var filterTo: Long? = null
    private var statusFilter: InvoiceStatus? = null

    private val searchHandler = Handler(Looper.getMainLooper())
    private var pendingFilter: Runnable? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_invoice_history)
        findViewById<android.view.View>(R.id.iv_back).setOnClickListener { finish() }

        adapter = InvoiceAdapter(
            onItemClick = { invoice -> openInvoicePdf(invoice) },
            onCorrectionClick = { correction -> openCorrectionPdf(correction) },
            onDeleteClick = { invoice -> confirmDelete(invoice) },
            onDeleteCorrectionClick = { correction -> confirmDeleteCorrection(correction) },
            onMarkPaidClick = { invoice -> confirmMarkPaid(invoice) },
            onKorektaClick = { invoice ->
                startActivity(
                    Intent(this, AddInvoiceCorrectionActivity::class.java)
                        .putExtra(AddInvoiceCorrectionActivity.EXTRA_INVOICE_ID, invoice.id)
                )
            }
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
            val db = AppDatabase.getInstance(applicationContext)
            allInvoices = db.invoiceDao().getAll()
            allCorrections = db.invoiceCorrectionDao().getAll()
            withContext(Dispatchers.Main) { applyFilters() }
        }
    }

    /**
     * Применяет текущий поисковый запрос (номер, клиент, NIP, сумма/дельта) и
     * фильтр по датам выдачи к ОБОИМ спискам — фактурам и корректировкам —
     * и сливает их в единую хронологическую ленту (сортировка по issueDateMillis
     * по убыванию, самые новые документы сверху). Фильтрация выполняется в
     * фоновом потоке (Dispatchers.Default), что остаётся быстрым даже при
     * большом числе выставленных документов.
     */
    private fun applyFilters() {
        val query = searchQuery
        val from = filterFrom
        val to = filterTo
        val status = statusFilter
        val invoiceSource = allInvoices
        val correctionSource = allCorrections

        CoroutineScope(Dispatchers.Default).launch {
            val filteredInvoices = invoiceSource.filter { inv ->
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

            // Korekty nie mają statusu płatności — pokazujemy je tylko, gdy nie jest
            // aktywny filtr Zapłacona/Oczekuje (czyli na zakładce "Wszystkie").
            val invoiceNumberById = invoiceSource.associate { it.id to it.invoiceNumber }
            val filteredCorrections = if (status != null) emptyList() else correctionSource.filter { cor ->
                val inRange = (from == null || cor.issueDateMillis >= from) &&
                        (to == null || cor.issueDateMillis <= to)
                if (!inRange) return@filter false
                if (query.isEmpty()) return@filter true

                val originalNumber = if (cor.originalInvoiceNumber > 0) cor.originalInvoiceNumber
                    else invoiceNumberById[cor.originalInvoiceId]
                val deltaStr = String.format(Locale.getDefault(), "%.2f", cor.deltaAmount)
                cor.correctionNumber.toString().contains(query, ignoreCase = true) ||
                        (originalNumber != null && originalNumber.toString().contains(query, ignoreCase = true)) ||
                        cor.reason.contains(query, ignoreCase = true) ||
                        deltaStr.contains(query, ignoreCase = true)
            }

            val merged: List<InvoiceHistoryItem> = filteredInvoices.map { InvoiceHistoryItem.InvoiceRow(it) } +
                filteredCorrections.map { cor ->
                    val originalNumber = if (cor.originalInvoiceNumber > 0) cor.originalInvoiceNumber
                        else invoiceNumberById[cor.originalInvoiceId]
                    InvoiceHistoryItem.CorrectionRow(cor, originalNumber)
                }
            val sorted = merged.sortedByDescending { it.issueDateMillis }

            withContext(Dispatchers.Main) {
                adapter.submitList(sorted)
                val tvNoInvoices = findViewById<TextView>(R.id.tv_no_invoices)
                if (sorted.isEmpty()) {
                    tvNoInvoices.visibility = View.VISIBLE
                    tvNoInvoices.text = if (allInvoices.isEmpty() && allCorrections.isEmpty())
                        getString(R.string.no_invoices) else getString(R.string.search_no_results)
                } else {
                    tvNoInvoices.visibility = View.GONE
                }
            }
        }
    }

    private fun openCorrectionPdf(correction: InvoiceCorrection) {
        val opened = InvoiceFileStorage.openPdfSafely(this, correction.pdfFilePath)
        if (!opened) {
            Toast.makeText(this, getString(R.string.open_folder_error, InvoiceFileStorage.displayFolderPath), Toast.LENGTH_LONG).show()
        }
    }

    /** Удаляет запись korekty и её PDF-файл. Обратите внимание: если korekta была
     *  применена к доходу (appliedToIncome), созданная Entry НЕ откатывается
     *  автоматически — так же, как удаление обычной фактуры не откатывает Entry,
     *  созданную при её выставлении (см. [confirmDelete]); при необходимости
     *  соответствующий приход нужно удалить вручную на экране Historii/главном. */
    private fun confirmDeleteCorrection(correction: InvoiceCorrection) {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.delete_correction_confirm_title))
            .setMessage(getString(R.string.delete_correction_confirm_message))
            .setPositiveButton(getString(R.string.delete_confirm_yes)) { _, _ ->
                CoroutineScope(Dispatchers.IO).launch {
                    InvoiceFileStorage.deleteFile(applicationContext, correction.pdfFilePath)
                    AppDatabase.getInstance(applicationContext).invoiceCorrectionDao().delete(correction)
                    withContext(Dispatchers.Main) {
                        Toast.makeText(this@InvoiceHistoryActivity, getString(R.string.correction_deleted), Toast.LENGTH_SHORT).show()
                        loadData()
                    }
                }
            }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
    }

    private fun openInvoicePdf(invoice: Invoice) {
        // openPdfSafely сам ловит и ActivityNotFoundException, и SecurityException
        // (известная проблема на части устройств с MediaStore-URI — раньше это
        // приводило к падению всего приложения при тапе по фактуре) и делает
        // одну попытку через локальную копию файла, прежде чем сдаться.
        val opened = InvoiceFileStorage.openPdfSafely(this, invoice.pdfFilePath)
        if (!opened) {
            Toast.makeText(this, getString(R.string.open_folder_error, InvoiceFileStorage.displayFolderPath), Toast.LENGTH_LONG).show()
        }
    }

    /** Меняет статус на "оплачено" (сегодняшней датой) прямо из истории и
     *  перезаписывает уже сохранённый PDF-файл, чтобы он отражал новый статус —
     *  иначе документ продолжал бы показывать старую пометку "ожидает оплаты". */
    private fun confirmMarkPaid(invoice: Invoice) {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.invoice_mark_paid_confirm_title))
            .setMessage(getString(R.string.invoice_mark_paid_confirm_message))
            .setPositiveButton(getString(R.string.delete_confirm_yes)) { _, _ ->
                CoroutineScope(Dispatchers.IO).launch {
                    val paidInvoice = invoice.copy(status = InvoiceStatus.PAID, paymentDateMillis = System.currentTimeMillis(), dueDateMillis = null)
                    AppDatabase.getInstance(applicationContext).invoiceDao().update(paidInvoice)
                    val items = AppDatabase.getInstance(applicationContext).invoiceItemDao().getForInvoice(invoice.id)
                    val regenerated = try {
                        val pdfBytes = withContext(Dispatchers.Main) {
                            InvoiceHtmlPdfGenerator.generate(
                                context = applicationContext,
                                seller = InvoiceSellerDataStore.load(applicationContext),
                                invoiceNumber = paidInvoice.invoiceNumber,
                                issueDateMillis = paidInvoice.issueDateMillis,
                                paymentDateMillis = paidInvoice.paymentDateMillis,
                                serviceDateMillis = paidInvoice.serviceDateMillis,
                                isPhysicalPerson = paidInvoice.isPhysicalPerson,
                                buyerName = paidInvoice.buyerName,
                                buyerNip = paidInvoice.buyerNip,
                                buyerStreet = paidInvoice.buyerStreet,
                                buyerPostalCode = paidInvoice.buyerPostalCode,
                                buyerCity = paidInvoice.buyerCity,
                                serviceName = paidInvoice.serviceName,
                                amount = paidInvoice.amount,
                                paymentMethod = paidInvoice.paymentMethod,
                                invoiceStatus = InvoiceStatus.PAID,
                                dueDateMillis = null,
                                items = items
                            )
                        }
                        InvoiceFileStorage.overwritePdf(applicationContext, invoice.pdfFilePath) { out ->
                            out.write(pdfBytes)
                        }
                    } catch (e: Exception) {
                        false
                    }
                    withContext(Dispatchers.Main) {
                        Toast.makeText(
                            this@InvoiceHistoryActivity,
                            getString(if (regenerated) R.string.invoice_marked_paid_toast else R.string.invoice_marked_paid_pdf_warning),
                            Toast.LENGTH_SHORT
                        ).show()
                        loadData()
                    }
                }
            }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
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


