package com.example.fa_ksiegowy

import android.content.Context
import java.util.Calendar

/**
 * Считает показатели лимитов, которые отображаются на главном экране
 * гейджами (progress bar) и проверяются фоновым воркером для уведомлений:
 *
 *  1) quarterly    — Update (ustawa 2026): od 01.01.2026 miesięczny limit
 *                     działalności nierejestrowanej (75% minimalnego wynagrodzenia)
 *                     PRZESTAŁ obowiązywać — zastąpił go limit KWARTALNY
 *                     10 813,50 zł (225% minimalnego wynagrodzenia, zob.
 *                     QUARTERLY_LIMIT_2026). Przekroczenie limitu choćby w JEDNYM
 *                     kwartale rodzi obowiązek zarejestrowania JDG. Aktualne
 *                     tylko dla NIEZAREJESTROWANA.
 *  1b) yearlyIncomeSum — suma przychodu od początku ROKU kalendarzowego — nie jest
 *                     osobnym limitem ustawowym (10 813,50 × 4 = 43 254 zł to czysto
 *                     matematyczna suma czterech kwartałów, informacyjna), pokazywana
 *                     pod gejdżem kwartalnym jako "Suma roczna (informacyjnie)".
 *  2) bracket      — накопленный годовой dochód (przychód − koszty + otherIncome)
 *                     vs 120 000 zł (порог перехода с 12% на 32% по skali).
 *                     Используется ТОЛЬКО фоновым воркером уведомлений
 *                     (приближение к порогу) — не для отображения гейджа.
 *  3) bracketStage — Update: правильная ДВУХЭТАПНАЯ шкала прогрессивной skali
 *                     podatkowej для главного экрана (см. BracketStage):
 *                     сперва 0–30 000 zł (kwota wolna od podatku, 0%), после
 *                     заполнения — 30 000–120 000 zł (stawka 12%, do progu),
 *                     а после превышения 120 000 zł — nadwyżka opodatkowana 32%.
 *                     Раньше гейдж ошибочно показывал ОДНУ шкалу "0.../120 000 zł"
 *                     с подписью "Pierwszy próg podatkowy" — это было и неверно
 *                     названо (120 000 to DRUGI próg, nie pierwszy), и не
 *                     показывало пользователю, сколько осталось до 30 000 zł
 *                     kwoty wolnej (зголошение użytkownika, zrzuty ekranu).
 *                     Эта шкала НЕ связана с лимитом kwartalnym выше — не менялась.
 *  4) vat          — накопленный годовой przychód (без вычета kosztów) vs
 *                     240 000 zł (лимит zwolnienia podmiotowego z VAT).
 */
object LimitsHelper {

    /** Kwartalny limit przychodu działalności nierejestrowanej obowiązujący od
     *  01.01.2026 — 225% minimalnego wynagrodzenia (4 806 zł), ustalony ustawowo
     *  jako stała kwota, w przeciwieństwie do starego limitu miesięcznego, który
     *  aplikacja wyliczała z minimalnego wynagrodzenia (75%). Roczna suma poniżej
     *  to WYŁĄCZNIE matematyczny iloczyn 4 kwartałów — nie osobny limit z ustawy. */
    const val QUARTERLY_LIMIT_2026 = 10813.50
    const val YEARLY_INFO_2026 = 43254.0

    data class LimitStatus(
        val current: Double,
        val limit: Double
    ) {
        val ratio: Double get() = if (limit > 0) (current / limit).coerceAtLeast(0.0) else 0.0
        val percent: Int get() = (ratio * 100).toInt()
        val exceeded: Boolean get() = current > limit
    }

    /** Update: этап прогрессивной skali podatkowej, в котором сейчас находится
     *  накопленный годовой dochód пользователя — см. BracketStageStatus. */
    enum class BracketStage { TAX_FREE, RATE_12, RATE_32 }

    /**
     * taxableBase  — АБСОЛЮТНЫЙ накопленный годовой dochód (для подписи, всегда
     *                понятен пользователю независимо от текущего этапа).
     * barCurrent/barLimit — прогресс ВНУТРИ текущего этапа шкалы (для самого
     *                progress bar): например, на этапе RATE_12 barCurrent — это
     *                сколько уже "заполнено" ПОСЛЕ 30 000 zł, а barLimit — ширина
     *                этого сегмента (120 000 − 30 000 = 90 000 zł).
     */
    data class BracketStageStatus(
        val stage: BracketStage,
        val taxableBase: Double,
        val barCurrent: Double,
        val barLimit: Double
    ) {
        val percent: Int get() = if (barLimit > 0) ((barCurrent / barLimit) * 100).toInt().coerceIn(0, 100) else 100
    }

