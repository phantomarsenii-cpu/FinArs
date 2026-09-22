package com.example.fa_ksiegowy

import android.content.Context
import java.util.Locale

object LocaleHelper {
    private const val PREFS_NAME = "settings"
    private const val KEY_LANG = "appLang"
    private val SUPPORTED = setOf("ru", "pl", "en", "uk")

    fun applyLocale(context: Context): Context {
        val lang = getOrInitLanguage(context)
        return updateContextLocale(context, lang)
    }

    fun setLanguage(context: Context, code: String) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putString(KEY_LANG, code).apply()
    }

    /** Текущий язык приложения — сохранённый выбор пользователя, а если его ещё
     *  нет (самый первый запуск), тот же язык, что определит и сохранит applyLocale:
     *  системный, если он поддерживается, иначе английский. */
    fun getLanguage(context: Context): String = getOrInitLanguage(context)

    private fun getOrInitLanguage(context: Context): String {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val saved = prefs.getString(KEY_LANG, null)
        if (saved != null) return saved
        val systemLang = Locale.getDefault().language
        val initial = if (SUPPORTED.contains(systemLang)) systemLang else "en"
        prefs.edit().putString(KEY_LANG, initial).apply()
        return initial
    }

    private fun updateContextLocale(context: Context, lang: String): Context {
        val locale = Locale(lang)
        Locale.setDefault(locale)
        val config = context.resources.configuration
        config.setLocale(locale)
        return context.createConfigurationContext(config)
    }
}
