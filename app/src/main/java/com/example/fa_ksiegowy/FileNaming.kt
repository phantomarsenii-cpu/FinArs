package com.example.fa_ksiegowy

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Единый стандарт именования файлов чеков и отчётов, чтобы их можно было
 * сортировать по имени и легко находить/архивировать для налоговой:
 *
 *   Чек/квитанция:  YYYY-MM-DD_INCOME|EXPENSE_<сумма>PLN_<id>.<ext>
 *     пример:       2026-08-02_EXPENSE_150.00PLN_1042.jpg
 *
 *   Отчёт/PDF:      YYYY-MM-DD_<TYPE>_REPORT.<ext>
 *     пример:       2026-08-02_PIT36_REPORT.pdf
 */
object FileNaming {
    private val dateFmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    private val stampFmt = SimpleDateFormat("yyyy-MM-dd_HHmm", Locale.US)

    private fun sanitizeAmount(amount: Double): String =
        String.format(Locale.US, "%.2f", amount)

    /** Имя файла чека/квитанции. dateMillis — дата операции (не момент сохранения файла). */
    fun receiptFileName(dateMillis: Long, isIncome: Boolean, amount: Double, entryId: Long, ext: String = "jpg"): String {
        val type = if (isIncome) "INCOME" else "EXPENSE"
        val date = dateFmt.format(Date(dateMillis))
        return "${date}_${type}_${sanitizeAmount(amount)}PLN_${entryId}.$ext"
    }

    /** Имя файла для сгенерированного отчёта (xlsx/zip/pdf). type — например "REPORT_MONTH", "REPORT_YEAR", "PIT36". */
    fun reportFileName(type: String, ext: String): String {
        val date = dateFmt.format(Date())
        return "${date}_${type}_REPORT.$ext"
    }

    /** Имя файла для помощника PIT (PIT-36 / PIT-36L / PIT-28) с указанием года декларации. */
    fun pitFileName(formCode: String, year: Int, ext: String = "pdf"): String {
        val date = dateFmt.format(Date())
        val safeForm = formCode.replace("-", "").replace(" ", "")
        return "${date}_${safeForm}_${year}_REPORT.$ext"
    }

    /** Временная метка для файлов, где нужна уникальность, но не строгий стандарт (например ZIP-бэкапы). */
    fun timestamp(): String = stampFmt.format(Date())
}
