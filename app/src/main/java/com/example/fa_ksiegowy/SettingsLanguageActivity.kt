package com.example.fa_ksiegowy

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.ImageView
import android.widget.Toast

/** Выбор языка приложения. Тап по строке языка только переставляет точку-индикатор
 *  (выбор ещё не применяется); реальное применение языка происходит по кнопке
 *  "Сохранить" — она сохраняет выбор, показывает короткое уведомление (ещё на
 *  СТАРОМ языке — экран в этот момент физически ещё не пересобран) и только потом
 *  перезапускает MainActivity как единственный экран в задаче, чтобы весь UI (в т.ч.
 *  уже открытые экраны) пересобрался с новой локалью. */
class SettingsLanguageActivity : BaseActivity() {

    private lateinit var langRows: Map<String, View>
    private lateinit var langRadios: Map<String, ImageView>
    private var pendingLanguage: String = "en"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings_language)

        langRows = mapOf(
            "en" to findViewById(R.id.row_lang_en),
            "ru" to findViewById(R.id.row_lang_ru),
            "pl" to findViewById(R.id.row_lang_pl),
            "uk" to findViewById(R.id.row_lang_uk)
        )
        langRadios = mapOf(
            "en" to findViewById(R.id.radio_lang_en),
            "ru" to findViewById(R.id.radio_lang_ru),
            "pl" to findViewById(R.id.radio_lang_pl),
            "uk" to findViewById(R.id.radio_lang_uk)
        )

        findViewById<View>(R.id.iv_back).setOnClickListener { finish() }
        langRows.forEach { (code, row) -> row.setOnClickListener { selectPending(code) } }
        findViewById<View>(R.id.btn_save_language).setOnClickListener { saveLanguage() }

        // Первый запуск SettingsLanguageActivity уже идёт после attachBaseContext ->
        // LocaleHelper.applyLocale(), который на самом первом старте приложения сам
        // определяет и сохраняет системный язык (или "en", если он не поддерживается).
        // Поэтому здесь достаточно просто прочитать уже сохранённое значение — точка
        // сразу встанет на реально установленный сейчас язык.
        selectPending(LocaleHelper.getLanguage(this))
    }

    private fun selectPending(code: String) {
        pendingLanguage = code
        langRadios.forEach { (rowCode, radio) ->
            radio.setImageResource(
                if (rowCode == code) R.drawable.ic_radio_selected else R.drawable.ic_radio_unselected
            )
        }
    }

    private fun saveLanguage() {
        // Уведомление показываем ДО применения нового языка — контекст этой Activity
        // ещё несёт ресурсы СТАРОГО языка (getString здесь вернёт "Сохранено" и т.п.
        // на языке, который был установлен до сохранения).
        Toast.makeText(this, getString(R.string.saved), Toast.LENGTH_SHORT).show()

        LocaleHelper.setLanguage(this, pendingLanguage)

        val intent = Intent(this, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        startActivity(intent)
        finishAffinity()
    }
}
