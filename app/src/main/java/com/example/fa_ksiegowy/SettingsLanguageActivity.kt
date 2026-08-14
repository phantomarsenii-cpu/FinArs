package com.example.fa_ksiegowy

import android.content.Intent
import android.os.Bundle
import android.widget.Button

/** Выбор языка приложения. Смена языка перезапускает MainActivity как единственный
 *  экран в задаче, чтобы весь UI (в т.ч. уже открытые экраны) пересобрался с новой локалью. */
class SettingsLanguageActivity : BaseActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings_language)

        findViewById<android.view.View>(R.id.iv_back).setOnClickListener { finish() }
        findViewById<Button>(R.id.btn_lang_en).setOnClickListener { setLocale("en") }
        findViewById<Button>(R.id.btn_lang_ru).setOnClickListener { setLocale("ru") }
        findViewById<Button>(R.id.btn_lang_pl).setOnClickListener { setLocale("pl") }
    }

    private fun setLocale(code: String) {
        LocaleHelper.setLanguage(this, code)
        val intent = Intent(this, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        startActivity(intent)
        finishAffinity()
    }
}
