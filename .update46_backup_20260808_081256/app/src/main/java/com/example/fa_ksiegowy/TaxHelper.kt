package com.example.fa_ksiegowy

import android.content.SharedPreferences
import java.util.Calendar

/**
 * Официальная прогрессивная шкала налога (PIT) для działalność nierejestrowana:
 *
 *   • 0 – 30 000 zł/год за год        — 0%  (kwota wolna od podatku)
 *   • 30 000 – 120 000 zł/год         — 12% с суммы СВЕРХ 30 000 zł
 *   • свыше 120 000 zł/год            — 32% с суммы СВЕРХ 120 000 zł
 *
 * Важно: ставка применяется только к части дохода СВЕРХ каждого порога,
 * а не ко всей сумме целиком (раньше в приложении был плоский процент,
 * применённый ко всей налогооблагаемой сумме — это было неверно).
 *
 * "Прочие доходы" пользователя (otherIncome, вводятся вручную в настройках)
 * учитываются как занимающие нижние ступени шкалы ПЕРВЫМИ — налог, который
 * показывается в приложении, это налог именно с прибыли из приложения
 * (appProfit), рассчитанный маржинально поверх прочих доходов.
 */
object TaxHelper {

    const val ANNUAL_LIMIT = 30000.0
    const val SECOND_BRACKET_THRESHOLD = 120000.0
    private const val FIRST_BRACKET_RATE = 0.12
    private const val SECOND_BRACKET_RATE = 0.32

    data class TaxResult(
        val totalTaxable: Double,   // otherIncome + appProfit
        val taxBase: Double,        // appProfit (для обратной совместимости с UI)
        val tax: Double,            // налог, относящийся именно к прибыли из приложения
        val effectiveRatePercent: Double // эффективная ставка на appProfit, для отображения "Налог (X%)"
    )

    fun currentYear(): Int = Calendar.getInstance().get(Calendar.YEAR)

    /** Границы календарного года: [начало 1 января, начало 1 января следующего года). */
    fun yearRange(year: Int): Pair<Long, Long> {
        val start = Calendar.getInstance().apply {
            clear()
            set(year, Calendar.JANUARY, 1, 0, 0, 0)
        }.timeInMillis
        val end = Calendar.getInstance().apply {
            clear()
            set(year + 1, Calendar.JANUARY, 1, 0, 0, 0)
        }.timeInMillis
        return start to end
    }

    private fun otherIncomeKey(year: Int) = "otherIncome_$year"

    fun getOtherIncome(prefs: SharedPreferences, year: Int = currentYear()): Double =
        prefs.getFloat(otherIncomeKey(year), 0f).toDouble()

    fun setOtherIncome(prefs: SharedPreferences, year: Int, value: Double) {
        prefs.edit().putFloat(otherIncomeKey(year), value.toFloat()).apply()
    }

    /**
     * Официальная прогрессивная шкала PIT для действия nierejestrowana / ryczałt-подобного
     * случая, как её описал пользователь:
     *   • 0 – 30 000 zł/год       — 0% (kwota wolna od podatku)
     *   • 30 000 – 120 000 zł/год — 12% с суммы СВЕРХ 30 000 (не со всей суммы!)
     *   • свыше 120 000 zł/год    — 32% с суммы СВЕРХ 120 000, плюс фиксированные
     *                               (120 000 − 30 000) × 12% с предыдущей ступени
     * Считает налог на весь годовой налогооблагаемый доход целиком (без разбивки
     * по источникам) — используется как вспомогательная функция ниже.
     */
    private fun bracketTax(annualIncome: Double): Double {
        val income = if (annualIncome < 0) 0.0 else annualIncome
        return when {
            income <= ANNUAL_LIMIT -> 0.0
            income <= SECOND_BRACKET_THRESHOLD -> (income - ANNUAL_LIMIT) * FIRST_BRACKET_RATE
            else -> (SECOND_BRACKET_THRESHOLD - ANNUAL_LIMIT) * FIRST_BRACKET_RATE +
                (income - SECOND_BRACKET_THRESHOLD) * SECOND_BRACKET_RATE
        }
    }

    /**
     * Считаем налог, относящийся к прибыли ИЗ ПРИЛОЖЕНИЯ (appProfit), с учётом того,
     * что "прочие доходы" (otherIncome) занимают нижние ступени шкалы первыми —
     * это стандартный маржинальный подход: appProfit облагается по тем ступеням
     * шкалы, которые остаются НАД уже "использованными" прочими доходами.
     *
     * Пример (как в вопросе пользователя): appProfit = 234 400, otherIncome = 0.
     *   taxOnCombined = (120000-30000)*12% + (234400-120000)*32% = 10800 + 36608 = 47408
     *   taxOnOtherOnly = 0 (прочих доходов нет)
     *   tax = 47408 — именно эта сумма должна отображаться, а не плоские 12%.
     */
    fun calc(appProfit: Double, otherIncome: Double): TaxResult {
        val other = if (otherIncome < 0) 0.0 else otherIncome
        val app = if (appProfit < 0) 0.0 else appProfit
        val combined = other + app

        val taxOnOtherOnly = bracketTax(other)
        val taxOnCombined = bracketTax(combined)
        val tax = taxOnCombined - taxOnOtherOnly

        val effectiveRate = if (app > 0) (tax / app) * 100.0 else 0.0
        return TaxResult(combined, app, tax, effectiveRate)
    }

    const val LINIOWY_RATE = 0.19

    /**
     * Podatek liniowy (19%) — плоская ставка без kwoty wolnej od podatku и без
     * прогрессии; применяется ко всему dochód (przychód − koszty), otherIncome
     * здесь не влияет на ставку прибыли из приложения (в отличие от skali),
     * так как нет порогов — 19% от appProfit целиком.
     */
    fun calcLiniowy(appProfit: Double): TaxResult {
        val app = if (appProfit < 0) 0.0 else appProfit
        val tax = app * LINIOWY_RATE
        return TaxResult(app, app, tax, LINIOWY_RATE * 100.0)
    }

    /**
     * Ryczałt od przychodów ewidencjonowanych: налог считается от PRZYCHODU
     * (не dochodu — koszty не вычитаются) по ставке, которая зависит от вида
     * деятельности (PKD) и вводится пользователем вручную в настройках
     * (2–17%, см. ustawa o ryczałcie).
     */
    fun calcRyczalt(przychod: Double, ratePercent: Double): TaxResult {
        val p = if (przychod < 0) 0.0 else przychod
        val rate = (if (ratePercent < 0) 0.0 else ratePercent) / 100.0
        val tax = p * rate
        return TaxResult(p, p, tax, ratePercent)
    }

    /**
     * Текст динамической подписи налога на главном экране/в отчётах — см. п.2 требований.
     * Как только доход попадает во второй порог (>120 000 zł), надпись однозначно
     * называет действующую предельную ставку — 32% — вместо "12% / 32%", которая
     * при переносе строки на узком экране визуально сливалась с суммой налога
     * и вводила пользователя в заблуждение (12 или 32?).
     */
    fun taxLabelResId(taxableBase: Double): Int = when {
        taxableBase <= ANNUAL_LIMIT -> R.string.tax_label_zero
        taxableBase <= SECOND_BRACKET_THRESHOLD -> R.string.tax_label_12
        else -> R.string.tax_label_32
    }
}
