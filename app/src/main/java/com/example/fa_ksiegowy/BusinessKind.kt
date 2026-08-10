package com.example.fa_ksiegowy

import android.content.SharedPreferences

/**
 * Тип деятельности пользователя, выбираемый в настройках. От него зависит,
 * появляется ли на главном экране кнопка "Склад" (Magazin) и связанная
 * логика списания товара при выставлении фактуры.
 */
enum class BusinessKind {
    SALES,
    SERVICES,
    MIXED;

    val showsMagazin: Boolean get() = this == SALES || this == MIXED
}

object BusinessKindHelper {
    private const val KEY = "business_kind"

    fun get(prefs: SharedPreferences): BusinessKind {
        val raw = prefs.getString(KEY, BusinessKind.SERVICES.name) ?: BusinessKind.SERVICES.name
        return try {
            BusinessKind.valueOf(raw)
        } catch (e: IllegalArgumentException) {
            BusinessKind.SERVICES
        }
    }

    fun set(prefs: SharedPreferences, kind: BusinessKind) {
        prefs.edit().putString(KEY, kind.name).apply()
    }
}
