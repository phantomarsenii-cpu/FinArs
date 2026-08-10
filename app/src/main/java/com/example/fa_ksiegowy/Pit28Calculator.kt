package com.example.fa_ksiegowy

import kotlin.math.roundToInt

/**
 * PIT-28 Ryczałt (Lump-sum tax) для зарегистрированной JDG деятельности
 * 
 * Расчет налога на основе ДОХОДА (не расходов).
 * Налоговые ставки зависят от PKD (Polska Klasyfikacja Działalności):
 * 2%, 3%, 5.5%, 8.5%, 10%, 12%, 12.5%, 14%, 15%, 17%
 * 
 * Формула:
 * НалогКРычалт = Przychód * СтавкаРычалту (зависит от PKD)
 * 
 * С поддержкой:
 * - Нескольких ставок ryczałtu на одной деятельности
 * - ZUS и страховка здоровья (вычитаются перед налогом)
 * - Различные льготы (в пределах 85 528 PLN)
 */
object Pit28Calculator {
    
    private const val RELIEFS_LIMIT = 85_528.0  // Максимум льгот в год
    private const val ZUS_RATE = 0.20
    
    data class RyczaltRate(
        val ratePercent: Double,  // 2.0, 3.0, 5.5, 8.5, 10.0, 12.0, 12.5, 14.0, 15.0, 17.0
        val pkdCode: String = "",  // Пример: "J58.11.Z" для консалтинга
        val beschreibung: String = ""
    )
    
    data class IncomeByRate(
        val rate: RyczaltRate,
        val amount: Double  // Доход по этой ставке
    )
    
    data class Pit28Data(
        val year: Int,
        val incomeByRates: List<IncomeByRate>,  // Список доходов с разными ставками
        val zusContribution: Double = 0.0,
        val healthInsurance: Double = 0.0,
        val reliefs: Double = 0.0
    )
    
    data class TaxLineItem(
        val rate: RyczaltRate,
        val income: Double,
        val taxGross: Double,
        val taxRounded: Double
    )
    
    data class Result(
        val year: Int,
        val totalIncome: Double,
        val totalZusDeduction: Double,
        val totalHealthDeduction: Double,
        val totalDeductions: Double,
        val incomeAfterDeductions: Double,
        val reliefs: Double,
        val taxLineItems: List<TaxLineItem>,
        val taxGrossTotal: Double,
        val taxTotal: Double,
        val netIncome: Double
    )
    
    /**
     * Расчет налога с несколькими ставками
     */
    fun calculate(data: Pit28Data): Result {
        // 1. Общий доход
        val totalIncome = data.incomeByRates.sumOf { it.amount }
        
        // 2. Вычеты ZUS и страховки
        val zusDeduction = data.zusContribution.coerceAtLeast(0.0)
        val healthDeduction = data.healthInsurance.coerceAtLeast(0.0)
        val totalDeductions = zusDeduction + healthDeduction
        
        val incomeAfterDeductions = (totalIncome - totalDeductions).coerceAtLeast(0.0)
        
        // 3. Применить льготы (лимит 85 528 PLN)
        val reliefAmount = data.reliefs.coerceAtMost(RELIEFS_LIMIT)
        val incomeAfterReliefs = (incomeAfterDeductions - reliefAmount).coerceAtLeast(0.0)
        
        // 4. Пропорциональное распределение льгот по ставкам
        val proportionalReliefs = distributeProportionally(
            totalAmount = reliefAmount,
            byRates = data.incomeByRates
        )
        
        // 5. Рассчитать налог для каждой ставки
        val lineItems = mutableListOf<TaxLineItem>()
        var taxGrossTotal = 0.0
        var taxTotalRounded = 0.0
        
        for ((index, incomeItem) in data.incomeByRates.withIndex()) {
            // Применить пропорциональное разделение льгот
            val incomeAfterRelief = (incomeItem.amount - (proportionalReliefs[index] ?: 0.0))
                .coerceAtLeast(0.0)
            
            val taxGross = incomeAfterRelief * (incomeItem.rate.ratePercent / 100.0)
            val taxRounded = taxGross.roundToInt().toDouble()
            
            lineItems.add(
                TaxLineItem(
                    rate = incomeItem.rate,
                    income = incomeItem.amount,
                    taxGross = taxGross,
                    taxRounded = taxRounded
                )
            )
            
            taxGrossTotal += taxGross
            taxTotalRounded += taxRounded
        }
        
        // 6. Чистый доход
        val netIncome = totalIncome - taxTotalRounded
        
        return Result(
            year = data.year,
            totalIncome = totalIncome,
            totalZusDeduction = zusDeduction,
            totalHealthDeduction = healthDeduction,
            totalDeductions = totalDeductions,
            incomeAfterDeductions = incomeAfterDeductions,
            reliefs = reliefAmount,
            taxLineItems = lineItems,
            taxGrossTotal = taxGrossTotal,
            taxTotal = taxTotalRounded,
            netIncome = netIncome
        )
    }
    
