package com.example.fa_ksiegowy

import android.content.SharedPreferences

/**
 * Тип деятельности пользователя — от него зависят применяемые лимиты
 * и то, какая декларация (PIT-36 / PIT-36L / PIT-28) актуальна.
 *
 *  NIEZAREJESTROWANA — działalność nierejestrowana (без регистрации JDG в CEIDG).
 *                       Лимит (od 01.01.2026): przychód (доход) в КВАРТАЛЕ не должен
 *                       превышать 10 813,50 zł (стала кwota, зоб. LimitsHelper.
 *                       QUARTERLY_LIMIT_2026). При превышении в течение 7 дней
 *                       возникает обязанность зарегистрировать JDG.
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

    // Update (2026): stary miesięczny limit 75% minimalnego wynagrodzenia został
    // usunięty razem z polem do ręcznego wpisania minimalnego wynagrodzenia — limit
    // działalności nierejestrowanej jest teraz kwartalny i stały (zob.
    // LimitsHelper.QUARTERLY_LIMIT_2026 = 10 813,50 zł), niezależny od minimalnego
    // wynagrodzenia.

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
