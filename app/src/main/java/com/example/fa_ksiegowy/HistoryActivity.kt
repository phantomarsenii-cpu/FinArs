package com.example.fa_ksiegowy

import android.app.DatePickerDialog
import android.content.Intent
import android.graphics.Typeface
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Ekran "Transakcje" — pelna historia operacji z wyszukiwarka, filtrem daty i
 * zakladkami Wszystkie/Przychody/Wydatki, dokladnie wedlug makietu. Lista jest
 * pogrupowana wg miesiaca (zob. HistoryAdapter).
 */
class HistoryActivity : BaseActivity() {
    private lateinit var db: AppDatabase
    private lateinit var adapter: HistoryAdapter

    private var allEntries: List<Entry> = emptyList()
    private var searchQuery: String = ""
    private var filterFrom: Long? = null
    private var filterTo: Long? = null
    /** null = wszystkie, true = tylko przychody, false = tylko wydatki. */
    private var incomeFilter: Boolean? = null

    private val searchHandler = Handler(Looper.getMainLooper())
    private var pendingFilter: Runnable? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_history)
        BottomNavBar.attach(this, BottomNavBar.Tab.TRANSACTIONS)
        db = AppDatabase.getInstance(this)

        adapter = HistoryAdapter { entry ->
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

        setupTabs()
        setupSearchAndFilters()
        loadData()
    }

    override fun onResume() {
        super.onResume()
        // Обновляем список при каждом возврате на экран — например, после редактирования
        // или удаления записи в AddEntryActivity. Текущий поиск/фильтр сохраняется.
        loadData()
    }

    private fun setupTabs() {
        findViewById<View>(R.id.tab_all).setOnClickListener { selectTab(null) }
        findViewById<View>(R.id.tab_income).setOnClickListener { selectTab(true) }
        findViewById<View>(R.id.tab_expense).setOnClickListener { selectTab(false) }
        selectTab(null)
    }

    private fun selectTab(filter: Boolean?) {
        incomeFilter = filter
        val active = ContextCompat.getColor(this, R.color.text_primary)
        val inactive = ContextCompat.getColor(this, R.color.text_secondary)
        val line = ContextCompat.getColor(this, R.color.accent_blue_light)
        val transparent = ContextCompat.getColor(this, android.R.color.transparent)

        fun style(tabTv: Int, indicator: Int, isActive: Boolean) {
            findViewById<TextView>(tabTv).apply {
                setTextColor(if (isActive) active else inactive)
                setTypeface(typeface, if (isActive) Typeface.BOLD else Typeface.NORMAL)
            }
            findViewById<View>(indicator).setBackgroundColor(if (isActive) line else transparent)
        }
        style(R.id.tv_tab_all, R.id.indicator_all, filter == null)
        style(R.id.tv_tab_income, R.id.indicator_income, filter == true)
        style(R.id.tv_tab_expense, R.id.indicator_expense, filter == false)

        applyFilters()
    }

    private fun setupSearchAndFilters() {
        val etSearch = findViewById<EditText>(R.id.et_search)
        val btnClearSearch = findViewById<TextView>(R.id.btn_clear_search)
        val btnFilterDate = findViewById<View>(R.id.btn_filter_date)
        val btnFilterClear = findViewById<TextView>(R.id.btn_filter_clear)

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
        findViewById<TextView>(R.id.btn_filter_clear).visibility =
            if (filterFrom != null || searchQuery.isNotEmpty()) View.VISIBLE else View.GONE
    }

    private fun loadData() {
        CoroutineScope(Dispatchers.IO).launch {
            allEntries = db.entryDao().getAll()
            withContext(Dispatchers.Main) { applyFilters() }
        }
    }

    /**
     * Применяет текущий поисковый запрос, фильтр по датам и вкладку
     * Wszystkie/Przychody/Wydatki к списку операций.
     */
    private fun applyFilters() {
        val query = searchQuery
        val from = filterFrom
        val to = filterTo
        val incFilter = incomeFilter
        val source = allEntries

        CoroutineScope(Dispatchers.Default).launch {
            val filtered = source.filter { entry ->
                if (incFilter != null && entry.isIncome != incFilter) return@filter false
                val inRange = (from == null || entry.dateMillis >= from) &&
                        (to == null || entry.dateMillis <= to)
                if (!inRange) return@filter false
                if (query.isEmpty()) return@filter true

                val amountStr = String.format(Locale.getDefault(), "%.2f", entry.amount)
                (entry.comment?.contains(query, ignoreCase = true) == true) ||
                        amountStr.contains(query, ignoreCase = true)
            }

            withContext(Dispatchers.Main) {
                adapter.submitEntries(filtered)
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
}
