package com.example.fa_ksiegowy

import android.app.DatePickerDialog
import android.content.Intent
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
 * Отдельный экран с полной историей операций, итоговой строкой (SUMA / ИТОГО),
 * поиском по комментарию/сумме и фильтром по диапазону дат.
 */
class HistoryActivity : BaseActivity() {
    private lateinit var db: AppDatabase
    private lateinit var adapter: EntryAdapter
    private val filterDateFmt = SimpleDateFormat("dd.MM.yy", Locale.getDefault())

    private var allEntries: List<Entry> = emptyList()
    private var searchQuery: String = ""
    private var filterFrom: Long? = null
    private var filterTo: Long? = null

    private val searchHandler = Handler(Looper.getMainLooper())
    private var pendingFilter: Runnable? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_history)
        db = AppDatabase.getInstance(this)

        adapter = EntryAdapter { entry ->
            startActivity(
                Intent(this@HistoryActivity, AddEntryActivity::class.java)
                    .putExtra("entryId", entry.id)
                    .putExtra("isIncome", entry.isIncome)
            )
        }
        findViewById<RecyclerView>(R.id.rv_history).apply {
            layoutManager = LinearLayoutManager(this@HistoryActivity)
            adapter = this@HistoryActivity.adapter
        }

        setupSearchAndFilters()
        loadData()
    }

    override fun onResume() {
        super.onResume()
        // Обновляем список при каждом возврате на экран — например, после редактирования
        // или удаления записи в AddEntryActivity. Текущий поиск/фильтр сохраняется.
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
            allEntries = db.entryDao().getAll()

            val income = allEntries.filter { it.isIncome }.sumOf { it.amount }
            val expense = allEntries.filter { !it.isIncome }.sumOf { it.amount }
            val profit = income - expense

            val prefs = getSharedPreferences("settings", MODE_PRIVATE)
            val activityType = ActivityTypeHelper.get(prefs)
            val ryczaltRate = ActivityTypeHelper.getRyczaltRate(prefs)
            val year = TaxHelper.currentYear()
            val otherIncome = TaxHelper.getOtherIncome(prefs, year)
            val tax = when (activityType) {
                ActivityType.NIEZAREJESTROWANA, ActivityType.JDG_SKALA -> TaxHelper.calc(profit, otherIncome)
                ActivityType.JDG_LINIOWY -> TaxHelper.calcLiniowy(profit)
                ActivityType.JDG_RYCZALT -> TaxHelper.calcRyczalt(income, ryczaltRate)
            }.tax
            val netProfit = profit - tax

            withContext(Dispatchers.Main) {
                findViewById<View>(R.id.layout_totals).visibility =
                    if (allEntries.isEmpty()) View.GONE else View.VISIBLE

                findViewById<TextView>(R.id.tv_totals_income).text = formatMoney(income)
                findViewById<TextView>(R.id.tv_totals_expense).text = formatMoney(expense)
                findViewById<TextView>(R.id.tv_totals_tax).text = formatMoney(tax)
                findViewById<TextView>(R.id.tv_totals_net_profit).text = formatMoney(netProfit)

                applyFilters()
            }
        }
    }

    /**
     * Применяет текущий поисковый запрос и фильтр по датам к списку операций.
     * Фильтрация выполняется в фоновом потоке (Dispatchers.Default), что важно
     * для отзывчивости UI на больших списках операций.
     */
    private fun applyFilters() {
        val query = searchQuery
        val from = filterFrom
        val to = filterTo
        val source = allEntries

        CoroutineScope(Dispatchers.Default).launch {
            val filtered = source.filter { entry ->
                val inRange = (from == null || entry.dateMillis >= from) &&
                        (to == null || entry.dateMillis <= to)
                if (!inRange) return@filter false
                if (query.isEmpty()) return@filter true

                val amountStr = String.format(Locale.getDefault(), "%.2f", entry.amount)
                (entry.comment?.contains(query, ignoreCase = true) == true) ||
                        amountStr.contains(query, ignoreCase = true)
            }

            withContext(Dispatchers.Main) {
                adapter.submitList(filtered)
                val tvNoEntries = findViewById<TextView>(R.id.tv_no_entries)
                if (filtered.isEmpty()) {
                    tvNoEntries.visibility = View.VISIBLE
                    tvNoEntries.text = if (allEntries.isEmpty())
                        getString(R.string.no_entries) else getString(R.string.search_no_results)
                } else {
                    tvNoEntries.visibility = View.GONE
                }
            }
        }
    }

    private fun formatMoney(v: Double): String = String.format(Locale.getDefault(), "%.2f", v)
}
