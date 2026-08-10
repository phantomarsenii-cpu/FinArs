package com.example.fa_ksiegowy

import android.content.Context
import java.util.Calendar

/**
 * Kontrola rocznego limitu 20 000 PLN sprzedaży gotówkowej na rzecz osób
 * fizycznych nieprowadzących działalności gospodarczej (art. 111 ust. 1
 * ustawy o VAT wraz z rozporządzeniem w sprawie zwolnień z kasy fiskalnej).
 * Po przekroczeniu limitu powstaje obowiązek posiadania kasy fiskalnej.
 * Płatności bezgotówkowe (przelew, BLIK) NIE wliczają się do tego limitu.
 */
object CashLimitHelper {

    const val LIMIT = 20000.0
    const val WARNING_RATIO = 0.8 // 16 000 PLN

    data class Status(val currentCashSum: Double) {
        val ratio: Double get() = (currentCashSum / LIMIT).coerceAtLeast(0.0)
        val percent: Int get() = (ratio * 100).toInt()
        val nearLimit: Boolean get() = ratio >= WARNING_RATIO
        val exceeded: Boolean get() = currentCashSum > LIMIT
    }

    private fun yearRange(year: Int): Pair<Long, Long> {
        val start = Calendar.getInstance().apply {
            set(year, Calendar.JANUARY, 1, 0, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val end = (start.clone() as Calendar).apply { add(Calendar.YEAR, 1) }
        return start.timeInMillis to (end.timeInMillis - 1)
    }

    /** Suma gotówki dla osób fizycznych w bieżącym roku kalendarzowym, bez [excludingInvoiceId] (edycja). */
    suspend fun computeCurrentYear(context: Context, excludingInvoiceId: Long? = null): Status {
        val db = AppDatabase.getInstance(context)
        val year = Calendar.getInstance().get(Calendar.YEAR)
        val (from, to) = yearRange(year)
        val invoices = db.invoiceDao().getBetween(from, to)
        val sum = invoices
            .filter { it.id != excludingInvoiceId }
            .filter { it.isPhysicalPerson && it.paymentMethod.countsTowardCashLimit }
            .sumOf { it.amount }
        return Status(sum)
    }
}
