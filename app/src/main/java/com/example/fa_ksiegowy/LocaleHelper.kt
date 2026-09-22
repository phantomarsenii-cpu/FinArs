package com.example.fa_ksiegowy

import android.content.Context
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
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
        // Update: наш собственный подход (createConfigurationContext в attachBaseContext +
        // ручной перезапуск MainActivity) на некоторых устройствах/версиях Android не
        // обновлял язык у уже созданных Activity — например, если MainActivity была
        // launchMode="singleTask" и переиспользовалась системой вместо пересоздания.
        // AppCompatDelegate.setApplicationLocales() — официальный механизм AndroidX для
        // смены языка приложения: он сам корректно пересоздаёт (recreate) ВСЕ активные
        // Activity с новой конфигурацией, независимо от launchMode. Вызываем его здесь
        // же, чтобы оба механизма всегда были синхронизированы.
        AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(code))
    }

    /** Синхронизирует AppCompatDelegate с уже сохранённым языком — вызывается один раз
     *  при старте процесса (FaApp.onCreate), ДО создания первой Activity. */
    fun syncAppCompatDelegate(context: Context) {
        AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(getOrInitLanguage(context)))
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
