package com.example.fa_ksiegowy

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.TextView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale

/** Отдельный экран с полной историей операций и итоговой строкой (SUMA / ИТОГО). */
class HistoryActivity : BaseActivity() {
    private lateinit var db: AppDatabase

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_history)
        db = AppDatabase.getInstance(this)

        findViewById<RecyclerView>(R.id.rv_history).layoutManager = LinearLayoutManager(this)
        loadData()
    }

    override fun onResume() {
        super.onResume()
        // Обновляем список при каждом возврате на экран — например, после редактирования
        // или удаления записи в AddEntryActivity.
        loadData()
    }

    private fun loadData() {
        CoroutineScope(Dispatchers.IO).launch {
            val allEntries = db.entryDao().getAll()

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
                findViewById<RecyclerView>(R.id.rv_history).adapter = EntryAdapter(allEntries) { entry ->
                    startActivity(
                        Intent(this@HistoryActivity, AddEntryActivity::class.java)
                            .putExtra("entryId", entry.id)
                            .putExtra("isIncome", entry.isIncome)
                    )
                }
                findViewById<View>(R.id.tv_no_entries).visibility =
                    if (allEntries.isEmpty()) View.VISIBLE else View.GONE
                findViewById<View>(R.id.layout_totals).visibility =
                    if (allEntries.isEmpty()) View.GONE else View.VISIBLE

                findViewById<TextView>(R.id.tv_totals_income).text = formatMoney(income)
                findViewById<TextView>(R.id.tv_totals_expense).text = formatMoney(expense)
                findViewById<TextView>(R.id.tv_totals_tax).text = formatMoney(tax)
                findViewById<TextView>(R.id.tv_totals_net_profit).text = formatMoney(netProfit)
            }
        }
    }

    private fun formatMoney(v: Double): String = String.format(Locale.getDefault(), "%.2f", v)
}
