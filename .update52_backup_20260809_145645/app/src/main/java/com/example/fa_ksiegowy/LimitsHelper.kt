package com.example.fa_ksiegowy

import android.content.Context
import java.util.Calendar

/**
 * Считает три показателя лимитов, которые отображаются на главном экране
 * гейджами (progress bar) и проверяются фоновым воркером для уведомлений:
 *
 *  1) monthly   — доход текущего месяца vs 75% minimalnego wynagrodzenia
 *                 (актуально только для NIEZAREJESTROWANA — контроль
 *                 обязанности регистрации JDG).
 *  2) bracket   — накопленный годовой dochód (przychód − koszty + otherIncome)
 *                 vs 120 000 zł (порог перехода с 12% на 32% по skali).
 *  3) vat       — накопленный годовой przychód (без вычета kosztów) vs
 *                 240 000 zł (лимит zwolnienia podmiotowego z VAT).
 */
object LimitsHelper {

    data class LimitStatus(
        val current: Double,
        val limit: Double
    ) {
        val ratio: Double get() = if (limit > 0) (current / limit).coerceAtLeast(0.0) else 0.0
        val percent: Int get() = (ratio * 100).toInt()
        val exceeded: Boolean get() = current > limit
    }

    data class AllLimits(
        val monthly: LimitStatus,
        val bracket: LimitStatus,
        val vat: LimitStatus,
        val activityType: ActivityType
    )

    private fun monthRange(now: Calendar): Pair<Long, Long> {
        val start = (now.clone() as Calendar).apply {
            set(Calendar.DAY_OF_MONTH, 1)
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val end = (start.clone() as Calendar).apply { add(Calendar.MONTH, 1) }
        return start.timeInMillis to end.timeInMillis
    }

    suspend fun compute(context: Context): AllLimits {
        val db = AppDatabase.getInstance(context)
        val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
        val activityType = ActivityTypeHelper.get(prefs)

        val now = Calendar.getInstance()
        val (monthStart, monthEndExclusive) = monthRange(now)
        val monthEntries = db.entryDao().getBetween(monthStart, monthEndExclusive - 1)
        val monthIncome = monthEntries.filter { it.isIncome }.sumOf { it.amount }

        val year = TaxHelper.currentYear()
        val (yearStart, yearEndExclusive) = TaxHelper.yearRange(year)
        val yearEntries = db.entryDao().getBetween(yearStart, yearEndExclusive - 1)
        val yearIncome = yearEntries.filter { it.isIncome }.sumOf { it.amount }
        val yearExpense = yearEntries.filter { !it.isIncome }.sumOf { it.amount }
        val yearProfit = yearIncome - yearExpense
        val otherIncome = TaxHelper.getOtherIncome(prefs, year)

        val monthlyLimit = ActivityTypeHelper.nierejestrowanaMonthlyLimit(prefs)
        val bracketStatus = LimitStatus(yearProfit + otherIncome, TaxHelper.SECOND_BRACKET_THRESHOLD)
        val vatStatus = LimitStatus(yearIncome, VAT_EXEMPT_LIMIT)
        val monthlyStatus = LimitStatus(monthIncome, monthlyLimit)

        return AllLimits(monthlyStatus, bracketStatus, vatStatus, activityType)
    }

    /** Roczny limit zwolnienia podmiotowego z VAT (art. 113 ustawy o VAT), proporcjonalny w pierwszym roku. */
    const val VAT_EXEMPT_LIMIT = 240000.0
}
