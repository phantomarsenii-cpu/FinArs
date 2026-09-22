package com.example.fa_ksiegowy

import android.content.Intent
import android.os.Bundle
import android.widget.Button

/** Выбор языка приложения. Смена языка перезапускает MainActivity как единственный
 *  экран в задаче, чтобы весь UI (в т.ч. уже открытые экраны) пересобрался с новой локалью. */
class SettingsLanguageActivity : BaseActivity() {

    private lateinit var langButtons: Map<String, Button>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings_language)

        langButtons = mapOf(
            "en" to findViewById(R.id.btn_lang_en),
            "ru" to findViewById(R.id.btn_lang_ru),
            "pl" to findViewById(R.id.btn_lang_pl),
            "uk" to findViewById(R.id.btn_lang_uk)
        )

        findViewById<android.view.View>(R.id.iv_back).setOnClickListener { finish() }
        langButtons.forEach { (code, button) -> button.setOnClickListener { setLocale(code) } }

        // Первый запуск SettingsLanguageActivity уже идёт после attachBaseContext ->
        // LocaleHelper.applyLocale(), который на самом первом старте приложения сам
        // определяет и сохраняет системный язык (или "en", если он не поддерживается).
        // Поэтому здесь достаточно просто прочитать уже сохранённое значение.
        highlightSelected(LocaleHelper.getLanguage(this))
    }

    private fun highlightSelected(selectedCode: String) {
        langButtons.forEach { (code, button) ->
            button.setBackgroundResource(
                if (code == selectedCode) R.drawable.btn_pill_primary else R.drawable.btn_pill_outline
            )
        }
    }

    private fun setLocale(code: String) {
        LocaleHelper.setLanguage(this, code)
        highlightSelected(code)
        val intent = Intent(this, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        startActivity(intent)
        finishAffinity()
    }
}
