package com.example.fa_ksiegowy

/**
 * Считает итоговые цифры декларации за один календарный год: Przychód (сумма
 * всех доходов), Koszty (сумма всех расходов), Dochód (разница) и налог —
 * по той форме налогообложения, которую выбрал пользователь в настройках
 * (см. ActivityType):
 *
 *   NIEZAREJESTROWANA / JDG_SKALA → PIT-36,  skala podatkowa (TaxHelper.calc)
 *   JDG_LINIOWY                   → PIT-36L, podatek liniowy 19% (TaxHelper.calcLiniowy)
 *   JDG_RYCZALT                   → PIT-28,  ryczałt od przychodów (TaxHelper.calcRyczalt)
 *
 * Это НЕ официальный расчёт налоговой — только вспомогательная оценка на основе
 * введённых пользователем данных, чтобы не считать вручную перед подачей декларации.
 */
object Pit36Calculator {

    data class Result(
        val year: Int,
        val przychod: Double,
        val koszty: Double,
        val dochod: Double,
        val otherIncome: Double,
        val tax: TaxHelper.TaxResult,
        val activityType: ActivityType
    )

    fun calculate(
        entries: List<Entry>,
        year: Int,
        otherIncome: Double,
        activityType: ActivityType = ActivityType.NIEZAREJESTROWANA,
        ryczaltRatePercent: Double = 0.0
    ): Result {
        val przychod = entries.filter { it.isIncome }.sumOf { it.amount }
        val koszty = entries.filter { !it.isIncome }.sumOf { it.amount }
        val dochod = przychod - koszty

        val tax = when (activityType) {
            ActivityType.NIEZAREJESTROWANA, ActivityType.JDG_SKALA -> TaxHelper.calc(dochod, otherIncome)
            ActivityType.JDG_LINIOWY -> TaxHelper.calcLiniowy(dochod)
            ActivityType.JDG_RYCZALT -> TaxHelper.calcRyczalt(przychod, ryczaltRatePercent)
        }
        return Result(year, przychod, koszty, dochod, otherIncome, tax, activityType)
    }
}