    data class AllLimits(
        val quarterly: LimitStatus,
        val yearlyIncomeSum: Double,
        val bracket: LimitStatus,
        val bracketStage: BracketStageStatus,
        val vat: LimitStatus,
        val activityType: ActivityType
    )

    /** Границы bieżącego kwartału kalendarzowego: [начало 1-го дня квартала,
     *  начало 1-го дня следующего квартала). Kwartały: Q1 sty-mar, Q2 kwi-cze,
     *  Q3 lip-wrz, Q4 paź-gru — zgodnie z ustawą (kwartał kalendarzowy). */
    fun quarterRange(now: Calendar): Pair<Long, Long> {
        val quarterStartMonth = (now.get(Calendar.MONTH) / 3) * 3
        val start = (now.clone() as Calendar).apply {
            set(Calendar.MONTH, quarterStartMonth)
            set(Calendar.DAY_OF_MONTH, 1)
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val end = (start.clone() as Calendar).apply { add(Calendar.MONTH, 3) }
        return start.timeInMillis to end.timeInMillis
    }

    /** Numer kwartału (1..4) dla danego kalendarza. */
    fun quarterNumber(cal: Calendar): Int = cal.get(Calendar.MONTH) / 3 + 1

    /** Czytelna etykieta kwartału do wyświetlenia pod gejdżem/w raporcie, np. "Q3 2026 (lip-wrz)". */
    fun quarterLabel(cal: Calendar): String {
        val q = quarterNumber(cal)
        val months = when (q) {
            1 -> "sty-mar"
            2 -> "kwi-cze"
            3 -> "lip-wrz"
            else -> "paź-gru"
        }
        return "Q$q ${cal.get(Calendar.YEAR)} ($months)"
    }

    suspend fun compute(context: Context): AllLimits {
        val db = AppDatabase.getInstance(context)
        val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
        val activityType = ActivityTypeHelper.get(prefs)

        val now = Calendar.getInstance()
        val (quarterStart, quarterEndExclusive) = quarterRange(now)
        val quarterIncome = db.entryDao().getIncomeBetween(quarterStart, quarterEndExclusive - 1).sumOf { it.amount }

        val year = TaxHelper.currentYear()
        val (yearStart, yearEndExclusive) = TaxHelper.yearRange(year)
        val yearEntries = db.entryDao().getBetween(yearStart, yearEndExclusive - 1)
        val yearIncome = yearEntries.filter { it.isIncome }.sumOf { it.amount }
        val yearExpense = yearEntries.filter { !it.isIncome }.sumOf { it.amount }
        val yearProfit = yearIncome - yearExpense
        val otherIncome = TaxHelper.getOtherIncome(prefs, year)
        val taxableBase = yearProfit + otherIncome

        val quarterlyStatus = LimitStatus(quarterIncome, QUARTERLY_LIMIT_2026)
        val bracketStatus = LimitStatus(taxableBase, TaxHelper.SECOND_BRACKET_THRESHOLD)

        // Update: prawidłowa dwuetapowa skala — 0% do ANNUAL_LIMIT (30 000 zł),
        // 12% od ANNUAL_LIMIT do SECOND_BRACKET_THRESHOLD (120 000 zł), 32%
        // powyżej. Stawka dotyczy TYLKO części ponad każdy próg (zgodnie z
        // TaxHelper.calc, który już liczy podatek w ten sposób) — tu odwzorowujemy
        // to samo na progress barze главного экрана.
        val bracketStage = when {
            taxableBase <= TaxHelper.ANNUAL_LIMIT ->
                BracketStageStatus(BracketStage.TAX_FREE, taxableBase, taxableBase.coerceAtLeast(0.0), TaxHelper.ANNUAL_LIMIT)
            taxableBase <= TaxHelper.SECOND_BRACKET_THRESHOLD ->
                BracketStageStatus(
                    BracketStage.RATE_12, taxableBase,
                    taxableBase - TaxHelper.ANNUAL_LIMIT,
                    TaxHelper.SECOND_BRACKET_THRESHOLD - TaxHelper.ANNUAL_LIMIT
                )
            else -> {
                val over = taxableBase - TaxHelper.SECOND_BRACKET_THRESHOLD
                BracketStageStatus(BracketStage.RATE_32, taxableBase, over, over)
            }
        }

        val vatStatus = LimitStatus(yearIncome, VAT_EXEMPT_LIMIT)

        return AllLimits(quarterlyStatus, yearIncome, bracketStatus, bracketStage, vatStatus, activityType)
    }

    /** Roczny limit zwolnienia podmiotowego z VAT (art. 113 ustawy o VAT), proporcjonalny w pierwszym roku. */
    const val VAT_EXEMPT_LIMIT = 240000.0
}
