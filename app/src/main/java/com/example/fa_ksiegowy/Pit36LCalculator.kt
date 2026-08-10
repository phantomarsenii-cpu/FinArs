package com.example.fa_ksiegowy

import kotlin.math.roundToInt

/**
 * PIT-36L(21) Линейный налог (19%) для зарегистрированной JDG деятельности
 * 
 * Формула расчета:
 * Dochód = Przychód - Koszty
 * Налог = Dochód * 19%
 * 
 * С поддержкой льгот:
 * - Ulga na powrót (art. 21 ust. 1 pkt 152)
 * - Ulga dla rodzin 4+ (art. 21 ust. 1 pkt 153)
 * - Ulga dla pracujących seniorów (art. 21 ust. 1 pkt 154)
 * - Общий лимит льгот: 85 528 PLN в год
 */
object Pit36LCalculator {
    
    private const val TAX_RATE = 0.19  // 19% линейный налог
    private const val RELIEFS_LIMIT = 85_528.0  // Максимум льгот в год
    private const val ZUS_RATE = 0.20  // Примерный процент ZUS (социальные взносы)
    private const val HEALTH_INSURANCE_RATE = 0.09  // Страховка здоровья
    
    data class Pit36LData(
        val year: Int,
        val przychod: Double,  // Доход (sales)
        val koszty: Double,    // Расходы (costs)
        val zusContribution: Double = 0.0,  // Взносы ZUS
        val healthInsurance: Double = 0.0,  // Страховка здоровья
        val reliefs: Reliefs = Reliefs()
    )
    
    data class Reliefs(
        val ulgaNaPowrot: Double = 0.0,  // Ulga na powrót
        val ulgaDzialnosci: Double = 0.0,  // Ulga dla rodzin 4+ (дочерняя версия)
        val ulgaSenior: Double = 0.0      // Ulga dla seniorów
    ) {
        fun total(): Double = ulgaNaPowrot + ulgaDzialnosci + ulgaSenior
    }
    
    data class Result(
        val przychod: Double,
        val koszty: Double,
        val dochod: Double,
        val taxableIncome: Double,  // После вычетов ZUS и здоровья
        val reliefs: Double,
        val taxableAfterReliefs: Double,
        val taxGross: Double,  // Налог до округления
        val tax: Double,       // Налог после округления до целых PLN
        val netIncome: Double  // Доход после налога
    )
    
    /**
     * Главный расчетный метод
     */
    fun calculate(data: Pit36LData): Result {
        // 1. Базовый доход
        val dochod = (data.przychod - data.koszty).coerceAtLeast(0.0)
        
        // 2. Вычеты ZUS и страховки здоровья (перед налогом)
        val zusDeduction = data.zusContribution.coerceAtLeast(0.0)
        val healthDeduction = data.healthInsurance.coerceAtLeast(0.0)
        val deductions = zusDeduction + healthDeduction
        
        val taxableIncome = (dochod - deductions).coerceAtLeast(0.0)
        
        // 3. Применить льготы (с лимитом 85 528 PLN)
        val reliefAmount = data.reliefs.total().coerceAtMost(RELIEFS_LIMIT)
        val taxableAfterReliefs = (taxableIncome - reliefAmount).coerceAtLeast(0.0)
        
        // 4. Рассчитать налог (19%)
        val taxGross = taxableAfterReliefs * TAX_RATE
        
        // 5. Округлить налог (математическое округление до целых PLN)
        // По Ordynacja Podatkowa: обычно округление в большую сторону
        val tax = taxGross.roundToInt().toDouble()
        
        // 6. Чистый доход
        val netIncome = dochod - tax
        
        return Result(
            przychod = data.przychod,
            koszty = data.koszty,
            dochod = dochod,
            taxableIncome = taxableIncome,
            reliefs = reliefAmount,
            taxableAfterReliefs = taxableAfterReliefs,
            taxGross = taxGross,
            tax = tax,
            netIncome = netIncome
        )
    }
    
    /**
     * Калькулятор с автоматическим расчетом ZUS на основе дохода
     */
    fun calculateAuto(
        year: Int,
        przychod: Double,
        koszty: Double,
        reliefs: Reliefs = Reliefs()
    ): Result {
        val dochod = (przychod - koszty).coerceAtLeast(0.0)
        
        // Автоматический расчет ZUS (~20% от дохода)
        val automaticZus = (dochod * ZUS_RATE).coerceAtMost(10_000.0)  // Лимит ZUS
        val automaticHealth = (dochod * HEALTH_INSURANCE_RATE).coerceAtMost(5_000.0)
        
        val data = Pit36LData(
            year = year,
            przychod = przychod,
            koszty = koszty,
            zusContribution = automaticZus,
            healthInsurance = automaticHealth,
            reliefs = reliefs
        )
        
        return calculate(data)
    }
}