    /**
     * Расчет для одной ставки (упрощенный вариант)
     */
    fun calculateSimple(
        year: Int,
        przychod: Double,
        ratePercent: Double,
        zusContribution: Double = 0.0,
        healthInsurance: Double = 0.0,
        reliefs: Double = 0.0
    ): Result {
        val incomeByRates = listOf(
            IncomeByRate(
                rate = RyczaltRate(ratePercent = ratePercent),
                amount = przychod
            )
        )
        
        val data = Pit28Data(
            year = year,
            incomeByRates = incomeByRates,
            zusContribution = zusContribution,
            healthInsurance = healthInsurance,
            reliefs = reliefs
        )
        
        return calculate(data)
    }
    
    /**
     * Расчет с автоматическим расчетом ZUS
     */
    fun calculateAuto(
        year: Int,
        przychod: Double,
        ratePercent: Double,
        reliefs: Double = 0.0
    ): Result {
        // Автоматический ZUS (~20% от дохода)
        val automaticZus = (przychod * ZUS_RATE).coerceAtMost(10_000.0)
        
        return calculateSimple(
            year = year,
            przychod = przychod,
            ratePercent = ratePercent,
            zusContribution = automaticZus,
            reliefs = reliefs
        )
    }
    
    /**
     * Распределение льгот пропорционально доходам по ставкам
     */
    private fun distributeProportionally(
        totalAmount: Double,
        byRates: List<IncomeByRate>
    ): Map<Int, Double> {
        if (totalAmount <= 0.0 || byRates.isEmpty()) {
            return emptyMap()
        }
        
        val totalIncome = byRates.sumOf { it.amount }
        if (totalIncome <= 0.0) return emptyMap()
        
        return byRates.mapIndexed { index, item ->
            val proportion = item.amount / totalIncome
            index to (totalAmount * proportion)
        }.toMap()
    }
    
    /**
     * Генератор типовых ставок по PKD
     */
    fun getStandardRate(pkdCategory: String): RyczaltRate {
        return when (pkdCategory.lowercase()) {
            "consulting", "j58.11" -> RyczaltRate(ratePercent = 3.0, pkdCode = "J58.11.Z")
            "it_services", "j62.01" -> RyczaltRate(ratePercent = 12.0, pkdCode = "J62.01.Z")
            "repair", "s95.11" -> RyczaltRate(ratePercent = 8.5, pkdCode = "S95.11.Z")
            "transport", "h49.39" -> RyczaltRate(ratePercent = 8.5, pkdCode = "H49.39.Z")
            "retail", "g47.19" -> RyczaltRate(ratePercent = 5.5, pkdCode = "G47.19.Z")
            else -> RyczaltRate(ratePercent = 12.0)  // Default
        }
    }
}
