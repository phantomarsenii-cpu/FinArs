package com.example.fa_ksiegowy

import android.content.Intent
import androidx.activity.addCallback
import android.os.Bundle
import android.text.format.DateFormat
import android.widget.Button
import android.widget.CheckBox
import android.widget.TextView
import java.util.Date

/**
 * Экран пользовательского соглашения и отказа от ответственности.
 *
 * Режим "первое согласие" (readOnly = false, по умолчанию):
 * показывается текст, чекбокс и кнопка "Принять и продолжить" (активна
 * только при отмеченном чекбоксе). После принятия флаг сохраняется
 * НАВСЕГДА (KEY_TERMS_ACCEPTED) и отозвать его из приложения нельзя.
 * 
 * После принятия Terms проверяется, выбран ли пользователем тип деятельности.
 * Если нет (is_tax_type_selected == false), направляется на SettingsTaxActivity
 * для обязательного выбора, иначе на MainActivity.
 *
 * Режим "просмотр" (readOnly = true) — вызывается из Настроек:
 * чекбокс и кнопка принятия скрыты, внизу показана плашка со статусом
 * и датой принятия, доступна только кнопка "Закрыть".
 */
class TermsActivity : BaseActivity() {

    companion object {
        const val PREFS_NAME = "settings"
        const val KEY_TERMS_ACCEPTED = "terms_accepted"
        const val KEY_TERMS_ACCEPTED_TIMESTAMP = "terms_accepted_timestamp"
        const val EXTRA_READ_ONLY = "read_only"

        fun isAccepted(context: android.content.Context): Boolean {
            val prefs = context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
            return prefs.getBoolean(KEY_TERMS_ACCEPTED, false)
        }
    }

    private var readOnly: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_terms)

        readOnly = intent.getBooleanExtra(EXTRA_READ_ONLY, false)
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)

        findViewById<TextView>(R.id.tv_terms_body).text = getString(R.string.terms_full_text)

        val checkbox = findViewById<CheckBox>(R.id.cb_terms_accept)
        val btnAccept = findViewById<Button>(R.id.btn_terms_accept)
        val btnClose = findViewById<Button>(R.id.btn_terms_close)
        val statusBanner = findViewById<TextView>(R.id.tv_terms_status)

        if (readOnly) {
            checkbox.visibility = android.view.View.GONE
            btnAccept.visibility = android.view.View.GONE
            btnClose.visibility = android.view.View.VISIBLE

            val ts = prefs.getLong(KEY_TERMS_ACCEPTED_TIMESTAMP, -1L)
            statusBanner.visibility = android.view.View.VISIBLE
            statusBanner.text = if (ts > 0) {
                val formatted = DateFormat.format("dd.MM.yyyy HH:mm", Date(ts))
                getString(R.string.terms_status_accepted, formatted)
            } else {
                getString(R.string.terms_status_unknown)
            }

            btnClose.setOnClickListener { finish() }
        } else {
            checkbox.visibility = android.view.View.VISIBLE
            btnAccept.visibility = android.view.View.VISIBLE
            btnClose.visibility = android.view.View.GONE
            statusBanner.visibility = android.view.View.GONE

            btnAccept.isEnabled = false
            checkbox.setOnCheckedChangeListener { _, isChecked ->
                btnAccept.isEnabled = isChecked
            }

            btnAccept.setOnClickListener {
                if (!checkbox.isChecked) return@setOnClickListener
                prefs.edit()
                    .putBoolean(KEY_TERMS_ACCEPTED, true)
                    .putLong(KEY_TERMS_ACCEPTED_TIMESTAMP, System.currentTimeMillis())
                    .apply()
                
                // Проверить, выбран ли тип деятельности
                val isTaxTypeSelected = prefs.getBoolean("is_tax_type_selected", false)
                val nextIntent = if (!isTaxTypeSelected) {
                    // Обязательный выбор типа деятельности
                    Intent(this, SettingsTaxActivity::class.java)
                } else {
                    // Переход на главную страницу
                    Intent(this, MainActivity::class.java)
                }
                startActivity(nextIntent)
                finish()
            }

            // Первичное согласие нельзя обойти системной кнопкой "назад".
            onBackPressedDispatcher.addCallback(this, true) {
                /* no-op: блокируем выход системной кнопкой "назад",
                   пока соглашение не принято */
            }
        }
    }
}
