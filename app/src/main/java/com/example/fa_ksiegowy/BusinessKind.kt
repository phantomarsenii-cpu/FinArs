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
    /**
     * Update: ekran "Typ sprzedaży" zostal usuniety z Ustawien — Magazyn jest
     * teraz stalym elementem dolnej nawigacji (zamiast warunkowego przycisku
     * na Start), wiec typ dzialalnosci jest zawsze traktowany jako MIXED
     * (sprzedaz + uslugi), co odblokowuje pelna funkcjonalnosc magazynu i
     * faktur dla kazdego uzytkownika bez potrzeby wyboru.
     */
    fun get(prefs: SharedPreferences): BusinessKind = BusinessKind.MIXED
}
