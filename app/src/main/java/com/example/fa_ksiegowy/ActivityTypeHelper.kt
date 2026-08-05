package com.example.fa_ksiegowy

import android.content.SharedPreferences

/**
 * Тип деятельности пользователя — от него зависят применяемые лимиты
 * и то, какая декларация (PIT-36 / PIT-36L / PIT-28) актуальна.
 *
 *  NIEZAREJESTROWANA — działalność nierejestrowana (без регистрации JDG в CEIDG).
 *                       Лимит: przychód (доход) в МЕСЯЦ не должен превышать 75%
 *                       kwoty minimalnego wynagrodzenia. При превышении в течение
 *                       7 дней возникает обязанность зарегистрировать JDG.
 *                       Подаётся через PIT-36 по skala podatkowa.
 *  JDG_SKALA         — зарегистрированное ИП (JDG), skala podatkowa 12%/32% → PIT-36.
 *  JDG_LINIOWY       — JDG, podatek liniowy 19% (без kwoty wolnej) → PIT-36L.
 *  JDG_RYCZALT       — JDG, ryczałt od przychodów ewidencjonowanych → PIT-28.
 */
enum class ActivityType(val formCode: String) {
    NIEZAREJESTROWANA("PIT-36"),
    JDG_SKALA("PIT-36"),
    JDG_LINIOWY("PIT-36L"),
    JDG_RYCZALT("PIT-28");

    val isRegisteredJdg: Boolean get() = this != NIEZAREJESTROWANA
}

object ActivityTypeHelper {
    private const val KEY = "activity_type"
    private const val KEY_RYCZALT_RATE = "ryczalt_rate_percent"

    /**
     * Minimalne wynagrodzenie za pracę — используется для расчёта лимита
     * działalności nierejestrowanej (75% от этой суммы в месяц).
     * Значение нужно проверять и обновлять ежегодно (устанавливается
     * rozporządzeniem Rady Ministrów) — здесь задано отдельным ключом
     * в настройках, чтобы пользователь мог поправить его сам, если
     * приложение не переиздавалось после изменения ставки.
     */
    private const val KEY_MIN_WAGE = "minimalne_wynagrodzenie"
    const val DEFAULT_MIN_WAGE = 4666.0 // zł/mies., проверьте актуальное значение на дату использования

    fun getMinWage(prefs: SharedPreferences): Double {
        val v = prefs.getFloat(KEY_MIN_WAGE, DEFAULT_MIN_WAGE.toFloat()).toDouble()
        return if (v <= 0.0) DEFAULT_MIN_WAGE else v
    }

    fun setMinWage(prefs: SharedPreferences, value: Double) {
        prefs.edit().putFloat(KEY_MIN_WAGE, value.toFloat()).apply()
    }

    /** Месячный лимит дохода для działalności nierejestrowanej = 75% minimalnego wynagrodzenia. */
    fun nierejestrowanaMonthlyLimit(prefs: SharedPreferences): Double = getMinWage(prefs) * 0.75

    fun get(prefs: SharedPreferences): ActivityType {
        val name = prefs.getString(KEY, ActivityType.NIEZAREJESTROWANA.name)
        return try {
            ActivityType.valueOf(name ?: ActivityType.NIEZAREJESTROWANA.name)
        } catch (e: IllegalArgumentException) {
            ActivityType.NIEZAREJESTROWANA
        }
    }

    fun set(prefs: SharedPreferences, type: ActivityType) {
        prefs.edit().putString(KEY, type.name).apply()
    }

    /** Ставка ryczałtu в процентах (2–17%, зависит от вида деятельности — PKD) — вводится вручную. */
    fun getRyczaltRate(prefs: SharedPreferences): Double =
        prefs.getFloat(KEY_RYCZALT_RATE, 0f).toDouble()

    fun setRyczaltRate(prefs: SharedPreferences, percent: Double) {
        prefs.edit().putFloat(KEY_RYCZALT_RATE, percent.toFloat()).apply()
    }
}
